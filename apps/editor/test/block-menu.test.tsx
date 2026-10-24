import { act, cleanup, fireEvent, screen } from '@testing-library/react'
import type { Editor, JSONContent } from '@tiptap/core'
import { NodeSelection } from '@tiptap/pm/state'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { openBlockMenu } from '../src/components/block-menu'
import { blockCounts, blockKindLabel } from '../src/core/block-kinds'
import { createEditor, type EditorOptions } from '../src/core/editor'
import type { AIRequestMessage } from '../src/extensions/ai-review'
import { handleAIEvent } from '../src/extensions/ai-review'
import { unitAtPos } from '../src/extensions/block-units'
import {
  blockThreadRanges,
  commentsState,
  setThreads,
  threadRange,
  type ThreadItem
} from '../src/extensions/comments'
import { doc } from './helpers'

let host: HTMLElement
let editor: Editor
let created: { quote: string; body: string; blockId?: string }[]
let opened: string[]
let requests: AIRequestMessage[]

beforeEach(() => {
  created = []
  opened = []
  requests = []
  host = document.createElement('div')
  document.body.append(host)
})
afterEach(() => {
  cleanup()
  editor?.destroy()
  host.remove()
  document.querySelectorAll('.hk-block-menu, .hk-floating, .hk-pop').forEach((e) => e.remove())
  vi.unstubAllGlobals()
})

const noop = () => {}
const options = (): EditorOptions => ({
  comments: {
    create: (_id, quote, body, blockId) => created.push({ quote, body, blockId }),
    reply: noop,
    resolve: noop,
    remove: noop,
    edit: noop,
    device: () => 'Mac',
    pages: () => [],
    openPage: noop,
    link: () => null
  },
  pageLinks: {
    pages: () => [],
    currentPageId: () => 'p',
    untitled: () => 'Untitled',
    open: noop,
    openExternal: (url) => opened.push(url)
  },
  ai: { request: (m) => requests.push(m), cancel: noop, title: () => 'Trip' }
})

const gist = {
  type: 'embed',
  attrs: {
    id: 'e1',
    provider: 'gist',
    src: 'https://gist.github.com/a/1.js',
    original: 'https://gist.github.com/a/1',
    height: 300
  }
}
const image = { type: 'image', attrs: { id: 'i1', src: 'hikki-editor://assets/kyoto.png' } }
const para = (id: string, text: string) => ({
  type: 'paragraph',
  attrs: { id },
  content: [{ type: 'text', text }]
})

function open(content: JSONContent[], at: number) {
  editor = createEditor(host, { type: 'doc', content }, options())
  const unit = unitAtPos(editor.state, at)!
  act(() => openBlockMenu(editor, unit, new DOMRect(10, 10, 20, 20)))
}

/** Position of the n-th top-level block. */
function blockPos(index: number): number {
  let pos = 0
  for (let i = 0; i < index; i++) pos += editor.state.doc.child(i).nodeSize
  return pos
}

const row = (name: RegExp) => screen.getByRole('menuitem', { name })

