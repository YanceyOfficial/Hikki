import { act, cleanup, fireEvent, screen } from '@testing-library/react'
import type { Editor } from '@tiptap/core'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { createEditor } from '../src/core/editor'
import {
  commentRanges,
  commentsState,
  setThreads,
  type ThreadItem
} from '../src/extensions/comments'

let host: HTMLElement
let editor: Editor
let calls: string[]

const thread = (id: string, resolved = false): ThreadItem => ({
  id,
  quote: 'quick',
  resolved,
  comments: [
    { id: `${id}-1`, body: 'first', author: 'Yancey', device: 'Mac', createdAt: Date.now() }
  ]
})

beforeEach(() => {
  calls = []
  host = document.createElement('div')
  const column = document.createElement('div')
  column.className = 'hk-column'
  column.append(host)
  document.body.append(column)
  editor = createEditor(
    host,
    {
      type: 'doc',
      content: [{ type: 'paragraph', content: [{ type: 'text', text: 'the quick fox jumps' }] }]
    },
    {
      comments: {
        create: (_id, quote, body) => calls.push(`create ${quote} ${body}`),
        reply: (id, body) => calls.push(`reply ${id} ${body}`),
        resolve: (id, resolved) => calls.push(`resolve ${id} ${resolved}`),
        remove: (id) => calls.push(`remove ${id}`),
        device: () => 'Mac'
      }
    }
  )
})
afterEach(() => {
  cleanup()
  editor.destroy()
  host.parentElement?.remove()
})

describe('comments', () => {
  it('a comment on a selection: a draft first, the passage marked only once it is sent', async () => {
    act(() => {
      editor.commands.setTextSelection({ from: 5, to: 10 })
      editor.commands.commentStart()
    })
    expect(commentRanges(editor.state.doc).size).toBe(0)
    expect(host.querySelector('.hk-comment-active')?.textContent).toBe('quick')
    const field = await screen.findByTestId('comment-field')
    fireEvent.change(field, { target: { value: '样态，不是传闻' } })
    fireEvent.keyDown(field, { key: 'Enter' })
    expect(calls).toEqual(['create quick 样态，不是传闻'])
    const [[id, ranges]] = [...commentRanges(editor.state.doc)]
    expect(editor.state.doc.textBetween(ranges[0].from, ranges[0].to)).toBe('quick')
    expect(commentsState(editor.state)?.active).toBe(id)
    expect(commentsState(editor.state)?.draft).toBeNull()
  })

  it('only open threads the store knows are marked; resolving hides the mark', () => {
    act(() => {
      editor.commands.setTextSelection({ from: 5, to: 10 })
      editor.commands.commentStart()
      editor.commands.commentSend('hi')
    })
    const id = [...commentRanges(editor.state.doc).keys()][0]
    act(() => editor.commands.commentOpen(null))
    expect(host.querySelector('.hk-comment')).toBeNull()
    act(() => setThreads(editor, [thread(id)]))
    expect(host.querySelector('.hk-comment')?.textContent).toBe('quick')
    expect(screen.getAllByTestId('comment-thread')).toHaveLength(1)
    act(() => setThreads(editor, [thread(id, true)]))
    expect(host.querySelector('.hk-comment')).toBeNull()
    expect(screen.queryByTestId('comment-thread')).toBeNull()
  })

  it('replies, resolves and deletes through the host; deleting takes the mark away', async () => {
    act(() => {
      editor.commands.setTextSelection({ from: 5, to: 10 })
      editor.commands.commentStart()
      editor.commands.commentSend('hi')
    })
    const id = [...commentRanges(editor.state.doc).keys()][0]
    act(() => setThreads(editor, [thread(id)]))
    const field = await screen.findByTestId('comment-field')
    fireEvent.change(field, { target: { value: 'a reply' } })
    fireEvent.keyDown(field, { key: 'Enter' })
    act(() => screen.getByTestId('comment-resolve').click())
    act(() => editor.commands.commentDelete(id))
    expect(calls.slice(1)).toEqual([`reply ${id} a reply`, `resolve ${id} true`, `remove ${id}`])
    expect(commentRanges(editor.state.doc).size).toBe(0)
  })

  it('the mark survives a save and a reload (it is part of the page)', () => {
    act(() => {
      editor.commands.setTextSelection({ from: 5, to: 10 })
      editor.commands.commentStart()
      editor.commands.commentSend('hi')
    })
    const json = editor.getJSON()
    expect(JSON.stringify(json)).toContain('"type":"comment"')
    editor.commands.setContent(json)
    expect(commentRanges(editor.state.doc).size).toBe(1)
  })
})
