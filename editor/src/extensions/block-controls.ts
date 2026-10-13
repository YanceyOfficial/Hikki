import gripSvg from '@phosphor-icons/core/assets/bold/dots-six-vertical-bold.svg?raw'
import plusSvg from '@phosphor-icons/core/assets/regular/plus.svg?raw'
import { Extension, type Editor } from '@tiptap/core'
import { Plugin, PluginKey, TextSelection } from '@tiptap/pm/state'
import type { EditorView } from '@tiptap/pm/view'

import { openBlockMenu } from '../components/block-menu'
import { t } from '../core/i18n'
import { tiptapShortcut } from '../core/shortcuts'
import { BlockHighlight, BlockHighlightKey, setBlockHighlight } from './block-highlight'
import { duplicateUnit, firstTextPos, moveUnit, unitAtPos, type BlockUnit } from './block-units'
import { dropBeside, MAX_COLUMNS } from './columns'

export const BlockControlsKey = new PluginKey('blockControls')

const atCaret = (editor: Editor) => unitAtPos(editor.state, editor.state.selection.from)

/** Moves the block at the caret one place up or down among its siblings. */
const moveAtCaret = (editor: Editor, dir: -1 | 1) => {
  const unit = atCaret(editor)
  if (!unit) return false
  const $pos = editor.state.doc.resolve(unit.pos)
  const index = $pos.index()
  const parent = $pos.parent
  if (dir === -1 && index === 0) return true
  if (dir === 1 && index >= parent.childCount - 1) return true
  const target =
    dir === -1
      ? unit.pos - parent.child(index - 1).nodeSize
      : unit.pos + unit.node.nodeSize + parent.child(index + 1).nodeSize
  const tr = moveUnit(editor.state, unit, target)
  if (tr) editor.view.dispatch(tr)
  return true
}

/** Pixels the pointer must travel before a press on the grip becomes a drag (otherwise it's a click). */
const DRAG_THRESHOLD = 4
/** How close to a block's side edge a drop makes columns. */
const SIDE_EDGE = 48

const icon = (svg: string) =>
  svg.replace('<svg ', '<svg width="18" height="18" aria-hidden="true" ')

/**
 * Notion-style block controls: "+" and a ⋮⋮ grip beside the block under the pointer, level with its first
 * line. Drag the grip (pointer events — HTML5 drag-and-drop is unreliable in WebKit) to move the block: a
 * ghost follows the pointer and a line marks the gap; near another block's side edge the drop makes
 * columns. Click the grip for the block menu. Fine pointers only (touch would fight text selection).
 */
export const BlockControls = Extension.create<{ enabled: boolean | null }>({
  name: 'blockControls',

  addOptions() {
    // null: decided when the editor is created (a fine pointer: mouse or trackpad).
    return { enabled: null }
  },

  addKeyboardShortcuts() {
    return {
      // Duplicate the block (Notion ⌘D), move it up/down (⌘⇧↑ / ⌘⇧↓).
      [tiptapShortcut('duplicateBlock')]: ({ editor }) => {
        const unit = atCaret(editor)
        if (!unit) return false
        editor.view.dispatch(duplicateUnit(editor.state, unit))
        return true
      },
      [tiptapShortcut('moveBlockUp')]: ({ editor }) => moveAtCaret(editor, -1),
      [tiptapShortcut('moveBlockDown')]: ({ editor }) => moveAtCaret(editor, 1)
    }
  },

  addProseMirrorPlugins() {
    // The highlights serve every pointer (the block menu may open from touch later); the handle itself
    // needs a mouse or trackpad.
    const enabled = this.options.enabled ?? window.matchMedia?.('(pointer: fine)').matches ?? false
    if (!enabled) return [BlockHighlight]
    const editor = this.editor
    return [
      BlockHighlight,
      new Plugin({ key: BlockControlsKey, view: (view) => new BlockControlsView(view, editor) })
    ]
  }
})

type Drop =
  | { kind: 'gap'; pos: number; rect: DOMRect; y: number }
  | { kind: 'side'; target: BlockUnit; side: 'left' | 'right'; rect: DOMRect }