describe('block menu, Notion’s', () => {
  it('names the block’s kind, ends with its word and character count', () => {
    open([para('a', 'one two 三四')], 1)
    expect(screen.getByTestId('block-menu-kind').textContent).toBe('Text')
    // CJK characters count a word each, as the page’s count does.
    expect(screen.getByTestId('block-menu-counts').textContent).toBe('4 words, 10 characters')
    for (const name of [/Duplicate/u, /Delete/u, /Comment/u, /Ask AI/u])
      expect(row(name)).toBeTruthy()
    expect(screen.getAllByRole('separator').length).toBeGreaterThan(1)
  })

  it('kinds: a gist embed is "GitHub Gist", a pasted YouTube link "YouTube", an image "Image"', () => {
    editor = createEditor(host, { type: 'doc', content: [gist, image, para('a', 'x')] }, options())
    expect(blockKindLabel(editor.state.doc.child(0))).toBe('GitHub Gist')
    expect(blockKindLabel(editor.state.doc.child(1))).toBe('Image')
    const youtube = editor.schema.nodes.embed.create({ provider: 'youtube' })
    expect(blockKindLabel(youtube)).toBe('YouTube')
    expect(blockCounts(editor.state.doc.child(1))).toBeNull()
  })

  it('an embed: Open in browser and Copy link to original use the link it was made from', () => {
    const writes: string[] = []
    Object.defineProperty(navigator, 'clipboard', {
      configurable: true,
      value: {
        writeText: (text: string) => {
          writes.push(text)
          return Promise.resolve()
        }
      }
    })
    open([gist, para('a', 'x')], 0)
    expect(screen.getByTestId('block-menu-kind').textContent).toBe('GitHub Gist')
    expect(screen.queryByTestId('block-menu-counts')).toBeNull()
    act(() => row(/Open in browser/u).click())
    expect(opened).toEqual(['https://gist.github.com/a/1'])
    act(() => openBlockMenu(editor, unitAtPos(editor.state, 0)!, new DOMRect(0, 0, 1, 1)))
    act(() => row(/Copy link to original/u).click())
    expect(writes).toEqual(['https://gist.github.com/a/1'])
  })

  it('an embed: Replace swaps its link in the same block (id, height kept)', () => {
    open([gist, para('a', 'x')], 0)
    act(() => row(/Replace/u).click())
    const field = screen.getByLabelText('Link to embed') as HTMLInputElement
    expect(field.value).toBe('https://gist.github.com/a/1')
    act(() => void fireEvent.change(field, { target: { value: 'https://vimeo.com/76979871' } }))
    act(() => void fireEvent.keyDown(field, { key: 'Enter' }))
    const node = editor.state.doc.child(0)
    expect(node.attrs).toMatchObject({
      id: 'e1',
      provider: 'vimeo',
      original: 'https://vimeo.com/76979871',
      height: 300
    })
  })

  it('an embed: Caption writes a line under it, and an empty one removes it', () => {
    open([gist, para('a', 'x')], 0)
    act(() => row(/Caption/u).click())
    const field = screen.getByPlaceholderText('Write a caption…') as HTMLInputElement
    act(() => void fireEvent.change(field, { target: { value: '  Build script  ' } }))
    act(() => void fireEvent.keyDown(field, { key: 'Enter' }))
    expect(editor.state.doc.child(0).attrs.caption).toBe('Build script')
    expect(host.querySelector('.hk-embed-caption')?.textContent).toBe('Build script')
    expect(editor.getHTML()).toContain('data-caption="Build script"')
    // A press on the caption reopens the panel; clearing it removes the line.
    act(() => (host.querySelector('.hk-embed-caption') as HTMLElement).click())
    const again = screen.getByPlaceholderText('Write a caption…') as HTMLInputElement
    expect(again.value).toBe('Build script')
    act(() => void fireEvent.change(again, { target: { value: '' } }))
    act(() => void fireEvent.keyDown(again, { key: 'Enter' }))
    expect(editor.state.doc.child(0).attrs.caption).toBeNull()
    expect(host.querySelector('.hk-embed-caption')).toBeNull()
  })

  it('Comment on a text block starts a passage comment on its text', () => {
    open([para('a', 'hello world')], 1)
    act(() => row(/Comment/u).click())
    const draft = commentsState(editor.state)?.draft
    expect(draft).toMatchObject({ from: 1, to: 12 })
    expect(draft?.blockId).toBeUndefined()
  })
})

const thread = (id: string, blockId: string): ThreadItem => ({
  id,
  quote: 'Image',
  resolved: false,
  blockId,
  comments: [{ id: `${id}-1`, body: 'nice', author: null, device: null, createdAt: Date.now() }]
})

