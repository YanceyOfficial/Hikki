import { act, cleanup, fireEvent, screen, waitFor } from '@testing-library/react'
import type { Editor } from '@tiptap/core'
import { CellSelection } from '@tiptap/pm/tables'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { BLOCK_TYPES } from '../src/core/blocks'
import { createEditor } from '../src/core/editor'
import {
  addColumnAtEnd,
  addRowAtEnd,
  clearCells,
  selectColumn,
  selectRow,
  setCellBackground,
  sortColumn
} from '../src/extensions/table-ops'

let host: HTMLElement
let editor: Editor

const cell = (text: string, type = 'tableCell', attrs = {}) => ({
  type,
  attrs,
  content: [{ type: 'paragraph', content: text ? [{ type: 'text', text }] : [] }]
})
const row = (...cells: object[]) => ({ type: 'tableRow', content: cells })
const tableDoc = (...rows: object[]) => ({
  type: 'doc',
  content: [{ type: 'table', content: rows }]
})

/** The table's cell texts, row by row. */
const grid = () => {
  const table = editor.state.doc.firstChild!
  const out: string[][] = []
  table.forEach((r) => {
    const texts: string[] = []
    r.forEach((c) => texts.push(c.textContent))
    out.push(texts)
  })
  return out
}

beforeEach(() => {
  host = document.createElement('div')
  document.body.append(host)
})
afterEach(() => {
  cleanup()
  editor?.destroy()
  host.remove()
})

const sample = () =>
  tableDoc(
    row(cell('Name', 'tableHeader'), cell('Qty', 'tableHeader')),
    row(cell('pear'), cell('10')),
    row(cell('Apple'), cell('9')),
    row(cell(''), cell('100'))
  )

describe('table operations', () => {
  it('"/" inserts a 3×3 table with a header row', () => {
    editor = createEditor(host, null)
    BLOCK_TYPES.find((b) => b.id === 'table')!
      .apply(editor.chain().focus())
      .run()
    expect(grid()).toHaveLength(3)
    expect(grid()[0]).toHaveLength(3)
    expect(editor.state.doc.firstChild!.firstChild!.firstChild!.type.name).toBe('tableHeader')
  })

  it('sorts body rows by a column; headers stay, numbers compare as numbers, empties last', () => {
    editor = createEditor(host, sample())
    expect(sortColumn(editor, 0, 1, 'asc')).toBe(true)
    expect(grid().map((r) => r[1])).toEqual(['Qty', '9', '10', '100'])
    sortColumn(editor, 0, 0, 'asc')
    expect(grid().map((r) => r[0])).toEqual(['Name', 'Apple', 'pear', ''])
    sortColumn(editor, 0, 0, 'desc')
    expect(grid().map((r) => r[0])).toEqual(['Name', 'pear', 'Apple', ''])
  })

  it('refuses to sort a table with merged cells', () => {
    editor = createEditor(
      host,
      tableDoc(row(cell('a', 'tableCell', { colspan: 2 })), row(cell('b'), cell('c')))
    )
    expect(sortColumn(editor, 0, 0, 'asc')).toBe(false)
  })

  it('adds a row and a column at the end', () => {
    editor = createEditor(host, sample())
    addRowAtEnd(editor, 0)
    addColumnAtEnd(editor, 0)
    expect(grid()).toHaveLength(5)
    expect(grid()[0]).toHaveLength(3)
  })

  it('selects a row or column, colors and clears it', () => {
    editor = createEditor(host, sample())
    selectRow(editor, 0, 1)
    expect(editor.state.selection).toBeInstanceOf(CellSelection)
    setCellBackground(editor, 'yellow')
    expect(editor.getHTML()).toContain('data-bg-color="yellow"')
    clearCells(editor)
    expect(grid()[1]).toEqual(['', ''])
    selectColumn(editor, 0, 1)
    clearCells(editor)
    expect(grid().map((r) => r[1])).toEqual(['', '', '', ''])
  })
})

const hoverCell = (index: number) => {
  const target = host.querySelectorAll('td, th')[index] as HTMLElement
  act(() => void fireEvent.mouseMove(target))
}

describe('table controls', () => {
  it('hovering a cell shows its row and column grips and the edge bars', async () => {
    editor = createEditor(host, sample())
    hoverCell(3)
    await waitFor(() => expect(screen.getByRole('button', { name: 'Row options' })).toBeTruthy())
    expect(screen.getByRole('button', { name: 'Column options' })).toBeTruthy()
    act(() => screen.getByRole('button', { name: 'Add a row' }).click())
    expect(grid()).toHaveLength(5)
  })

  it('the row grip selects its row and its menu acts on it', async () => {
    editor = createEditor(host, sample())
    hoverCell(2)
    const grip = await screen.findByRole('button', { name: 'Row options' })
    act(() => grip.click())
    expect(editor.state.selection).toBeInstanceOf(CellSelection)
    act(() => screen.getByRole('menuitem', { name: /Delete row/u }).click())
    expect(grid().map((r) => r[0])).toEqual(['Name', 'Apple', ''])
  })

  it('a multi-cell selection gets a bar that merges the cells', async () => {
    editor = createEditor(host, sample())
    selectRow(editor, 0, 1)
    const merge = await screen.findByRole('button', { name: /Merge cells/u })
    act(() => merge.click())
    expect(grid()[1]).toHaveLength(1)
  })
})