class BlockControlsView {
  private readonly handle: HTMLDivElement
  private readonly line: HTMLDivElement
  private unit: BlockUnit | null = null
  private press: { unit: BlockUnit; x: number; y: number; pointer: number } | null = null
  private ghost: HTMLElement | null = null
  private drop: Drop | null = null
  private ghostOffset = { x: 0, y: 0 }
  private scrollFrame = 0
  private lastPointer = { x: 0, y: 0 }

  constructor(
    private readonly view: EditorView,
    private readonly editor: Editor
  ) {
    this.handle = document.createElement('div')
    this.handle.className = 'hk-block-handle'
    this.handle.dataset.hidden = 'true'
    const plus = document.createElement('button')
    plus.type = 'button'
    plus.className = 'hk-block-plus'
    plus.setAttribute('aria-label', t('blockMenu.add'))
    plus.innerHTML = icon(plusSvg)
    plus.addEventListener('mousedown', (e) => e.preventDefault())
    plus.addEventListener('click', () => this.addBelow())
    const grip = document.createElement('button')
    grip.type = 'button'
    grip.className = 'hk-block-grip'
    grip.setAttribute('aria-label', t('editor.dragBlock'))
    grip.innerHTML = icon(gripSvg)
    grip.addEventListener('pointerdown', this.onGripDown)
    this.handle.append(plus, grip)
    this.line = document.createElement('div')
    this.line.className = 'hk-drop-line'
    this.line.dataset.hidden = 'true'
    document.body.append(this.handle, this.line)
    document.addEventListener('mousemove', this.onMove)
    view.dom.addEventListener('keydown', this.hide)
    window.addEventListener('scroll', this.reposition, true)
  }

  update() {
    // Locked (or unreadable) now: whatever handle was showing goes at once, not on the next pointer move.
    if (!this.editor.isEditable) return this.hide()
    // Text being selected (the selection menu is up, or about to be): one surface at a time, as in Notion.
    if (this.selecting()) return this.hide()
    // The hovered block may have moved or gone; re-find it from where it was.
    if (this.unit && !this.press) {
      const unit = unitAtPos(
        this.view.state,
        Math.min(this.unit.pos, this.view.state.doc.content.size)
      )
      this.unit = unit
      this.reposition()
    }
  }

  destroy() {
    document.removeEventListener('mousemove', this.onMove)
    this.view.dom.removeEventListener('keydown', this.hide)
    window.removeEventListener('scroll', this.reposition, true)
    this.endDrag()
    this.handle.remove()
    this.line.remove()
  }

  // MARK: Hover

  private contentRect(): DOMRect {
    return this.view.dom.getBoundingClientRect()
  }

  /** The unit at a viewport point (anywhere on its row, including the left gutter). */
  private unitAtPoint(x: number, y: number): BlockUnit | null {
    const rect = this.contentRect()
    const left = Math.min(Math.max(x, rect.left + 2), rect.right - 2)
    const at = this.view.posAtCoords({ left, top: y })
    if (!at) return null
    return unitAtPos(this.view.state, at.inside >= 0 ? at.inside : at.pos)
  }

  /** A non-empty text selection: the selection menu's moment, not the handle's. */
  private selecting(): boolean {
    const { selection } = this.view.state
    return selection instanceof TextSelection && !selection.empty
  }

  private onMove = (event: MouseEvent) => {
    if (this.press) return
    // A locked (or unreadable) page has no handle at all — the one already showing goes too.
    if (!this.editor.isEditable || this.selecting()) return this.hide()
    const rect = this.contentRect()
    // Over the page or its left gutter (where the handle sits), within the page's height.
    const inBand = event.clientX >= rect.left - 96 && event.clientX <= rect.right + 24
    if (!inBand || event.clientY < rect.top - 4 || event.clientY > rect.bottom + 4) {
      if (!this.handle.contains(event.target as Node)) this.hide()
      return
    }
    if (this.handle.contains(event.target as Node)) return
    const unit = this.unitAtPoint(event.clientX, event.clientY)
    if (!unit) return this.hide()
    this.unit = unit
    this.reposition()
  }

  private hide = () => {
    if (this.press) return
    this.handle.dataset.hidden = 'true'
  }

