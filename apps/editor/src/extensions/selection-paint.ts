import { Extension } from '@tiptap/core'
import { AllSelection, Plugin, PluginKey, TextSelection, type EditorState } from '@tiptap/pm/state'
import type { EditorView } from '@tiptap/pm/view'
import { Decoration, DecorationSet } from '@tiptap/pm/view'

/** Plugin state: whether a mouse drag is selecting (the drag layer paints meanwhile). */
export const SelectionPaintKey = new PluginKey<{ dragging: boolean }>('selectionPaint')

/**
 * The page paints a text selection itself, on the text only (as the AI range is): the browser's own paint covers
 * whole line boxes across blocks — list numbers, the gaps between items — and looks broken there.
 *
 * Settled selections are a decoration. While the mouse is still dragging, re-drawing the text under the pointer
 * would cut the browser's drag-selection short, so a layer behind the page draws the selected characters' boxes
 * instead (nothing in the text changes) until the button is released. Fields inside the page keep the browser's
 * selection; table cell selections keep their own style.
 */
export const SelectionPaint = Extension.create({
  name: 'selectionPaint',

  addProseMirrorPlugins() {
    return [
      new Plugin({
        key: SelectionPaintKey,
        state: {
          init: () => ({ dragging: false }),
          apply: (tr, value) => {
            const dragging = tr.getMeta(SelectionPaintKey) as boolean | undefined
            return dragging === undefined ? value : { dragging }
          }
        },
        view: (view) => new DragLayer(view),
        props: {
          handleDOMEvents: {
            mousedown: (view, event) => {
              if (event.button === 0) view.dispatch(view.state.tr.setMeta(SelectionPaintKey, true))
              return false
            }
          },
          // Past the limit the browser paints (the class that hides its paint goes with the decoration).
          attributes: (state): Record<string, string> =>
            paintsItself(state) ? { class: 'hk-own-selection' } : {},
          decorations: (state) => {
            const { selection } = state
            if (selection.empty || SelectionPaintKey.getState(state)?.dragging) return null
            if (!paintsItself(state)) return null
            if (!(selection instanceof TextSelection) && !(selection instanceof AllSelection))
              return null
            return DecorationSet.create(state.doc, [
              Decoration.inline(selection.from, selection.to, { class: 'hk-selection' })
            ])
          }
        }
      })
    ]
  }
})

/**
 * The longest selection (in document positions, about characters) the page paints itself. Beyond it the browser's
 * own paint is good enough and far cheaper: our decoration wraps every selected text node, and a ⌘A over a long
 * page took WebKit the better part of a second per 3000 blocks — seconds on a long one, read as a hang (ISSUE-261);
 * the drag layer measures every selected text node on each change of the selection.
 */
export const PAINT_LIMIT = 20_000

/** Whether the page paints this state's selection itself (see `PAINT_LIMIT`). */
export function paintsItself(state: EditorState): boolean {
  const { from, to } = state.selection
  return to - from <= PAINT_LIMIT
}

/** Boxes of the selected characters, relative to `origin` — text nodes only, so list numbers and gaps never count. */
export function selectedTextRects(range: Range, root: Node, origin: DOMRect): DOMRect[] {
  const rects: DOMRect[] = []
  const container = range.commonAncestorContainer
  const walker = document.createTreeWalker(
    container.nodeType === Node.TEXT_NODE ? (container.parentNode ?? container) : container,
    NodeFilter.SHOW_TEXT
  )
  for (let node = walker.nextNode(); node; node = walker.nextNode()) {
    if (!root.contains(node) || !range.intersectsNode(node)) continue
    // A ruby's reading is a mark over the text, not text that is selected.
    if (node.parentElement?.closest('rt')) continue
    const text = node as Text
    const part = document.createRange()
    part.setStart(text, node === range.startContainer ? range.startOffset : 0)
    part.setEnd(text, node === range.endContainer ? range.endOffset : text.length)
    if (part.collapsed) continue
    for (const rect of part.getClientRects()) {
      if (rect.width > 0 && rect.height > 0)
        rects.push(
          new DOMRect(rect.left - origin.left, rect.top - origin.top, rect.width, rect.height)
        )
    }
  }
  return rects
}

/** The layer that paints a selection while it is being dragged (see `SelectionPaint`). */
class DragLayer {
  private readonly layer: HTMLDivElement
  private frame = 0

  constructor(private readonly view: EditorView) {
    this.layer = document.createElement('div')
    this.layer.className = 'hk-selection-layer'
    this.layer.setAttribute('aria-hidden', 'true')
    view.dom.parentElement?.prepend(this.layer)
    document.addEventListener('selectionchange', this.schedule)
    window.addEventListener('scroll', this.schedule, true)
    window.addEventListener('mouseup', this.release, true)
  }

  private get dragging(): boolean {
    return SelectionPaintKey.getState(this.view.state)?.dragging ?? false
  }

  private readonly release = () => {
    if (this.dragging) this.view.dispatch(this.view.state.tr.setMeta(SelectionPaintKey, false))
    this.layer.replaceChildren()
  }

  private readonly schedule = () => {
    if (!this.dragging || this.frame) return
    this.frame = requestAnimationFrame(() => {
      this.frame = 0
      this.paint()
    })
  }

  /** Draws the selected characters' boxes (the layer sits behind the page's text). */
  paint(): void {
    const selection = this.view.dom.ownerDocument.getSelection()
    const parent = this.layer.parentElement
    if (
      !this.dragging ||
      !paintsItself(this.view.state) ||
      !selection ||
      selection.rangeCount === 0 ||
      selection.isCollapsed ||
      !parent
    ) {
      this.layer.replaceChildren()
      return
    }
    const rects = selectedTextRects(
      selection.getRangeAt(0),
      this.view.dom,
      parent.getBoundingClientRect()
    )
    this.layer.replaceChildren(
      ...rects.map((rect) => {
        const box = document.createElement('div')
        box.style.cssText = `left:${rect.left}px;top:${rect.top}px;width:${rect.width}px;height:${rect.height}px`
        return box
      })
    )
  }

  update(): void {
    if (!this.dragging) this.layer.replaceChildren()
  }

  destroy(): void {
    cancelAnimationFrame(this.frame)
    document.removeEventListener('selectionchange', this.schedule)
    window.removeEventListener('scroll', this.schedule, true)
    window.removeEventListener('mouseup', this.release, true)
    this.layer.remove()
  }
}
