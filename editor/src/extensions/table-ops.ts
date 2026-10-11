import type { Editor } from '@tiptap/core'
import type { Node as PMNode } from '@tiptap/pm/model'
import { CellSelection, TableMap, deleteCellSelection } from '@tiptap/pm/tables'

import type { PaletteColor } from './colors'

/**
 * Table operations used by the table controls (grips, edge "+" bars, cell menu). Positions are document
 * positions of the table node; rows/columns are TableMap indices.
 */

function tableAt(editor: Editor, tablePos: number): PMNode | null {
  const node = editor.state.doc.nodeAt(tablePos)
  return node?.type.name === 'table' ? node : null
}

/** Document position of the cell covering (row, col). */
function cellPos(editor: Editor, tablePos: number, row: number, col: number): number | null {
  const table = tableAt(editor, tablePos)
  if (!table) return null
  const map = TableMap.get(table)
  if (row < 0 || col < 0 || row >= map.height || col >= map.width) return null
  return tablePos + 1 + map.map[row * map.width + col]
}

export function selectRow(editor: Editor, tablePos: number, row: number): boolean {
  const pos = cellPos(editor, tablePos, row, 0)
  if (pos === null) return false
  const $cell = editor.state.doc.resolve(pos)
  editor.view.dispatch(editor.state.tr.setSelection(CellSelection.rowSelection($cell)))
  return true
}

export function selectColumn(editor: Editor, tablePos: number, col: number): boolean {
  const pos = cellPos(editor, tablePos, 0, col)
  if (pos === null) return false
  const $cell = editor.state.doc.resolve(pos)
  editor.view.dispatch(editor.state.tr.setSelection(CellSelection.colSelection($cell)))
  return true
}

/** Puts the caret in the cell at (row, col), so the row/column commands act there. */
function caretIn(editor: Editor, tablePos: number, row: number, col: number): boolean {
  const pos = cellPos(editor, tablePos, row, col)
  if (pos === null) return false
  editor.commands.setTextSelection(pos + 2)
  return true
}

export function addRowAtEnd(editor: Editor, tablePos: number): boolean {
  const table = tableAt(editor, tablePos)
  if (!table) return false
  const map = TableMap.get(table)
  return caretIn(editor, tablePos, map.height - 1, 0) && editor.chain().focus().addRowAfter().run()
}

export function addColumnAtEnd(editor: Editor, tablePos: number): boolean {
  const table = tableAt(editor, tablePos)
  if (!table) return false
  const map = TableMap.get(table)
  return (
    caretIn(editor, tablePos, 0, map.width - 1) && editor.chain().focus().addColumnAfter().run()
  )
}

/** Background of the selected cells (palette name; null clears it). */
export function setCellBackground(editor: Editor, color: PaletteColor | null): boolean {
  return editor.chain().focus().setCellAttribute('background', color).run()
}

/** Empties the selected cells, keeping the table's shape. */
export function clearCells(editor: Editor): boolean {
  return deleteCellSelection(editor.state, editor.view.dispatch)
}

/** True when the table has merged cells (row/column operations like sorting don't apply). */
export function hasMergedCells(table: PMNode): boolean {
  let merged = false
  table.descendants((node) => {
    if (node.attrs.colspan > 1 || node.attrs.rowspan > 1) merged = true
    return !merged
  })
  return merged
}

/** A row made only of header cells. */
function isHeaderRow(row: PMNode): boolean {
  let header = row.childCount > 0
  row.forEach((cell) => {
    if (cell.type.name !== 'tableHeader') header = false
  })
  return header
}

/**
 * Sorts the body rows by the text in column `col` (header rows stay on top). Numbers compare as numbers
 * and text by the user's locale. Not available with merged cells.
 */
export function sortColumn(
  editor: Editor,
  tablePos: number,
  col: number,
  direction: 'asc' | 'desc'
): boolean {
  const table = tableAt(editor, tablePos)
  if (!table || hasMergedCells(table)) return false
  const rows: PMNode[] = []
  table.forEach((row) => rows.push(row))
  const headerCount = rows.findIndex((row) => !isHeaderRow(row))
  const head = headerCount === -1 ? rows : rows.slice(0, headerCount)
  const body = headerCount === -1 ? [] : rows.slice(headerCount)
  const collator = new Intl.Collator(undefined, { numeric: true, sensitivity: 'base' })
  const key = (row: PMNode) => (col < row.childCount ? row.child(col).textContent.trim() : '')
  const sorted = body.toSorted((a, b) => {
    const [ka, kb] = [key(a), key(b)]
    // Empty cells sort last either way.
    if (!ka || !kb) return ka ? -1 : kb ? 1 : 0
    return direction === 'asc' ? collator.compare(ka, kb) : collator.compare(kb, ka)
  })
  if (sorted.every((row, i) => row === body[i])) return true
  const next = table.type.create(table.attrs, [...head, ...sorted], table.marks)
  editor.view.dispatch(editor.state.tr.replaceWith(tablePos, tablePos + table.nodeSize, next))
  return true
}
