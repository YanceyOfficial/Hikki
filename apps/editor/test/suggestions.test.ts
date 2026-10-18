import type { Editor } from '@tiptap/core'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { createEditor } from '../src/core/editor'
import { plainText } from '../src/core/extract'
import { emojiItems } from '../src/extensions/emoji-suggestion'
import type { PageIndexEntry, PageLinksHost } from '../src/extensions/page-links'
import { notifyPageIndexChanged, pageMentionItems } from '../src/extensions/page-mention'
import type { EmojiCategory } from '../src/lib/emoji-data'
import { settle } from './helpers'

const key = (editor: Editor, k: string) => {
  const event = new KeyboardEvent('keydown', { key: k, bubbles: true, cancelable: true })
  editor.view.someProp('handleKeyDown', (f) => f(editor.view, event))
}
/** Types like a user: through the input-rule handler, so Typography's rules fire. */
const type = (editor: Editor, text: string) => {
  for (const char of text) {
    const { view } = editor
    const { from, to } = view.state.selection
    const handled = view.someProp('handleTextInput', (f) =>
      f(view, from, to, char, () => view.state.tr.insertText(char, from, to))
    )
    if (!handled) view.dispatch(view.state.tr.insertText(char, from, to))
  }
}
const options = (selector: string) =>
  [...document.querySelectorAll(`${selector} [role=option]`)].map((e) =>
    e.getAttribute('aria-label')
  )

const chip = () => document.querySelector('a.hk-mention') as HTMLAnchorElement
const line = (...content: object[]) => ({ type: 'doc', content: [{ type: 'paragraph', content }] })

let pages: PageIndexEntry[] = []
const opened: string[] = []
const host: PageLinksHost = {
  pages: () => pages,
  currentPageId: () => 'here',
  untitled: () => 'Untitled',
  open: ({ pageId }) => void opened.push(pageId),
  openExternal: () => {}
}

let element: HTMLElement
let editor: Editor
beforeEach(() => {
  pages = [
    { id: 'p1', title: 'Roadmap', icon: '🗺️' },
    { id: 'p2', title: 'Reading list', icon: null },
    { id: 'p3', title: 'Trip to Kyoto', icon: '⛩️' }
  ]
  opened.length = 0
  element = document.createElement('div')
  document.body.append(element)
  editor = createEditor(element, null, { pageLinks: host })
  editor.commands.setTextSelection(1)
})
afterEach(() => {
  editor.destroy()
  element.remove()
  document.querySelectorAll('.hk-mention-menu, .hk-emoji-menu').forEach((e) => e.remove())
  vi.unstubAllGlobals()
})

describe('"@" page mentions', () => {
  it('ranks title prefixes first, then matches anywhere', () => {
    // "Trip" has an r too, but after the titles that start with one.
    expect(pageMentionItems(pages, 'r', 'Untitled').map((p) => p.id)).toEqual(['p1', 'p2', 'p3'])
    expect(pageMentionItems(pages, 'kyo', 'Untitled').map((p) => p.id)).toEqual(['p3'])
    expect(pageMentionItems(pages, '', 'Untitled')).toHaveLength(3)
    expect(pageMentionItems([{ id: 'x', title: '', icon: null }], 'unt', 'Untitled')).toHaveLength(
      1
    )
  })

  it('"@" lists pages, Enter inserts a chip with the icon and title, and a click opens the page', async () => {
    editor.commands.insertContent('See @tri')
    await settle()
    expect(options('.hk-mention-menu')).toEqual(['Trip to Kyoto'])
    key(editor, 'Enter')
    await settle()
    expect(document.querySelector('.hk-mention-menu')).toBeNull()
    const paragraph = editor.getJSON().content?.[0]
    expect(paragraph?.content?.[1]).toMatchObject({
      type: 'mention',
      attrs: { id: 'p3', label: 'Trip to Kyoto' }
    })
    expect(chip().getAttribute('href')).toBe('hikki://page/p3')
    expect(chip().textContent).toBe('⛩️Trip to Kyoto')
    // ProseMirror reads a click from mousedown + mouseup.
    const title = chip().querySelector('.hk-mention-title')!
    title.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, button: 0 }))
    title.dispatchEvent(new MouseEvent('mouseup', { bubbles: true, button: 0 }))
    expect(opened).toEqual(['p3'])
  })

  it('shows the page as it is now: renamed, then gone (the stored label stays as the fallback)', () => {
    editor.commands.setContent({
      type: 'doc',
      content: [
        { type: 'paragraph', content: [{ type: 'mention', attrs: { id: 'p1', label: 'Roadmap' } }] }
      ]
    })
    pages = [{ id: 'p1', title: 'Roadmap 2027', icon: '🚀' }]
    notifyPageIndexChanged()
    expect(chip().textContent).toBe('🚀Roadmap 2027')
    pages = []
    notifyPageIndexChanged()
    expect(chip().textContent).toBe('📄Roadmap')
    expect(chip().dataset.missing).toBe('true')
  })

  it('copies out as a page link and pastes back as a mention, not a link mark', () => {
    editor.commands.setContent({
      type: 'doc',
      content: [
        {
          type: 'paragraph',
          content: [{ type: 'mention', attrs: { id: 'p2', label: 'Reading list' } }]
        }
      ]
    })
    const html = editor.getHTML()
    expect(html).toContain('href="hikki://page/p2"')
    expect(html).toContain('data-type="mention"')
    editor.commands.setContent(html)
    expect(editor.getJSON().content?.[0].content?.[0]).toMatchObject({
      type: 'mention',
      attrs: { id: 'p2' }
    })
    expect(editor.getText()).toBe('@Reading list')
  })

  it("doesn't open in a code block or inside a word (an email address)", async () => {
    editor.commands.insertContent('mail me@exa')
    await settle()
    expect(document.querySelector('.hk-mention-menu')).toBeNull()
  })
})

