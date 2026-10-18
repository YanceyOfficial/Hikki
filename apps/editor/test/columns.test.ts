import type { Editor, JSONContent } from '@tiptap/core'
import { NodeSelection } from '@tiptap/pm/state'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { BLOCK_TYPES } from '../src/core/blocks'
import { createEditor } from '../src/core/editor'
import { dropBeside } from '../src/extensions/columns'
import { doc, stripIds } from './helpers'

let host: HTMLElement
let editor: Editor

beforeEach(() => {
  host = document.createElement('div')
  document.body.append(host)
})
afterEach(() => {
  editor?.destroy()
  host.remove()
})

const types = () => stripIds(editor.getJSON()).content.map((n: { type: string }) => n.type)
const rect = new DOMRect(0, 0, 600, 30)

describe('columns', () => {
  it('"/3 columns" replaces the empty line with three columns, caret in the first', () => {
    editor = createEditor(host, null)
    editor.commands.setTextSelection(1)
    BLOCK_TYPES.find((b) => b.id === 'columns3')!
      .apply(editor.chain().focus())
      .run()
    const row = editor.getJSON().content?.[0]
    expect(row?.type).toBe('columns')
    expect(row?.content).toHaveLength(3)
    expect(editor.state.selection.$from.node(-1).type.name).toBe('column')
  })

  it('does not nest a row inside a column', () => {
    editor = createEditor(host, null)
    editor.commands.setTextSelection(1)
    editor.commands.insertColumns(2)
    expect(editor.commands.insertColumns(2)).toBe(false)
  })

  it('Backspace in an empty column removes it; a lone column unwraps', () => {
    editor = createEditor(host, null)
    editor.commands.setTextSelection(1)
    editor.commands.insertColumns(2)
    editor.commands.insertContent('kept')
    // Into the second (empty) column.
    const second = editor.state.doc.firstChild!.firstChild!.nodeSize + 3
    editor.commands.setTextSelection(second)
    editor.commands.keyboardShortcut('Backspace')
    expect(types()[0]).toBe('paragraph')
    expect(editor.getText()).toContain('kept')
  })

  it('dragging a block beside another makes a row (left or right)', () => {
    editor = createEditor(host, doc('target', 'dragged'))
    const draggedPos = editor.state.doc.firstChild!.nodeSize
    editor.view.dispatch(
      editor.state.tr.setSelection(NodeSelection.create(editor.state.doc, draggedPos))
    )
    const node = editor.state.doc.firstChild!
    expect(dropBeside(editor.view, { pos: 0, node, side: 'left', rect })).toBe(true)
    const row = editor.getJSON().content?.[0]
    expect(row?.type).toBe('columns')
    const texts = (row?.content ?? []).map((c: JSONContent) => c.content?.[0].content?.[0].text)
    expect(texts).toEqual(['dragged', 'target'])
  })

  it('dragging beside a row adds a column (widths reset)', () => {
    editor = createEditor(host, doc('', 'extra'))
    editor.commands.setTextSelection(1)
    editor.commands.insertColumns(2)
    const row = editor.state.doc.firstChild!
    const extraPos = row.nodeSize
    editor.view.dispatch(
      editor.state.tr.setSelection(NodeSelection.create(editor.state.doc, extraPos))
    )
    dropBeside(editor.view, { pos: 0, node: editor.state.doc.firstChild!, side: 'right', rect })
    expect(editor.getJSON().content?.[0].content).toHaveLength(3)
  })

  it('stores widths and renders them as flex shares', () => {
    const stored = {
      type: 'doc',
      content: [
        {
          type: 'columns',
          content: [
            { type: 'column', attrs: { width: 70 }, content: [{ type: 'paragraph' }] },
            { type: 'column', attrs: { width: 30 }, content: [{ type: 'paragraph' }] }
          ]
        }
      ]
    }
    editor = createEditor(host, stored)
    const cols = host.querySelectorAll<HTMLElement>('[data-type="column"]')
    expect(cols[0].style.flex).toContain('70')
    expect(editor.getHTML()).toContain('data-width="30"')
  })

  it('never lets a stored width into the style unless it is a number (no CSS injection)', () => {
    const evil = '50 1 0%; position: fixed; inset: 0; background: url(https://example.com/x)'
    const stored = {
      type: 'doc',
      content: [
        {
          type: 'columns',
          content: [
            { type: 'column', attrs: { width: evil }, content: [{ type: 'paragraph' }] },
            { type: 'column', attrs: { width: 1e9 }, content: [{ type: 'paragraph' }] }
          ]
        }
      ]
    }
    editor = createEditor(host, stored)
    const html = editor.getHTML()
    expect(html).not.toContain('position')
    expect(html).not.toContain('url(')
    const cols = host.querySelectorAll<HTMLElement>('[data-type="column"]')
    expect(cols[0].style.position).toBe('')
    expect(cols[0].style.flexGrow).toBe('1')
    expect(cols[1].hasAttribute('data-width')).toBe(false)
  })
})
