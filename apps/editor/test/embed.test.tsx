import { act, fireEvent, render, screen } from '@testing-library/react'
import type { Editor } from '@tiptap/core'
import { siFigma } from 'simple-icons'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { brandFill, isDarkHex } from '../src/components/brand-logos'
import { BLOCK_TYPES } from '../src/core/blocks'
import { createEditor } from '../src/core/editor'
import { openEmbedPanel } from '../src/extensions/embed'
import type { PageLinksHost } from '../src/extensions/page-links'
import { embedFromHTML, embedFromURL, type LinkCard } from '../src/lib/embeds'
import { doc, settle } from './helpers'

let host: HTMLElement
let editor: Editor
let links: PageLinksHost
let linkPreview: ReturnType<typeof vi.fn<(url: string) => Promise<LinkCard | null>>>

beforeEach(() => {
  host = document.createElement('div')
  document.body.append(host)
  links = {
    pages: () => [],
    currentPageId: () => 'here',
    untitled: () => 'Untitled',
    open: vi.fn(),
    openExternal: vi.fn()
  }
  linkPreview = vi.fn(async (_url: string): Promise<LinkCard | null> => ({
    title: 'Yancey Blog',
    description: 'Thoughts and stories',
    icon: 'https://www.yanceyleo.com/icon.png'
  }))
  editor = createEditor(host, doc(''), { pageLinks: links, linkPreview })
})
afterEach(() => {
  editor.destroy()
  host.remove()
})

const frame = () => host.querySelector('.hk-embed iframe') as HTMLIFrameElement
/** A document with one embed as another device (or a paste) might have stored it. */
const stored = (src: string, original: string) => {
  editor.commands.setContent({
    type: 'doc',
    content: [
      { type: 'embed', attrs: { src, provider: 'vimeo', original, height: 300, html: null } }
    ]
  })
}