  /** Level with the block's first line (its vertical centre), left of the block (and of a list marker). */
  private reposition = () => {
    const unit = this.unit
    if (!unit || this.press) return
    const dom = this.view.nodeDOM(unit.pos)
    if (!(dom instanceof HTMLElement)) return this.hide()
    const rect = dom.getBoundingClientRect()
    let centre = rect.top + Math.min(rect.height / 2, 14)
    const text = firstTextPos(unit)
    if (text !== null) {
      try {
        const coords = this.view.coordsAtPos(Math.min(text, this.view.state.doc.content.size))
        centre = (coords.top + coords.bottom) / 2
      } catch {
        // Keep the box estimate.
      }
    }
    const listItem = unit.node.type.name === 'listItem' || unit.node.type.name === 'taskItem'
    // A table draws its own row grips at its left edge (components/table-overlay.tsx); the handle keeps clear.
    const table = unit.node.type.name === 'table'
    const left = rect.left - (listItem ? 22 : 0) - (table ? 22 : 0) - this.handle.offsetWidth - 4
    Object.assign(this.handle.style, {
      left: `${left}px`,
      top: `${centre - this.handle.offsetHeight / 2}px`
    })
    this.handle.dataset.hidden = 'false'
  }

  // MARK: Add

  /** "+": a new line below the block with the "/" menu open (Notion). */
  private addBelow() {
    const unit = this.unit
    if (!unit) return
    const end = unit.pos + unit.node.nodeSize
    const { state } = this.view
    const paragraph = state.schema.nodes.paragraph.create()
    const tr = state.tr.insert(end, paragraph)
    tr.setSelection(TextSelection.create(tr.doc, end + 1))
    this.view.dispatch(tr)
    this.view.focus()
    this.editor.commands.insertContent('/')
  }

  // MARK: Drag

  private onGripDown = (event: PointerEvent) => {
    if (event.button !== 0 || !this.unit) return
    event.preventDefault()
    const grip = event.currentTarget as HTMLElement
    grip.setPointerCapture(event.pointerId)
    this.press = { unit: this.unit, x: event.clientX, y: event.clientY, pointer: event.pointerId }
    grip.addEventListener('pointermove', this.onDragMove)
    grip.addEventListener('pointerup', this.onDragUp)
    grip.addEventListener('pointercancel', this.onDragCancel)
    document.addEventListener('keydown', this.onDragKey, true)
  }

  private onDragMove = (event: PointerEvent) => {
    const press = this.press
    if (!press) return
    this.lastPointer = { x: event.clientX, y: event.clientY }
    if (!this.ghost) {
      if (Math.hypot(event.clientX - press.x, event.clientY - press.y) < DRAG_THRESHOLD) return
      this.startGhost(press.unit, event)
    }
    this.moveGhost(event.clientX, event.clientY)
    this.drop = this.dropAt(press.unit, event.clientX, event.clientY)
    this.showDrop()
    this.autoScroll()
  }

  private startGhost(unit: BlockUnit, event: PointerEvent) {
    const dom = this.view.nodeDOM(unit.pos)
    if (!(dom instanceof HTMLElement)) return
    const rect = dom.getBoundingClientRect()
    const ghost = document.createElement('div')
    ghost.className = 'hk-drag-ghost tiptap'
    ghost.style.width = `${rect.width}px`
    ghost.append(dom.cloneNode(true))
    document.body.append(ghost)
    this.ghost = ghost
    this.ghostOffset = { x: event.clientX - rect.left, y: event.clientY - rect.top }
    document.body.classList.add('hk-block-dragging')
    setBlockHighlight(this.view, { source: { from: unit.pos, to: unit.pos + unit.node.nodeSize } })
    this.handle.dataset.hidden = 'true'
  }

  private moveGhost(x: number, y: number) {
    if (this.ghost)
      this.ghost.style.transform = `translate(${x - this.ghostOffset.x}px, ${y - this.ghostOffset.y}px)`
  }

