import { readFileSync } from 'node:fs'
import { join } from 'node:path'

import { act, cleanup, fireEvent, screen, within } from '@testing-library/react'
import type { Editor } from '@tiptap/core'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { marginPlacement, PHONE_QUERY } from '../src/components/comments'
import { createEditor } from '../src/core/editor'
import {
  commentRanges,
  commentsState,
  findQuote,
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

beforeEach(async () => {
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
  // The comments layer's first render was scheduled outside act: let it land before the test.
  await act(async () => {})
})
afterEach(() => {
  cleanup()
  editor.destroy()
  host.parentElement?.remove()
  vi.unstubAllGlobals()
})

/** An iPhone: a touch screen in a narrow window (jsdom has no matchMedia of its own). */
function stubPhone() {
  vi.stubGlobal('matchMedia', (query: string) => ({
    matches: query === PHONE_QUERY || query === '(pointer: coarse)',
    media: query,
    addEventListener: () => {},
    removeEventListener: () => {}
  }))
}

/** A thread on "quick", known to the store. */
function commentOnQuick(): string {
  act(() => {
    editor.commands.setTextSelection({ from: 5, to: 10 })
    editor.commands.commentStart()
    editor.commands.commentSend('hi')
  })
  const id = [...commentRanges(editor.state.doc).keys()][0]
  act(() => {
    editor.commands.commentOpen(null)
    setThreads(editor, [thread(id)])
  })
  return id
}

describe('comments', () => {
  it('a page without comments does no layout work as it is edited', () => {
    const measured = vi.spyOn(editor.view.dom, 'getBoundingClientRect')
    act(() => {
      for (const char of 'typing') editor.commands.insertContent(char)
      editor.commands.setTextSelection(3)
    })
    expect(measured).not.toHaveBeenCalled()
  })

  it('moving the caret does not walk the page for comment passages again', () => {
    commentOnQuick()
    const walked = vi.spyOn(editor.state.doc, 'descendants')
    act(() => {
      for (const pos of [2, 3, 4, 12, 14]) editor.commands.setTextSelection(pos)
    })
    expect(walked).not.toHaveBeenCalled()
  })

  it('margin cards are observed once, not again on every height report', async () => {
    let observed = 0
    vi.stubGlobal(
      'ResizeObserver',
      class {
        constructor(private readonly callback: ResizeObserverCallback) {}
        observe(target: Element) {
          observed++
          // As the spec does: a newly observed element is reported once.
          queueMicrotask(() =>
            this.callback([{ target } as ResizeObserverEntry], this as unknown as ResizeObserver)
          )
        }
        unobserve() {}
        disconnect() {}
      }
    )
    commentOnQuick()
    for (let i = 0; i < 10; i++) await act(async () => await Promise.resolve())
    expect(screen.getAllByTestId('comment-thread')).toHaveLength(1)
    expect(observed).toBeLessThanOrEqual(1)
  })

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

  it('a selection over a commented passage is painted over its wash, not under it', () => {
    commentOnQuick()
    act(() => editor.commands.setTextSelection({ from: 5, to: 10 }))
    // One span carries both: the later rule in the stylesheet decides which background shows.
    const span = host.querySelector('.hk-comment.hk-selection')
    expect(span?.textContent).toBe('quick')
    const styles = readFileSync(join(process.cwd(), 'src/style.css'), 'utf8')
    const wash = styles.indexOf('.tiptap .hk-comment {')
    const selected = styles.search(
      /\.tiptap \.hk-comment\.hk-selection\s*\{\s*background: var\(--color-selection\)/u
    )
    expect(wash).toBeGreaterThan(-1)
    expect(selected).toBeGreaterThan(wash)
    // While a drag paints its own layer behind the text, the wash steps aside.
    expect(styles).toMatch(
      /\.hk-column:has\(> \.hk-selection-layer:not\(:empty\)\) \.hk-comment\s*\{\s*background: transparent/u
    )
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

  it('an open thread whose passage lost its mark is marked again where its quote is, once', () => {
    act(() => setThreads(editor, [{ ...thread('lost'), quote: 'quick fox' }]))
    const [[id, ranges]] = [...commentRanges(editor.state.doc)]
    expect(id).toBe('lost')
    expect(editor.state.doc.textBetween(ranges[0].from, ranges[0].to)).toBe('quick fox')
    // Not when the quote is ambiguous, gone, or the thread resolved.
    expect(findQuote(editor.state.doc, 'u')).toBeNull()
    expect(findQuote(editor.state.doc, 'slow dog')).toBeNull()
    act(() => setThreads(editor, [{ ...thread('done', true), quote: 'jumps' }]))
    expect(commentRanges(editor.state.doc).has('done')).toBe(false)
  })

  it('on a phone an open thread is a bottom sheet: the quote, its comments, a reply field it does not focus', async () => {
    stubPhone()
    const id = commentOnQuick()
    act(() => editor.commands.commentOpen(id))
    const sheet = await screen.findByTestId('comment-sheet')
    // In a sheet over the page, not a card in the text column.
    expect(host.parentElement!.contains(sheet)).toBe(false)
    expect(sheet.textContent).toContain('quick')
    expect(sheet.textContent).toContain('first')
    const field = within(sheet).getByTestId('comment-field')
    expect(document.activeElement).not.toBe(field)
    expect(document.activeElement).not.toBe(editor.view.dom)
    // The per-comment actions still work there.
    expect(within(sheet).getByTestId('comment-more')).toBeTruthy()
    fireEvent.change(field, { target: { value: 'a reply' } })
    fireEvent.keyDown(field, { key: 'Enter' })
    expect(calls.at(-1)).toBe(`reply ${id} a reply`)
  })

  it('on a phone a new comment is written in the sheet, its field focused', async () => {
    stubPhone()
    act(() => {
      editor.commands.setTextSelection({ from: 5, to: 10 })
      editor.commands.commentStart()
    })
    const sheet = await screen.findByTestId('comment-sheet')
    const field = within(sheet).getByTestId('comment-field')
    await vi.waitFor(() => expect(document.activeElement).toBe(field))
    fireEvent.change(field, { target: { value: 'hello' } })
    fireEvent.keyDown(field, { key: 'Enter' })
    expect(calls).toEqual(['create quick hello'])
  })

  it('the sheet closes with Escape and with a tap on the dimmed page, never giving the page the caret', async () => {
    stubPhone()
    const id = commentOnQuick()
    act(() => editor.commands.commentOpen(id))
    const sheet = await screen.findByTestId('comment-sheet')
    fireEvent.keyDown(sheet, { key: 'Escape' })
    await vi.waitFor(() => expect(commentsState(editor.state)?.active).toBeNull())
    expect(document.activeElement).not.toBe(editor.view.dom)

    act(() => editor.commands.commentOpen(id))
    await screen.findByTestId('comment-sheet')
    const scrim = document.querySelector('[data-slot="drawer-overlay"]')!
    expect(scrim).toBeTruthy()
    fireEvent.pointerDown(scrim)
    fireEvent.mouseDown(scrim)
    fireEvent.pointerUp(scrim)
    fireEvent.mouseUp(scrim)
    fireEvent.click(scrim)
    await vi.waitFor(() => expect(commentsState(editor.state)?.active).toBeNull())
    expect(document.activeElement).not.toBe(editor.view.dom)
  })

  it('a tap on a commented passage opens its thread without placing the caret (no keyboard)', () => {
    stubPhone()
    const id = commentOnQuick()
    const passage = host.querySelector(`[data-comment="${id}"]`)!
    const at = { clientX: 10, clientY: 10 }
    fireEvent.touchStart(passage, { touches: [at], changedTouches: [at] })
    // Not cancelled: the browser's click (caret, focus, keyboard) would follow.
    const allowed = fireEvent.touchEnd(passage, { touches: [], changedTouches: [at] })
    expect(allowed).toBe(false)
    expect(commentsState(editor.state)?.active).toBe(id)
    expect(document.activeElement).not.toBe(editor.view.dom)

    // A drag over it (scrolling) is not a tap: left to the browser.
    act(() => editor.commands.commentOpen(null))
    fireEvent.touchStart(passage, { touches: [at], changedTouches: [at] })
    fireEvent.touchMove(passage, { touches: [{ clientX: 10, clientY: 60 }] })
    expect(fireEvent.touchEnd(passage, { touches: [], changedTouches: [at] })).toBe(true)
    expect(commentsState(editor.state)?.active).toBeNull()
  })
})
