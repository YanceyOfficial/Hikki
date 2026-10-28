import { Extension } from '@tiptap/core'
import {
  AllSelection,
  Plugin,
  PluginKey,
  Selection,
  TextSelection,
  type EditorState
} from '@tiptap/pm/state'
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
 * instead (nothing in the text changes) until the button is released. A selection longer than `PAINT_LIMIT` is drawn
 * by that layer too, block by block and only where the viewport is. Fields inside the page keep the browser's
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
          // The class never changes: a class (or custom property) change on the root of a long page made WebKit
          // restyle every element under it — most of what ⌘A and the click after it cost (ISSUE-261).
          attributes: { class: 'hk-own-selection' },
          decorations: (state) => {
            const { selection } = state
            if (selection.empty || SelectionPaintKey.getState(state)?.dragging) return null
            if (!paintsText(state)) return null
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
 * The longest selection (in document positions, about characters) painted on the text. Beyond it the text
 * decoration — a span around every selected text node — took WebKit the better part of a second per 3000 blocks on
 * ⌘A, and as long again on the click that followed (ISSUE-261); such a selection is drawn block by block by the
 * layer, for the blocks in view only, and nothing in the page's DOM changes.
 */
export const PAINT_LIMIT = 20_000

/** Whether the page paints this state's selection on the text (see `PAINT_LIMIT`). */
export function paintsText(state: EditorState): boolean {
  const { from, to } = state.selection
  return to - from <= PAINT_LIMIT
}

/** A selection the layer draws block by block: longer than the limit, and one of text. */
function paintsBlocks(state: EditorState): boolean {
  const { selection } = state
  return (
    !selection.empty &&
    !paintsText(state) &&
    (selection instanceof TextSelection || selection instanceof AllSelection)
  )
}

/**
 * Which of `blocks` (their tops and bottoms, in order down the page) are within a viewport `height` tall: the first by
 * binary search, then on until one starts below it. Only those get a box, however long the page.
 */
export function visibleBlocks(
  blocks: { top: number; bottom: number }[],
  height: number
): [number, number] {
  let low = 0
  let high = blocks.length
  while (low < high) {
    const mid = (low + high) >> 1
    if (blocks[mid].bottom < 0) low = mid + 1
    else high = mid
  }
  let end = low
  while (end < blocks.length && blocks[end].top <= height) end += 1
  return [low, end]
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

/** The layer that paints a selection while it is being dragged, and a long one by block (see `SelectionPaint`). */
class DragLayer {
  private readonly layer: HTMLDivElement
  private frame = 0

  constructor(private readonly view: EditorView) {
    this.layer = document.createElement('div')
    this.layer.className = 'hk-selection-layer'
    this.layer.setAttribute('aria-hidden', 'true')
    view.dom.parentElement?.prepend(this.layer)
    document.addEventListener('selectionchange', this.schedule)
    document.addEventListener('selectionchange', this.dropped)
    window.addEventListener('scroll', this.schedule, true)
    window.addEventListener('resize', this.schedule)
    window.addEventListener('mouseup', this.release, true)
  }

  private get dragging(): boolean {
    return SelectionPaintKey.getState(this.view.state)?.dragging ?? false
  }

  private readonly release = () => {
    if (this.dragging) this.view.dispatch(this.view.state.tr.setMeta(SelectionPaintKey, false))
    else if (!paintsBlocks(this.view.state)) this.layer.replaceChildren()
  }

  /**
   * A read-only page (locked, or the trial over) lets go of its selection once the browser's has left it: on iOS a
   * tap elsewhere clears the selection instead of placing a caret, which ProseMirror never reads, so the painted
   * selection stayed with no way to clear it. An editable page keeps its own (a field in a panel takes the browser's).
   */
  private readonly dropped = () => {
    const { view } = this
    if (view.editable || view.state.selection.empty) return
    const selection = view.dom.ownerDocument.getSelection()
    if (selection && selection.rangeCount > 0 && view.dom.contains(selection.anchorNode)) return
    const { doc, selection: current } = view.state
    view.dispatch(view.state.tr.setSelection(Selection.near(doc.resolve(current.to))))
  }

  private readonly schedule = () => {
    if (!(this.dragging || paintsBlocks(this.view.state)) || this.frame) return
    this.frame = requestAnimationFrame(() => {
      this.frame = 0
      this.paint()
    })
  }

  /** Draws the selection's boxes (the layer sits behind the page's text): the blocks in view of a long selection,
   * else the characters of one being dragged. */
  paint(): void {
    const parent = this.layer.parentElement
    if (!parent) return
    if (paintsBlocks(this.view.state)) {
      this.draw(this.blockRects(parent.getBoundingClientRect()))
      return
    }
    const selection = this.view.dom.ownerDocument.getSelection()
    if (!this.dragging || !selection || selection.rangeCount === 0 || selection.isCollapsed) {
      this.layer.replaceChildren()
      return
    }
    this.draw(
      selectedTextRects(selection.getRangeAt(0), this.view.dom, parent.getBoundingClientRect())
    )
  }

  /** The boxes of the top-level blocks the selection reaches, within the viewport. */
  private blockRects(origin: DOMRect): DOMRect[] {
    const { from, to } = this.view.state.selection
    const children = Array.from(this.view.dom.children) as HTMLElement[]
    const rects = children.map((child) => child.getBoundingClientRect())
    const [start, end] = visibleBlocks(rects, window.innerHeight)
    const out: DOMRect[] = []
    for (let index = start; index < end; index += 1) {
      const pos = this.view.posAtDOM(children[index], 0)
      const node = this.view.state.doc.resolve(pos).node(1)
      const before = this.view.state.doc.resolve(pos).before(1)
      if (before >= to || before + node.nodeSize <= from) continue
      const rect = rects[index]
      out.push(new DOMRect(rect.left - origin.left, rect.top - origin.top, rect.width, rect.height))
    }
    return out
  }

  private draw(rects: DOMRect[]): void {
    this.layer.replaceChildren(
      ...rects.map((rect) => {
        const box = document.createElement('div')
        box.style.cssText = `left:${rect.left}px;top:${rect.top}px;width:${rect.width}px;height:${rect.height}px`
        return box
      })
    )
  }

  update(): void {
    if (paintsBlocks(this.view.state)) this.schedule()
    else if (!this.dragging) this.layer.replaceChildren()
  }

  destroy(): void {
    cancelAnimationFrame(this.frame)
    document.removeEventListener('selectionchange', this.schedule)
    document.removeEventListener('selectionchange', this.dropped)
    window.removeEventListener('scroll', this.schedule, true)
    window.removeEventListener('resize', this.schedule)
    window.removeEventListener('mouseup', this.release, true)
    this.layer.remove()
  }
}
