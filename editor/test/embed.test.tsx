import { act, fireEvent, screen } from '@testing-library/react'
import type { Editor } from '@tiptap/core'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { createEditor } from '../src/core/editor'
import { openEmbedPanel } from '../src/extensions/embed'
import type { PageLinksHost } from '../src/extensions/page-links'
import { embedFromHTML, embedFromURL } from '../src/lib/embeds'
import { doc, settle } from './helpers'

let host: HTMLElement
let editor: Editor
let links: PageLinksHost

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
  editor = createEditor(host, doc(''), { pageLinks: links })
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
      { type: 'embed', attrs: { src, provider: 'generic', original, height: 300, html: null } }
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
    editor.commands.insertEmbed(embedFromURL('https://example.com/')!)
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
    expect(frame().src).toBe('https://example.com/thing')
    expect(document.querySelector('.hk-embed-panel')).toBeNull()
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
