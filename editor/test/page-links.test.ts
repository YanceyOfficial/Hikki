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

describe('page links', () => {
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
