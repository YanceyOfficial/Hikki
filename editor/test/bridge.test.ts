import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { EditorBridge, type Transport } from '../src/bridge'
import type { ToNativeMessage } from '../src/protocol'
import { doc, page } from './helpers'

describe('EditorBridge', () => {
  let sent: ToNativeMessage[]
  let bridge: EditorBridge
  let host: HTMLElement

  beforeEach(() => {
    vi.useFakeTimers()
    sent = []
    const transport: Transport = {
      post: async (m) => {
        sent.push(m)
        return m.type === 'saveAsset' ? 'hikki-editor://assets/x.png' : null
      }
    }
    host = document.createElement('div')
    document.body.append(host)
    bridge = new EditorBridge(host, transport, { debounceMs: 400 })
  })
  afterEach(() => {
    vi.useRealTimers()
    host.remove()
  })

  const changed = () => sent.filter((m) => m.type === 'changed')
  const editor = () => (bridge as any).editor

  it('loading a page does not emit a change and exposes header state', () => {
    bridge.loadDocument(
      page('a', { title: 'Plan', icon: '🌊', cover: 'gradient:ocean', content: doc('hi') })
    )
    vi.advanceTimersByTime(1000)
    expect(changed()).toHaveLength(0)
    expect(bridge.page.get()).toMatchObject({
      docId: 'a',
      title: 'Plan',
      icon: '🌊',
      cover: 'gradient:ocean'
    })
    expect(bridge.snapshot()).toMatchObject({ docId: 'a', title: 'Plan', text: 'hi', wordCount: 2 })
  })

  it('debounces body edits into one changed message', () => {
    bridge.loadDocument(page('a'))
    editor().commands.insertContent(' there')
    editor().commands.insertContent(' again')
    vi.advanceTimersByTime(399)
    expect(changed()).toHaveLength(0)
    vi.advanceTimersByTime(1)
    expect(changed()).toHaveLength(1)
  })

  it('title edits are saved through the same debounced snapshot, newlines stripped', () => {
    bridge.loadDocument(page('a'))
    bridge.setTitle('Weekly\nsync')
    vi.advanceTimersByTime(400)
    const msg = changed()[0]
    expect(msg.type === 'changed' && msg.snapshot.title).toBe('Weekly sync')
  })

  it('icon and cover changes are sent immediately, not debounced', () => {
    bridge.loadDocument(page('a'))
    bridge.setIcon('👋')
    bridge.setCover('gradient:dusk')
    expect(sent.filter((m) => m.type === 'setIcon' || m.type === 'setCover')).toEqual([
      { type: 'setIcon', docId: 'a', icon: '👋' },
      { type: 'setCover', docId: 'a', cover: 'gradient:dusk' }
    ])
    expect(changed()).toHaveLength(0)
  })

  it('saveAsset base64-encodes the file and resolves to the URL the native side returns', async () => {
    vi.useRealTimers()
    bridge.loadDocument(page('a'))
    const url = await bridge.saveAsset(
      new Blob([new Uint8Array([1, 2, 3])], { type: 'image/png' }),
      'png'
    )
    expect(url).toBe('hikki-editor://assets/x.png')
    expect(sent.find((m) => m.type === 'saveAsset')).toEqual({
      type: 'saveAsset',
      fileExtension: 'png',
      dataBase64: 'AQID'
    })
  })

  it('flushes a pending edit of the previous page before loading the next', () => {
    bridge.loadDocument(page('a'))
    editor().commands.insertContent('!')
    bridge.loadDocument(page('b'))
    expect(changed()).toHaveLength(1)
    const msg = changed()[0]
    expect(msg.type === 'changed' && msg.snapshot.docId).toBe('a')
  })

  it('flush() returns null when the page was only viewed (viewing must not bump "edited")', () => {
    bridge.loadDocument(page('a'))
    expect(bridge.flush()).toBeNull()
    editor().commands.insertContent('!')
    vi.advanceTimersByTime(400) // the debounced save already reported it
    expect(bridge.flush()).toBeNull()
  })

  it('flush() returns the snapshot and cancels the pending debounce', () => {
    bridge.loadDocument(page('a'))
    editor().commands.insertContent('!')
    expect(bridge.flush()?.docId).toBe('a')
    vi.advanceTimersByTime(1000)
    expect(changed()).toHaveLength(0)
  })

  it('does not share undo history across pages', () => {
    bridge.loadDocument(page('a'))
    editor().commands.insertContent('!')
    bridge.loadDocument(page('b', { content: doc('other') }))
    bridge.exec('undo')
    expect(bridge.snapshot()?.text).toBe('other')
  })

  it('collects headings for the outline and keeps them current', () => {
    bridge.loadDocument(
      page('a', {
        content: {
          type: 'doc',
          content: [
            { type: 'heading', attrs: { level: 2 }, content: [{ type: 'text', text: 'Goals' }] },
            { type: 'paragraph' }
          ]
        }
      })
    )
    expect(bridge.page.get().headings.map((h) => h.text)).toEqual(['Goals'])
    editor().commands.insertContentAt(editor().state.doc.content.size, {
      type: 'heading',
      attrs: { level: 3 },
      content: [{ type: 'text', text: 'Risks' }]
    })
    expect(bridge.page.get().headings.map((h) => [h.level, h.text])).toEqual([
      [2, 'Goals'],
      [3, 'Risks']
    ])
  })

  it('Backspace at the start of the body asks the header to focus the title', () => {
    bridge.loadDocument(page('a'))
    editor().commands.setTextSelection(1)
    const before = bridge.page.get().focusTitleRequest
    const event = new KeyboardEvent('keydown', {
      key: 'Backspace',
      bubbles: true,
      cancelable: true
    })
    editor().view.someProp('handleKeyDown', (f: any) => f(editor().view, event))
    expect(bridge.page.get().focusTitleRequest).toBe(before + 1)
  })

  it('blur() drops editor focus and is safe before any page is loaded', () => {
    expect(() => bridge.blur()).not.toThrow()
    bridge.loadDocument(page('a'))
    bridge.focus()
    vi.advanceTimersByTime(50) // Tiptap applies focus on the next frame
    expect(editor().isFocused).toBe(true)
    bridge.blur()
    vi.advanceTimersByTime(50)
    expect(editor().isFocused).toBe(false)
  })

  it('enterFromTitle focuses the body synchronously and starts a fresh first line', () => {
    bridge.loadDocument(page('a', { content: doc('existing') }))
    bridge.enterFromTitle()
    // Focus must already be in the editor — no frame delay for keystrokes to slip into the title.
    expect(editor().view.hasFocus()).toBe(true)
    expect(editor().state.selection.from).toBe(1)
    expect(editor().getJSON().content).toEqual([
      { type: 'paragraph' },
      { type: 'paragraph', content: [{ type: 'text', text: 'existing' }] }
    ])
  })

  it('enterFromTitle reuses an empty first line instead of stacking blanks', () => {
    bridge.loadDocument(page('a', { content: doc('') }))
    bridge.enterFromTitle()
    expect(editor().getJSON().content).toEqual([{ type: 'paragraph' }])
  })

  it('rejects unknown commands', () => {
    bridge.loadDocument(page('a'))
    expect(bridge.exec('rm -rf')).toBe(false)
  })
})