describe('plain text of lines with inline nodes', () => {
  it('keeps the whole line around a mention or a ruby (search and word counts read it)', () => {
    expect(
      plainText(
        line(
          { type: 'text', text: 'Ask ' },
          { type: 'mention', attrs: { id: 'p1', label: 'Roadmap' } },
          { type: 'text', text: ' today' }
        )
      )
    ).toBe('Ask @Roadmap today')
    expect(
      plainText(
        line(
          { type: 'ruby', attrs: { reading: 'やく' }, content: [{ type: 'text', text: '役' }] },
          { type: 'text', text: 'に立つ' }
        )
      )
    ).toBe('役に立つ')
  })
})

describe('":" emoji', () => {
  const categories: EmojiCategory[] = [
    {
      key: 'smileys',
      label: 'Smileys',
      emojis: [
        {
          emoji: '😀',
          hexcode: '1F600',
          label: 'grinning face',
          keywords: 'grinning face smile 笑'
        },
        {
          emoji: '😂',
          hexcode: '1F602',
          label: 'face with tears of joy',
          keywords: 'face with tears of joy laugh'
        }
      ]
    },
    {
      key: 'animals',
      label: 'Animals',
      emojis: [{ emoji: '🐶', hexcode: '1F436', label: 'dog face', keywords: 'dog face pet' }]
    }
  ]

  it('searches labels and keywords, and offers recents for a bare ":"', () => {
    expect(emojiItems(categories, 'dog', []).map((e) => e.emoji)).toEqual(['🐶'])
    expect(emojiItems(categories, '笑', []).map((e) => e.emoji)).toEqual(['😀'])
    expect(emojiItems(categories, '', ['🐶', '❓', '😂']).map((e) => e.emoji)).toEqual(['🐶', '😂'])
  })

  it('":dog" + Enter types the character itself (no emoji node)', async () => {
    localStorage.clear()
    vi.stubGlobal(
      'fetch',
      vi.fn((url: URL) => {
        const body = String(url).endsWith('messages.json')
          ? { groups: [{ key: 'animals-nature', message: 'animals', order: 3 }] }
          : [
              {
                emoji: '🐶',
                hexcode: '1F436',
                label: 'dog face',
                tags: ['dog'],
                group: 3,
                order: 1
              }
            ]
        return Promise.resolve(new Response(JSON.stringify(body), { status: 200 }))
      })
    )
    editor.commands.insertContent('Walk the :dog')
    await vi.waitFor(() => expect(options('.hk-emoji-menu')).toEqual(['dog face']))
    key(editor, 'Enter')
    expect(editor.getText()).toBe('Walk the 🐶')
    expect(editor.getJSON().content?.[0].content).toEqual([{ type: 'text', text: 'Walk the 🐶' }])
  })

  it('a time or a smiley never opens it', async () => {
    editor.commands.insertContent('at 10:30 ')
    await settle()
    expect(document.querySelector('.hk-emoji-menu:not([hidden])')).toBeNull()
  })
})

describe('Typography', () => {
  it('turns --, ..., -> and (c) into their characters, and leaves quotes straight', () => {
    type(editor, 'a -- b... c -> d (c) "e"')
    expect(editor.getText()).toBe('a — b… c → d © "e"')
  })

  it('leaves code blocks alone', () => {
    editor.commands.setContent({
      type: 'doc',
      content: [{ type: 'codeBlock', content: [{ type: 'text', text: 'x' }] }]
    })
    editor.commands.setTextSelection(2)
    type(editor, ' -> y--')
    expect(editor.getText().trim()).toBe('x -> y--')
  })
})