describe('embed block', () => {
  it('a link becomes a sandboxed frame on the provider page; Open sends the original outside', () => {
    editor.commands.insertEmbed(embedFromURL('https://youtu.be/dQw4w9WgXcQ')!)
    expect(editor.getJSON().content?.[0]).toMatchObject({
      type: 'embed',
      attrs: {
        src: 'https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ',
        provider: 'youtube',
        original: 'https://youtu.be/dQw4w9WgXcQ',
        height: 400
      }
    })
    const iframe = frame()
    expect(iframe.src).toBe('https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ')
    expect(iframe.getAttribute('sandbox')).toContain('allow-same-origin')
    expect(iframe.getAttribute('allow')).toContain('fullscreen')
    expect(iframe.style.height).toBe('400px')
    expect(iframe.title).toBe('Embedded content')
    fireEvent.click(host.querySelector('.hk-embed-open')!)
    expect(links.openExternal).toHaveBeenCalledWith('https://youtu.be/dQw4w9WgXcQ')
  })

  it('a stored src that is not an https page never loads, and an unsafe original gets no Open button', () => {
    stored('javascript:alert(1)', 'javascript:alert(1)')
    expect(frame().hasAttribute('src')).toBe(false)
    expect(host.querySelector('.hk-embed-open')).toBeNull()
    stored('hikki-editor://app/index.html', 'https://example.com/')
    expect(frame().hasAttribute('src')).toBe(false)
    stored('data:text/html,<script>alert(1)</script>', 'https://example.com/')
    expect(frame().hasAttribute('src')).toBe(false)
    stored('https://example.com/page', 'file:///etc/passwd')
    expect(frame().src).toBe('https://example.com/page')
    expect(host.querySelector('.hk-embed-open')).toBeNull()
  })

  it('HTML goes into a frame of its own with no origin', () => {
    editor.commands.insertEmbed(embedFromHTML('<p>hello</p>')!)
    const iframe = frame()
    expect(iframe.srcdoc).toContain('<p>hello</p>')
    expect(iframe.getAttribute('sandbox')).not.toContain('allow-same-origin')
    expect(iframe.hasAttribute('src')).toBe(false)
    expect(host.querySelector('.hk-embed-open')).toBeNull()
  })

  it('the handle under the frame sets its height, within the range', () => {
    editor.commands.insertEmbed(embedFromURL('https://vimeo.com/76979871')!)
    const handle = host.querySelector('.hk-embed-resize') as HTMLElement
    fireEvent.pointerDown(handle, { pointerId: 1, button: 0, clientY: 100 })
    fireEvent.pointerMove(handle, { pointerId: 1, clientY: 160 })
    expect(frame().style.height).toBe('460px')
    fireEvent.pointerUp(handle, { pointerId: 1, clientY: 160 })
    expect(editor.getJSON().content?.[0]).toMatchObject({ type: 'embed', attrs: { height: 460 } })
    fireEvent.pointerDown(handle, { pointerId: 2, button: 0, clientY: 100 })
    fireEvent.pointerMove(handle, { pointerId: 2, clientY: -900 })
    fireEvent.pointerUp(handle, { pointerId: 2, clientY: -900 })
    expect(editor.getJSON().content?.[0]).toMatchObject({ attrs: { height: 120 } })
  })

  it('the panel takes a link, refuses one it cannot frame, and inserts on Enter', async () => {
    act(() => openEmbedPanel(editor, 'generic'))
    const input = (await screen.findByLabelText('Link to embed')) as HTMLInputElement
    fireEvent.change(input, { target: { value: 'nope' } })
    fireEvent.keyDown(input, { key: 'Enter' })
    expect(screen.getByText('That link can’t be embedded.')).toBeTruthy()
    expect(host.querySelector('.hk-embed')).toBeNull()
    fireEvent.change(input, { target: { value: 'example.com/thing' } })
    fireEvent.keyDown(input, { key: 'Enter' })
    await settle()
    expect(host.querySelector('.hk-embed-card-url')?.textContent).toBe('https://example.com/thing')
    expect(document.querySelector('.hk-embed-panel')).toBeNull()
  })

  it('any other page is a link card: its details are read and, for one just added, saved into the block', async () => {
    act(() => openEmbedPanel(editor, 'generic'))
    const input = (await screen.findByLabelText('Link to embed')) as HTMLInputElement
    fireEvent.change(input, { target: { value: 'https://www.yanceyleo.com/' } })
    fireEvent.keyDown(input, { key: 'Enter' })
    await settle()
    await settle()
    expect(linkPreview).toHaveBeenCalledWith('https://www.yanceyleo.com/')
    expect(host.querySelector('.hk-embed iframe')).toBeNull()
    expect(host.querySelector('.hk-embed-card-title')?.textContent).toBe('Yancey Blog')
    expect(host.querySelector('.hk-embed-card-description')?.textContent).toBe(
      'Thoughts and stories'
    )
    expect((host.querySelector('.hk-embed-card-icon') as HTMLImageElement).src).toBe(
      'https://www.yanceyleo.com/icon.png'
    )
    expect(editor.getJSON().content?.[0]).toMatchObject({
      type: 'embed',
      attrs: {
        provider: 'generic',
        title: 'Yancey Blog',
        icon: 'https://www.yanceyleo.com/icon.png'
      }
    })
    fireEvent.click(host.querySelector('.hk-embed-card')!)
    expect(links.openExternal).toHaveBeenCalledWith('https://www.yanceyleo.com/')
  })

  it('an older card without details reads them for display only — viewing never edits the page', async () => {
    editor.commands.setContent({
      type: 'doc',
      content: [
        {
          type: 'embed',
          attrs: {
            src: 'https://old.example/',
            provider: 'generic',
            original: 'https://old.example/',
            html: null
          }
        }
      ]
    })
    expect(host.querySelector('.hk-embed-card-title')?.textContent).toBe('old.example')
    await settle()
    await settle()
    expect(host.querySelector('.hk-embed-card-title')?.textContent).toBe('Yancey Blog')
    expect(editor.getJSON().content?.[0]).toMatchObject({ attrs: { title: null } })
  })

  it('a card with stored details asks for nothing and a non-web link opens nothing', () => {
    editor.commands.setContent({
      type: 'doc',
      content: [
        {
          type: 'embed',
          attrs: {
            provider: 'generic',
            original: 'javascript:alert(1)',
            title: 'T',
            html: null,
            icon: 'javascript:x'
          }
        }
      ]
    })
    expect(linkPreview).not.toHaveBeenCalled()
    expect(host.querySelector('.hk-embed-card-icon')).toBeNull()
    fireEvent.click(host.querySelector('.hk-embed-card')!)
    expect(links.openExternal).not.toHaveBeenCalled()
  })

  it('the HTML panel takes a snippet (⌘Enter) and Escape anywhere cancels', async () => {
    act(() => openEmbedPanel(editor, 'html'))
    const area = (await screen.findByLabelText('HTML to embed')) as HTMLTextAreaElement
    fireEvent.change(area, { target: { value: '<em>x</em>' } })
    fireEvent.keyDown(area, { key: 'Enter' })
    expect(host.querySelector('.hk-embed')).toBeNull()
    fireEvent.keyDown(area, { key: 'Enter', metaKey: true })
    await settle()
    expect(frame().srcdoc).toContain('<em>x</em>')
    act(() => openEmbedPanel(editor, 'figma'))
    await screen.findByLabelText('Link to embed')
    act(
      () =>
        void document.body.dispatchEvent(
          new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true })
        )
    )
    expect(document.querySelector('.hk-embed-panel')).toBeNull()
  })
})

