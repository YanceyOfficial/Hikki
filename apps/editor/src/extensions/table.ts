import { Extension, type Editor } from '@tiptap/core'
import { TableCell, TableHeader, TableKit } from '@tiptap/extension-table'
import { Plugin, PluginKey } from '@tiptap/pm/state'
import { CellSelection, TableMap, cellAround } from '@tiptap/pm/tables'
import type { EditorView } from '@tiptap/pm/view'
import { createRoot, type Root } from 'react-dom/client'

import { renderTableOverlay, type TableHover } from '../components/table-overlay'
import { PALETTE } from './colors'

const isPaletteColor = (value: unknown) =>
  typeof value === 'string' && (PALETTE as readonly string[]).includes(value)

/** Cell background as a palette name (`data-bg-color`, wash-* tokens), like text backgrounds. */
const background = {
  default: null,
  parseHTML: (el: HTMLElement) => {
    const value = el.getAttribute('data-bg-color')
    return isPaletteColor(value) ? value : null
  },
  renderHTML: (attrs: Record<string, unknown>) =>
    isPaletteColor(attrs.background) ? { 'data-bg-color': attrs.background } : {}
}

const Cell = TableCell.extend({
  addAttributes() {
    return { ...this.parent?.(), background }
  }
})

const Header = TableHeader.extend({
  addAttributes() {
    return { ...this.parent?.(), background }
  }
})

export const TableControlsKey = new PluginKey('tableControls')

/** Hover grips, edge "+" bars and the cell-selection bar, drawn by React over the editor. */
const TableControls = Extension.create({
  name: 'tableControls',
  addProseMirrorPlugins() {
    const editor = this.editor
    return [
      new Plugin({
        key: TableControlsKey,
        view: (view) => new TableControlsView(view, editor)
      })
    ]
  }
})

export const tableExtensions = [
  TableKit.configure({
    table: { resizable: true, cellMinWidth: 120, HTMLAttributes: { class: 'hk-table' } },
    tableCell: false,
    tableHeader: false
  }),
  Cell,
  Header,
  TableControls
]

/** How long the controls stay after the pointer leaves the table (time to reach a grip). */
const HIDE_DELAY_MS = 250

class TableControlsView {
  private readonly element: HTMLDivElement
  private readonly root: Root
  private hover: TableHover | null = null
  private menuOpen = false
  private hideTimer: ReturnType<typeof setTimeout> | null = null
  /** The last render showed nothing (no hovered table, no cell selection): another empty one is skipped. */
  private drewNothing = false
  private frame = 0

  constructor(
    private readonly view: EditorView,
    private readonly editor: Editor
  ) {
    this.element = document.createElement('div')
    this.element.className = 'hk-table-controls'
    document.body.append(this.element)
    this.root = createRoot(this.element)
    view.dom.addEventListener('mousemove', this.onMove)
    view.dom.addEventListener('mouseleave', this.scheduleHide)
    window.addEventListener('scroll', this.follow, { capture: true, passive: true })
    window.addEventListener('resize', this.follow)
    this.render()
  }

  update() {
    // The document changed (rows added, table deleted…): re-locate from the hovered cell, if still there.
    if (this.hover && !this.hover.cell.isConnected) this.hover = null
    else if (this.hover) this.hover = this.locate(this.hover.cell) ?? null
    this.render()
  }

  destroy() {
    this.view.dom.removeEventListener('mousemove', this.onMove)
    this.view.dom.removeEventListener('mouseleave', this.scheduleHide)
    window.removeEventListener('scroll', this.follow, { capture: true })
    window.removeEventListener('resize', this.follow)
    cancelAnimationFrame(this.frame)
    if (this.hideTimer) clearTimeout(this.hideTimer)
    const root = this.root
    queueMicrotask(() => root.unmount())
    this.element.remove()
  }

  private onMove = (event: MouseEvent) => {
    // While a grip's menu is open its row/column stays the anchor.
    if (!this.editor.isEditable || this.menuOpen) return
    const cell = (event.target as HTMLElement).closest?.('td, th')
    if (!(cell instanceof HTMLElement) || !this.view.dom.contains(cell)) return
    this.cancelHide()
    const next = this.locate(cell)
    if (next && (next.cell !== this.hover?.cell || next.tablePos !== this.hover?.tablePos)) {
      this.hover = next
      this.render()
    }
  }

  /** Table position and the cell's row/column from its DOM element. */
  private locate(cell: HTMLElement): TableHover | null {
    let pos: number
    try {
      pos = this.view.posAtDOM(cell, 0)
    } catch {
      return null
    }
    const $cell = cellAround(this.view.state.doc.resolve(pos))
    if (!$cell) return null
    const table = $cell.node(-1)
    const tableStart = $cell.start(-1)
    const rect = TableMap.get(table).findCell($cell.pos - tableStart)
    const tableEl = cell.closest('table')
    if (!tableEl) return null
    return { tablePos: tableStart - 1, row: rect.top, col: rect.left, cell, table: tableEl }
  }

  private scheduleHide = () => {
    this.cancelHide()
    this.hideTimer = setTimeout(() => {
      if (this.menuOpen) return
      this.hover = null
      this.render()
    }, HIDE_DELAY_MS)
  }

  private cancelHide = () => {
    if (this.hideTimer) clearTimeout(this.hideTimer)
    this.hideTimer = null
  }

  /** Scrolling or resizing moves the controls with their table: once per frame at most. */
  private follow = () => {
    if (this.frame) return
    this.frame = requestAnimationFrame(() => {
      this.frame = 0
      this.render()
    })
  }

  /** Draws the controls — every transaction and scroll calls it, so nothing to show twice draws nothing. */
  private render = () => {
    const selection = this.view.state.selection
    const cellSelection = selection instanceof CellSelection ? selection : null
    const nothing = !this.hover && !cellSelection
    if (nothing && this.drewNothing) return
    this.drewNothing = nothing
    renderTableOverlay(this.root, {
      editor: this.editor,
      hover: this.hover,
      cellSelection,
      onPointerEnter: this.cancelHide,
      onPointerLeave: this.scheduleHide,
      onMenuChange: (open) => {
        this.menuOpen = open
        if (!open) this.scheduleHide()
      }
    })
  }
}