  /** Where a drop at (x, y) would go: a gap between blocks, or beside a top-level block (columns). */
  private dropAt(dragged: BlockUnit, x: number, y: number): Drop | null {
    const target = this.unitAtPoint(x, y)
    if (!target) return null
    const end = dragged.pos + dragged.node.nodeSize
    if (target.pos >= dragged.pos && target.pos < end) return null
    const dom = this.view.nodeDOM(target.pos)
    if (!(dom instanceof HTMLElement)) return null
    const rect = dom.getBoundingClientRect()
    const topLevel = this.view.state.doc.resolve(target.pos).depth === 0
    const rowFull = target.node.type.name === 'columns' && target.node.childCount >= MAX_COLUMNS
    if (topLevel && !rowFull && dragged.node.type.name !== 'columns') {
      if (x < rect.left + SIDE_EDGE && x >= rect.left - 8)
        return { kind: 'side', target, side: 'left', rect }
      if (x > rect.right - SIDE_EDGE) return { kind: 'side', target, side: 'right', rect }
    }
    const before = y < rect.top + rect.height / 2
    const pos = before ? target.pos : target.pos + target.node.nodeSize
    if (pos >= dragged.pos && pos <= end) return null
    return { kind: 'gap', pos, rect, y: before ? rect.top : rect.bottom }
  }

  private showDrop() {
    const drop = this.drop
    if (!drop) {
      this.line.dataset.hidden = 'true'
      return
    }
    this.line.dataset.hidden = 'false'
    this.line.dataset.side = String(drop.kind === 'side')
    if (drop.kind === 'gap') {
      Object.assign(this.line.style, {
        left: `${drop.rect.left}px`,
        top: `${drop.y - 1}px`,
        width: `${drop.rect.width}px`,
        height: '3px'
      })
    } else {
      const x = drop.side === 'left' ? drop.rect.left - 6 : drop.rect.right + 3
      Object.assign(this.line.style, {
        left: `${x}px`,
        top: `${drop.rect.top}px`,
        width: '3px',
        height: `${drop.rect.height}px`
      })
    }
  }

  /** Near the top or bottom of the window, keep scrolling while the pointer stays there. */
  private autoScroll() {
    cancelAnimationFrame(this.scrollFrame)
    const edge = 56
    const { y } = this.lastPointer
    const speed =
      y < edge ? -(edge - y) / 3 : y > innerHeight - edge ? (y - (innerHeight - edge)) / 3 : 0
    if (!speed || !this.ghost) return
    this.scrollFrame = requestAnimationFrame(() => {
      const scroller = document.scrollingElement ?? document.documentElement
      scroller.scrollTop += speed
      if (this.press) {
        this.drop = this.dropAt(this.press.unit, this.lastPointer.x, this.lastPointer.y)
        this.showDrop()
      }
      this.autoScroll()
    })
  }

  private onDragUp = (event: PointerEvent) => {
    const press = this.press
    const dragged = this.ghost !== null
    const drop = this.drop
    this.endDrag(event.currentTarget as HTMLElement)
    if (!press) return
    if (!dragged) {
      // A click on the grip: the block menu.
      openBlockMenu(this.editor, press.unit, this.handle.getBoundingClientRect())
      return
    }
    if (!drop) return
    if (drop.kind === 'gap') {
      const tr = moveUnit(this.view.state, press.unit, drop.pos)
      if (tr) this.view.dispatch(tr)
    } else {
      const { pos, node } = press.unit
      dropBeside(
        this.view,
        { pos: drop.target.pos, node: drop.target.node, side: drop.side, rect: drop.rect },
        {
          from: pos,
          to: pos + node.nodeSize
        }
      )
    }
    this.view.focus()
  }

  private onDragCancel = (event: PointerEvent) => this.endDrag(event.currentTarget as HTMLElement)

  private onDragKey = (event: KeyboardEvent) => {
    if (event.key !== 'Escape') return
    event.preventDefault()
    event.stopPropagation()
    this.endDrag()
  }

  private endDrag(grip?: HTMLElement) {
    if (grip) {
      grip.removeEventListener('pointermove', this.onDragMove)
      grip.removeEventListener('pointerup', this.onDragUp)
      grip.removeEventListener('pointercancel', this.onDragCancel)
    }
    document.removeEventListener('keydown', this.onDragKey, true)
    cancelAnimationFrame(this.scrollFrame)
    this.ghost?.remove()
    this.ghost = null
    this.drop = null
    this.line.dataset.hidden = 'true'
    document.body.classList.remove('hk-block-dragging')
    if (BlockHighlightKey.getState(this.view.state)?.source)
      setBlockHighlight(this.view, { source: null })
    this.press = null
  }
}