describe('comments on whole blocks', () => {
  it('Comment on an embed starts a thread on the block; sending it stores the block id and marks nothing', () => {
    open([gist, para('a', 'x')], 0)
    act(() => row(/Comment/u).click())
    expect(commentsState(editor.state)?.draft).toMatchObject({ blockId: 'e1', from: 0 })
    expect(host.querySelector('.hk-comment-block-active')).not.toBeNull()
    act(() => void editor.commands.commentSend('Which file?'))
    expect(created).toEqual([
      { quote: 'GitHub Gist · https://gist.github.com/a/1', body: 'Which file?', blockId: 'e1' }
    ])
    expect(editor.getHTML()).not.toContain('data-comment')
  })

  it('⇧⌘M on a selected image starts a block thread too', () => {
    editor = createEditor(host, { type: 'doc', content: [image, para('a', 'x')] }, options())
    act(() => {
      editor.view.dispatch(editor.state.tr.setSelection(NodeSelection.create(editor.state.doc, 0)))
      editor.commands.commentStart()
    })
    expect(commentsState(editor.state)?.draft).toMatchObject({ blockId: 'i1', quote: 'Image' })
  })

  it('a stored block thread is outlined on its block, found by links, and gone with its block', () => {
    editor = createEditor(host, { type: 'doc', content: [para('a', 'x'), image] }, options())
    act(() => setThreads(editor, [thread('t1', 'i1')]))
    expect(blockThreadRanges(editor.state.doc, [thread('t1', 'i1')]).get('t1')).toEqual({
      from: blockPos(1),
      to: blockPos(2)
    })
    expect(threadRange(editor.state, 't1')).toEqual({ from: blockPos(1), to: blockPos(2) })
    expect(host.querySelector('img.hk-comment-block, .hk-comment-block')).not.toBeNull()
    act(() => void editor.commands.commentOpen('t1'))
    expect(host.querySelector('.hk-comment-block-active')).not.toBeNull()
    // The text block's own passage logic is untouched: no quote is searched for a block thread.
    expect(editor.getHTML()).not.toContain('data-comment')
    act(() => editor.view.dispatch(editor.state.tr.delete(blockPos(1), blockPos(2))))
    expect(threadRange(editor.state, 't1')).toBeNull()
  })
})

describe('Ask AI on media blocks', () => {
  it('an image stored in the workspace: presets and a question go out with the picture, nothing to edit', () => {
    open([image, para('a', 'after')], 0)
    act(() => void fireEvent.mouseMove(row(/Ask AI/u)))
    expect(screen.getByTestId('ai-action-describe')).toBeTruthy()
    expect(screen.queryByTestId('ai-action-improve')).toBeNull()
    act(() => screen.getByTestId('ai-action-extractText').click())
    expect(requests).toHaveLength(1)
    expect(requests[0]).toMatchObject({
      action: 'extractText',
      answer: true,
      units: [],
      media: { url: 'hikki-editor://assets/kyoto.png', kind: 'image' }
    })
    expect(requests[0].context.title).toBe('Trip')
    expect(host.querySelector('.hk-ai-media')).not.toBeNull()
  })

  it('the answer goes in right below the picture', () => {
    open([image, para('a', 'after')], 0)
    act(() => void fireEvent.mouseMove(row(/Ask AI/u)))
    act(() => screen.getByTestId('ai-action-describe').click())
    const id = requests[0].id
    act(() => {
      handleAIEvent(
        editor,
        { request: noop, cancel: noop, title: () => '' },
        { id, type: 'text', delta: 'A temple.' }
      )
      handleAIEvent(editor, { request: noop, cancel: noop, title: () => '' }, { id, type: 'done' })
    })
    act(() => screen.getByRole('button', { name: /Insert below/u }).click())
    expect(editor.state.doc.child(0).type.name).toBe('image')
    expect(editor.state.doc.child(1).textContent).toBe('A temple.')
    expect(editor.state.doc.child(2).textContent).toBe('after')
  })

  it('a PDF attachment is offered AI; video, audio and other files are not', () => {
    const pdf = {
      type: 'fileAttachment',
      attrs: { id: 'f1', src: 'hikki-editor://assets/a.pdf', name: 'Lease.pdf' }
    }
    open([pdf, para('a', 'x')], 0)
    act(() => void fireEvent.mouseMove(row(/Ask AI/u)))
    act(() => screen.getByTestId('ai-action-summarize').click())
    expect(requests[0].media).toEqual({
      url: 'hikki-editor://assets/a.pdf',
      kind: 'pdf',
      name: 'Lease.pdf'
    })
    cleanup()
    editor.destroy()
    const video = { type: 'video', attrs: { id: 'v1', src: 'hikki-editor://assets/a.mp4' } }
    const zip = {
      type: 'fileAttachment',
      attrs: { id: 'f2', src: 'hikki-editor://assets/a.zip', name: 'a.zip' }
    }
    for (const block of [video, zip]) {
      open([block, para('a', 'x')], 0)
      expect(screen.queryByRole('menuitem', { name: /Ask AI/u })).toBeNull()
      expect(screen.getByRole('menuitem', { name: /Comment/u })).toBeTruthy()
      cleanup()
      editor.destroy()
    }
    editor = createEditor(host, doc('x'))
  })
})