const embedBlocks = BLOCK_TYPES.filter((block) => block.group === 'embeds')

describe('the "/" menu’s Embeds group', () => {
  it('shows each service by its own logo; Embed and HTML keep their icons', () => {
    for (const block of embedBlocks) {
      const { container, unmount } = render(
        <block.icon size={18} className="text-subtle-foreground" />
      )
      const svg = container.querySelector('svg')!
      const generic = block.id === 'embed' || block.id === 'html'
      expect(svg.hasAttribute('data-logo'), block.id).toBe(!generic)
      unmount()
    }
  })

  it('lists a short set of work services, each opening a panel that names it', () => {
    expect(embedBlocks.map((block) => block.id)).toEqual([
      'embed',
      'html',
      'googleDrive',
      'figma',
      'miro',
      'loom',
      'airtable',
      'calendly',
      'gist',
      'codesandbox',
      'drawio',
      'excalidraw'
    ])
    editor = createEditor(host, doc(''))
    BLOCK_TYPES.find((block) => block.id === 'drawio')!.after!(editor)
    expect(screen.getByPlaceholderText('Paste a draw.io or diagrams.net link…')).toBeTruthy()
  })

  it('logos are single-path marks in their brand colour, the size of the icons beside them', () => {
    for (const block of embedBlocks.filter((b) => b.id !== 'embed' && b.id !== 'html')) {
      const { container, unmount } = render(
        <block.icon size={18} className="text-subtle-foreground" />
      )
      const svg = container.querySelector('svg')!
      expect(svg.getAttribute('width'), block.id).toBe('18')
      const fill = svg.getAttribute('fill')!
      // A brand colour, or the row's text colour for a near-black one (GitHub, CodeSandbox).
      expect(fill === 'currentColor' || /^#[0-9A-F]{6}$/iu.test(fill), block.id).toBe(true)
      expect(svg.getAttribute('class'), block.id).toBe('text-subtle-foreground')
      expect(svg.querySelectorAll('path'), block.id).toHaveLength(1)
      expect(svg.querySelector('[fill]:not(svg)'), block.id).toBeNull()
      unmount()
    }
    expect(['gist', 'codesandbox'].map((id) => colourOf(id))).toEqual([
      'currentColor',
      'currentColor'
    ])
    expect(colourOf('figma')).toBe(`#${siFigma.hex}`)
  })

  it('a near-black brand colour counts as dark', () => {
    expect(isDarkHex('181717')).toBe(true)
    expect(isDarkHex('F24E1E')).toBe(false)
    expect(brandFill('18A0FB')).toBe('#18A0FB')
  })
})

function colourOf(id: string): string | null {
  const block = embedBlocks.find((b) => b.id === id)!
  const { container, unmount } = render(<block.icon size={18} />)
  const fill = container.querySelector('svg')!.getAttribute('fill')
  unmount()
  return fill
}

const gist = () => embedFromURL('https://gist.github.com/octocat/6cad326836d38bd3a7ae')!
/** A frame's size report, as a gist's frame posts it (from the frame unless said otherwise). */
const report = (height: number, source: Window | null = frame().contentWindow) =>
  act(() => {
    window.dispatchEvent(
      new MessageEvent('message', { data: { hikkiEmbed: 'size', height }, source })
    )
  })

describe('a gist embed', () => {
  it('is styled like the page and sits in the card', () => {
    editor.commands.insertEmbed(gist())
    expect(host.querySelector('.hk-embed')!.hasAttribute('data-gist')).toBe(true)
    expect(frame().srcdoc).toContain('.gist .gist-meta')
    expect(frame().srcdoc).toContain('gist.github.com/octocat/6cad326836d38bd3a7ae.js')
    expect(frame().getAttribute('sandbox')).toBe('allow-scripts allow-popups')
  })

  it('fits its frame to the content it reports, up to the block’s height', () => {
    editor.commands.insertEmbed(gist())
    expect(frame().style.height).toBe('400px')
    report(180)
    expect(frame().style.height).toBe('180px')
    report(900)
    expect(frame().style.height).toBe('400px')
    report(10)
    expect(frame().style.height).toBe('48px')
    // Another window's message is ignored.
    report(200, window)
    expect(frame().style.height).toBe('48px')
  })

  it('a snippet that is not a gist keeps the block’s height whatever it reports', () => {
    editor.commands.insertEmbed(embedFromHTML('<p>hi</p>')!)
    expect(host.querySelector('.hk-embed')!.hasAttribute('data-gist')).toBe(false)
    report(150)
    expect(frame().style.height).toBe('400px')
  })
})
