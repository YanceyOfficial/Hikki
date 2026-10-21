import { act, cleanup, fireEvent, screen } from '@testing-library/react'
import type { Editor, JSONContent } from '@tiptap/core'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { openBlockMenu } from '../src/components/block-menu'
import { createEditor } from '../src/core/editor'
import { touchBlockInfo, touchMoveBlock } from '../src/core/touch-tools'
import { unitAtPos } from '../src/extensions/block-units'
import { movedContent, moveUnitTo, setMoveBlockHost } from '../src/extensions/move-block'
import { settle } from './helpers'

let host: HTMLElement
let editor: Editor
let sent: { target: string; blocks: JSONContent[]; text: string; words: number }[]
/** What the app answers next (resolved by the test when it holds the move). */
let answer: (blocks: JSONContent[]) => Promise<boolean>

const PAGES = [
  { id: 'here', title: 'Here', icon: null },
  { id: 'trip', title: 'Trip to Kyoto', icon: '🗾' },
  { id: 'notes', title: 'Notes', icon: null }
]

beforeEach(() => {
  sent = []
  answer = async () => true
  host = document.createElement('div')
  document.body.append(host)
  setMoveBlockHost({
    pages: () => PAGES,
    currentPageId: () => 'here',
    move: (target, blocks, text, words) => {
      sent.push({ target, blocks, text, words })
      return answer(blocks)
    }
  })
})
afterEach(() => {
  cleanup()
  editor?.destroy()
  host.remove()
  setMoveBlockHost(null)
  document.querySelectorAll('.hk-block-menu, .hk-floating, .hk-pop').forEach((e) => e.remove())
})

const para = (id: string, text: string, marks?: JSONContent['marks']) => ({
  type: 'paragraph',
  attrs: { id },
  content: [{ type: 'text', text, ...(marks ? { marks } : {}) }]
})
const make = (content: JSONContent[]) => {
  editor = createEditor(host, { type: 'doc', content })
}
const texts = () => editor.state.doc.content.content.map((n) => n.textContent)

describe('moving a block to another page', () => {
  it('sends the block with its text and words, and it leaves only once the app has it', async () => {
    make([para('a', 'one two 三四'), para('b', 'stay')])
    let release!: (ok: boolean) => void
    answer = () => new Promise((resolve) => (release = resolve))
    const moving = moveUnitTo(editor, unitAtPos(editor.state, 1)!, 'trip')
    expect(sent).toEqual([
      {
        target: 'trip',
        blocks: [
          expect.objectContaining({
            type: 'paragraph',
            attrs: expect.objectContaining({ id: 'a' })
          })
        ],
        text: 'one two 三四',
        words: 4
      }
    ])
    // Still here while the app writes it.
    expect(texts()).toEqual(['one two 三四', 'stay'])
    release(true)
    expect(await moving).toBe(true)
    expect(texts()).toEqual(['stay'])
  })

  it('a refused move leaves the block where it was', async () => {
    make([para('a', 'keep me')])
    answer = async () => false
    expect(await moveUnitTo(editor, unitAtPos(editor.state, 1)!, 'trip')).toBe(false)
    expect(texts()).toEqual(['keep me'])
  })

  it('takes the block from where it is after the wait, not where it was', async () => {
    make([para('a', 'first'), para('b', 'go')])
    let release!: (ok: boolean) => void
    answer = () => new Promise((resolve) => (release = resolve))
    const moving = moveUnitTo(editor, unitAtPos(editor.state, 8)!, 'trip')
    // A line typed above meanwhile moves the block down.
    editor.commands.insertContentAt(0, para('z', 'new line'))
    release(true)
    await moving
    expect(texts()).toEqual(['new line', 'first'])
  })

  it('never moves to the page itself, nor from a read-only page', async () => {
    make([para('a', 'x')])
    expect(await moveUnitTo(editor, unitAtPos(editor.state, 1)!, 'here')).toBe(false)
    editor.setEditable(false)
    expect(await moveUnitTo(editor, unitAtPos(editor.state, 1)!, 'trip')).toBe(false)
    expect(sent).toEqual([])
  })

  it('a list item goes in a list of its kind; comment marks stay behind', () => {
    make([
      {
        type: 'orderedList',
        content: [
          {
            type: 'listItem',
            content: [
              para('l1', 'step', [{ type: 'bold' }, { type: 'comment', attrs: { id: 't1' } }])
            ]
          }
        ]
      },
      {
        type: 'taskList',
        content: [{ type: 'taskItem', attrs: { checked: true }, content: [para('t', 'done')] }]
      }
    ])
    const ordered = movedContent(editor, unitAtPos(editor.state, 3)!)
    expect(ordered.type).toBe('orderedList')
    expect(ordered.content?.[0].type).toBe('listItem')
    expect(ordered.content?.[0].content?.[0].content?.[0].marks).toEqual([{ type: 'bold' }])
    const taskPos = editor.state.doc.child(0).nodeSize + 2
    const task = movedContent(editor, unitAtPos(editor.state, taskPos)!)
    expect(task.type).toBe('taskList')
    expect(task.content?.[0].attrs?.checked).toBe(true)
  })

  it('the phone’s ⋯ sheet moves the caret’s block, and offers it only on an editable page', async () => {
    make([para('a', 'stay'), para('b', 'go')])
    editor.commands.setTextSelection(8)
    expect(touchBlockInfo(editor)?.movable).toBe(true)
    expect(await touchMoveBlock(editor, 'notes')).toBe(true)
    expect(sent.map((s) => s.target)).toEqual(['notes'])
    expect(texts()).toEqual(['stay'])
    editor.setEditable(false)
    expect(touchBlockInfo(editor)?.movable).toBe(false)
  })

  it('the block menu’s Move to lists the other pages and moves the block to the one picked', async () => {
    make([para('a', 'go'), para('b', 'stay')])
    act(() => openBlockMenu(editor, unitAtPos(editor.state, 1)!, new DOMRect(10, 10, 20, 20)))
    fireEvent.mouseMove(screen.getByRole('menuitem', { name: /Move to/ }))
    expect(screen.queryByTestId('page-picker-here')).toBeNull()
    fireEvent.change(screen.getByTestId('page-picker-search'), { target: { value: 'kyo' } })
    expect(screen.queryByTestId('page-picker-notes')).toBeNull()
    fireEvent.click(screen.getByTestId('page-picker-trip'))
    await act(settle)
    expect(sent.map((s) => s.target)).toEqual(['trip'])
    expect(texts()).toEqual(['stay'])
    expect(document.querySelector('.hk-block-menu')).toBeNull()
  })
})
