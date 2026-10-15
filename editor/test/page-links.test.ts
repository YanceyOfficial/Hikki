import { Editor } from '@tiptap/core'
import UniqueID from '@tiptap/extension-unique-id'
import StarterKit from '@tiptap/starter-kit'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { isSafeHref } from '../src/core/links'
import { BlockControls } from '../src/extensions/block-controls'
import {
  blockLabel,
  copyLink,
  linkLabel,
  PageLinks,
  pageLinkHref,
  droppedPageLink,
  findTextMatch,
  PageLinksKey,
  parsePageLink,
  type PageLinksHost
} from '../src/extensions/page-links'

let host: HTMLElement
let editor: Editor
let links: PageLinksHost

const heading = (id: string, text: string) => ({
  type: 'heading',
  attrs: { id, level: 2 },
  content: [{ type: 'text', text }]
})
const para = (text: string, id = 'p1') => ({
  type: 'paragraph',
  attrs: { id },
  content: text ? [{ type: 'text', text }] : []
})

beforeEach(() => {
  host = document.createElement('div')
  document.body.append(host)
  links = {
    pages: () => [
      { id: 'notes', title: 'Meeting notes', icon: '📓' },
      { id: 'blank', title: '', icon: null }
    ],
    currentPageId: () => 'here',
    untitled: () => 'Untitled',
    open: vi.fn(),
    openExternal: vi.fn()
  }
  editor = new Editor({
    element: host,
    content: { type: 'doc', content: [heading('h1', '名词句基本文型'), para('')] },
    extensions: [
      // The app's own link setup (editor.ts), minus everything unrelated.
      StarterKit.configure({
        link: {
          openOnClick: false,
          protocols: ['hikki'],
          isAllowedUri: (u: string) => isSafeHref(u)
        }
      }),
      UniqueID.configure({ types: ['paragraph', 'heading'] }),
      BlockControls,
      PageLinks(links)
    ]
  })
})
afterEach(() => {
  editor.destroy()
  host.remove()
})

/** ProseMirror's paste prop, fed a clipboard (the test DOM's synthetic paste events carry none). */
const paste = (text: string, html = '') => {
  const plugin = PageLinksKey.get(editor.state)!
  const event = {
    clipboardData: { getData: (type: string) => (type === 'text/html' ? html : text) }
  }
  return plugin.props.handlePaste!.call(
    plugin,
    editor.view,
    event as unknown as ClipboardEvent,
    editor.state.doc.slice(0, 0)
  )
}

/**
 * ProseMirror's drop prop, fed a drag payload at a point the test DOM can't hit-test (posAtCoords is stubbed
 * to land inside the second block).
 */
const drop = (payload: Record<string, string>, moved = false) => {
  const plugin = PageLinksKey.get(editor.state)!
  const inside = editor.state.doc.child(0).nodeSize + 1
  vi.spyOn(editor.view, 'posAtCoords').mockReturnValue({ pos: inside, inside })
  const event = {
    clientX: 10,
    clientY: 10,
    preventDefault: vi.fn(),
    dataTransfer: { getData: (type: string) => payload[type] ?? '' }
  }
  const handled = plugin.props.handleDrop!.call(
    plugin,
    editor.view,
    event as unknown as DragEvent,
    editor.state.doc.slice(0, 0),
    moved
  )
  return { handled, prevented: event.preventDefault.mock.calls.length > 0 }
}

/** A drag's payload, as the drop handler reads it. */
const data = (map: Record<string, string>) =>
  ({ getData: (t: string) => map[t] ?? '' }) as unknown as DataTransfer

