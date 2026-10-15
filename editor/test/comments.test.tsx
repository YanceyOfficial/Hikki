import { act, cleanup, fireEvent, screen } from '@testing-library/react'
import type { Editor } from '@tiptap/core'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { marginPlacement } from '../src/components/comments'
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
        remove: (id, commentId) => calls.push(`remove ${id}${commentId ? ` ${commentId}` : ''}`),
        edit: (id, commentId, body) => calls.push(`edit ${id} ${commentId} ${body}`),
        device: () => 'Mac',
        pages: () => [
          { id: 'kyoto', title: 'Kyoto in spring', icon: '🌸' },
          { id: 'n4', title: 'N4 文法', icon: null }
        ],
        openPage: (id) => calls.push(`open ${id}`),
        link: (id) => `hikki://page/p#${id}`
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

  it('cards and badges keep clear of the outline rail at the window edge', () => {
    // 404 = a card (300) + its gap (40) + the rail's room (64).
    expect(marginPlacement(1400, 996)).toEqual({ wide: true, offset: 40 })
    expect(marginPlacement(1400, 997).wide).toBe(false)
    // A badge beside the text only with the rail's room past it; else just inside the text.
    expect(marginPlacement(1000, 880)).toEqual({ wide: false, offset: 12 })
    expect(marginPlacement(1000, 881)).toEqual({ wide: false, offset: -44 })
    expect(marginPlacement(1000, 960)).toEqual({ wide: false, offset: -44 })
  })

  it('a page mentioned with "@" is stored as a link and drawn as a chip that opens it', async () => {
    act(() => {
      editor.commands.setTextSelection({ from: 5, to: 10 })
      editor.commands.commentStart()
    })
    const field = (await screen.findByTestId('comment-field')) as HTMLInputElement
    fireEvent.change(field, { target: { value: 'see @kyo', selectionStart: 8 } })
    expect(screen.getByTestId('comment-mention-list').textContent).toContain('Kyoto in spring')
    fireEvent.keyDown(field, { key: 'Enter' })
    expect(field.value).toBe('see @Kyoto in spring ')
    fireEvent.keyDown(field, { key: 'Enter' })
    expect(calls).toEqual(['create quick see [@Kyoto in spring](hikki://page/kyoto)'])

    const [[id]] = [...commentRanges(editor.state.doc)]
    act(() =>
      setThreads(editor, [
        { ...thread(id), comments: [{ ...thread(id).comments[0], body: calls[0].slice(13) }] }
      ])
    )
    const chip = screen.getByTestId('comment-mention')
    expect(chip.textContent).toBe('🌸Kyoto in spring')
    act(() => chip.click())
    expect(calls.at(-1)).toBe('open kyoto')
  })

  it('a comment is edited in place, a reply deleted on its own, the first comment deletes the discussion', async () => {
    act(() => {
      editor.commands.setTextSelection({ from: 5, to: 10 })
      editor.commands.commentStart()
      editor.commands.commentSend('hi')
    })
    const id = [...commentRanges(editor.state.doc).keys()][0]
    const reply = {
      id: 'r',
      body: 'a reply',
      author: null,
      device: 'iPhone',
      createdAt: Date.now()
    }
    act(() => setThreads(editor, [{ ...thread(id), comments: [...thread(id).comments, reply] }]))
    expect(screen.getAllByTestId('comment-row')).toHaveLength(2)

    act(() => editor.commands.commentEdit(id, `${id}-1`, '  样态  '))
    act(() => editor.commands.commentDeleteReply(id, 'r'))
    expect(calls.slice(1)).toEqual([`edit ${id} ${id}-1 样态`, `remove ${id} r`])
    expect(editor.commands.commentEdit(id, 'r', '   ')).toBe(false)

    // Editing from the row: the field holds the words; Escape gives the words back unchanged.
    const more = screen.getAllByTestId('comment-more')[0]
    act(() => more.click())
    const item = await screen.findByTestId('comment-edit')
    act(() => item.click())
    const field = (await screen.findAllByTestId('comment-field'))[0] as HTMLInputElement
    expect(field.value).toBe('first')
    fireEvent.change(field, { target: { value: 'first, edited' } })
    fireEvent.keyDown(field, { key: 'Enter' })
    expect(calls.at(-1)).toBe(`edit ${id} ${id}-1 first, edited`)
  })
})