describe('page links', () => {
  it('reads the page link out of a drag payload: the URI list first, else the text', () => {
    expect(droppedPageLink(data({ 'text/uri-list': 'hikki://page/notes' }))).toEqual({
      pageId: 'notes',
      blockId: null
    })
    expect(
      droppedPageLink(
        data({ 'text/uri-list': '# a comment\nhikki://page/a#b\nhttps://x', 'text/plain': 'x' })
      )
    ).toEqual({ pageId: 'a', blockId: 'b' })
    expect(droppedPageLink(data({ 'text/plain': 'hikki://page/notes' }))).toEqual({
      pageId: 'notes',
      blockId: null
    })
    expect(droppedPageLink(data({ 'text/plain': 'hello' }))).toBeNull()
    expect(droppedPageLink(null)).toBeNull()
  })

  it('a page dragged from the sidebar drops as a labelled hyperlink where it lands', () => {
    const { handled, prevented } = drop({ 'text/uri-list': 'hikki://page/notes' })
    expect(handled).toBe(true)
    expect(prevented).toBe(true)
    const last = editor.getJSON().content?.at(-1)
    expect(last?.content?.[0]).toMatchObject({
      text: '📓 Meeting notes',
      marks: [{ type: 'link', attrs: { href: 'hikki://page/notes' } }]
    })
    // The caret sits after the link with the mark cleared, so typing on continues as plain text.
    expect(editor.isActive('link')).toBe(false)
  })

  it('other drops stay with ProseMirror: moved blocks, plain text, a locked page', () => {
    const before = editor.getJSON()
    expect(drop({ 'text/plain': 'hikki://page/notes' }, true).handled).toBe(false)
    expect(drop({ 'text/plain': 'just words' }).handled).toBe(false)
    editor.setEditable(false)
    expect(drop({ 'text/plain': 'hikki://page/notes' }).handled).toBe(false)
    expect(editor.getJSON()).toEqual(before)
  })

  it('parse and build hikki:// links with an optional block', () => {
    expect(parsePageLink('hikki://page/abc')).toEqual({ pageId: 'abc', blockId: null })
    expect(parsePageLink(' hikki://page/abc#blk-1 ')).toEqual({ pageId: 'abc', blockId: 'blk-1' })
    expect(parsePageLink('https://example.com')).toBeNull()
    expect(parsePageLink('hikki://page/a/b')).toBeNull()
    expect(pageLinkHref('abc', 'blk')).toBe('hikki://page/abc#blk')
  })

  it('labels: the block text here, the page title elsewhere, Untitled when nothing is known', () => {
    expect(linkLabel(editor, { pageId: 'here', blockId: 'h1' }, links)).toBe('名词句基本文型')
    expect(linkLabel(editor, { pageId: 'notes', blockId: 'x' }, links)).toBe('📓 Meeting notes')
    expect(linkLabel(editor, { pageId: 'blank', blockId: null }, links)).toBe('Untitled')
    expect(linkLabel(editor, { pageId: 'gone', blockId: null }, links)).toBe('Untitled')
    expect(blockLabel(editor.schema.nodeFromJSON(para('x'.repeat(200))))).toHaveLength(80)
  })

  it('pasting a block link as plain text lands as a labelled hyperlink', () => {
    editor.commands.setTextSelection(editor.state.doc.content.size - 1)
    expect(paste('hikki://page/here#h1')).toBe(true)
    const last = editor.getJSON().content?.at(-1)
    expect(last?.content?.[0]).toMatchObject({
      text: '名词句基本文型',
      marks: [{ type: 'link', attrs: { href: 'hikki://page/here#h1' } }]
    })
    expect(editor.getHTML()).toContain('href="hikki://page/here#h1"')
  })

  it('leaves a selection, other text and ready HTML links to Tiptap', () => {
    editor.commands.setTextSelection({ from: 1, to: 4 })
    expect(paste('hikki://page/notes')).toBe(false)
    editor.commands.setTextSelection(editor.state.doc.content.size - 1)
    expect(paste('just words')).toBe(false)
    expect(paste('hikki://page/notes', '<a href="hikki://page/notes">Meeting notes</a>')).toBe(
      false
    )
  })

  it('clicking a page link opens it (with its block); other links go to the system', () => {
    editor.commands.setContent({
      type: 'doc',
      content: [
        {
          type: 'paragraph',
          content: [
            {
              type: 'text',
              text: 'page',
              marks: [{ type: 'link', attrs: { href: 'hikki://page/notes#b2' } }]
            },
            { type: 'text', text: ' and ' },
            {
              type: 'text',
              text: 'web',
              marks: [{ type: 'link', attrs: { href: 'https://example.com' } }]
            }
          ]
        }
      ]
    })
    const [page, web] = host.querySelectorAll('a')
    page.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, button: 0 }))
    page.dispatchEvent(new MouseEvent('mouseup', { bubbles: true, button: 0 }))
    expect(links.open).toHaveBeenCalledWith({ pageId: 'notes', blockId: 'b2' })
    // Later than ProseMirror's double-click window, or the second click would count as one.
    vi.setSystemTime(Date.now() + 1000)
    web.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, button: 0 }))
    web.dispatchEvent(new MouseEvent('mouseup', { bubbles: true, button: 0 }))
    vi.useRealTimers()
    expect(links.openExternal).toHaveBeenCalledWith('https://example.com')
  })

  it('scrollToBlock tints the block and puts the caret in it', () => {
    const scrolled = vi.fn()
    HTMLElement.prototype.scrollIntoView = scrolled
    expect(editor.commands.scrollToBlock('h1')).toBe(true)
    expect(scrolled).toHaveBeenCalled()
    expect(host.querySelector('.hk-block-selected')).not.toBeNull()
    expect(editor.state.selection.$from.parent.textContent).toBe('名词句基本文型')
    expect(editor.commands.scrollToBlock('nope')).toBe(false)
  })

  it('findTextMatch lands on the first place a folded term occurs, across marks and accents', () => {
    editor.commands.setContent({
      type: 'doc',
      content: [
        para('Nothing here', 'a'),
        {
          type: 'paragraph',
          attrs: { id: 'b' },
          content: [
            { type: 'text', text: 'We met at the ' },
            { type: 'text', text: 'Café', marks: [{ type: 'bold' }] },
            { type: 'text', text: ' Royal' }
          ]
        },
        para('café again', 'c')
      ]
    })
    const doc = editor.state.doc
    const match = findTextMatch(doc, ['zzz', 'cafe royal'])!
    expect(doc.textBetween(match.from, match.to)).toBe('Café Royal')
    expect(doc.resolve(match.from).parent.attrs.id).toBe('b')
    // The earliest term in the block wins, whichever comes first in the query.
    const first = findTextMatch(doc, ['royal', 'met'])!
    expect(doc.textBetween(first.from, first.to)).toBe('met')
    expect(findTextMatch(doc, ['absent'])).toBeNull()
    expect(findTextMatch(doc, [])).toBeNull()
  })

  it('findTextMatch folds as the search index does: kana voicing, Hangul and ß survive', () => {
    // Terms arrive folded by Swift (`.caseInsensitive, .diacriticInsensitive`): ので stays ので, Straße → strasse.
    editor.commands.setContent({
      type: 'doc',
      content: [
        para('それで終わり', 'a'),
        para('雨なので休み', 'b'),
        para('한국어 die Straße', 'c')
      ]
    })
    const doc = editor.state.doc
    const at = (terms: string[]) => {
      const match = findTextMatch(doc, terms)
      return match && doc.textBetween(match.from, match.to)
    }
    expect(at(['ので'])).toBe('ので')
    expect(findTextMatch(doc, ['ので'])!.from).toBeGreaterThan(doc.child(0).nodeSize)
    expect(at(['한국'])).toBe('한국')
    expect(at(['strasse'])).toBe('Straße')
    expect(at(['cafe'])).toBeNull()
  })

  it('findTextMatch looks in the block the search named, and anywhere when that block is gone', () => {
    editor.commands.setContent({
      type: 'doc',
      content: [
        para('のですか', 'early'),
        heading('h2', 'ので表示理由'),
        para('no match here', 'none')
      ]
    })
    const doc = editor.state.doc
    const inBlock = findTextMatch(doc, ['ので'], 'h2')!
    expect(doc.resolve(inBlock.from).parent.attrs.id).toBe('h2')
    expect(doc.textBetween(inBlock.from, inBlock.to)).toBe('ので')
    // The block is there but its words aren't (edited since it was indexed): nothing to select.
    expect(findTextMatch(doc, ['ので'], 'none')).toBeNull()
    // A block id the page no longer has: the first place in the body.
    expect(doc.resolve(findTextMatch(doc, ['ので'], 'gone')!.from).parent.attrs.id).toBe('early')
  })

  it('revealText scrolls to the words, tints their block and selects them', () => {
    editor.commands.setContent({
      type: 'doc',
      content: [heading('h1', 'Title-ish'), para('first'), para('the 名词句 line', 'p2')]
    })
    const scrolled = vi.spyOn(window, 'scrollTo').mockImplementation(() => {})
    expect(editor.commands.revealText(['名词'])).toBe(true)
    expect(scrolled).toHaveBeenCalled()
    expect(host.querySelector('.hk-block-selected')).not.toBeNull()
    const { from, to } = editor.state.selection
    expect(editor.state.doc.textBetween(from, to)).toBe('名词')
    expect(editor.commands.revealText(['absent'])).toBe(false)
  })

  it('copyLink writes a ready hyperlink and the URL', async () => {
    const written: { items: Record<string, Blob> }[][] = []
    const write = async (items: { items: Record<string, Blob> }[]) => void written.push(items)
    Object.defineProperty(navigator, 'clipboard', {
      value: { write, writeText: vi.fn() },
      configurable: true
    })
    vi.stubGlobal(
      'ClipboardItem',
      class {
        constructor(public items: Record<string, Blob>) {}
      }
    )
    await copyLink('hikki://page/here#h1', 'A <b> heading')
    const item = written[0][0]
    expect(await item.items['text/plain'].text()).toBe('hikki://page/here#h1')
    expect(await item.items['text/html'].text()).toBe(
      '<a href="hikki://page/here#h1">A &lt;b&gt; heading</a>'
    )
    vi.unstubAllGlobals()
  })
})
