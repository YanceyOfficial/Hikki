import { act } from 'react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { EditorBridge, type Transport } from '../src/bridge'
import type { ToNativeMessage } from '../src/protocol'
import { doc, page, stripIds } from './helpers'

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
    expect(stripIds(editor().getJSON().content)).toEqual([
      { type: 'paragraph' },
      { type: 'paragraph', content: [{ type: 'text', text: 'existing' }] }
    ])
  })

  it('enterFromTitle reuses an empty first line instead of stacking blanks', () => {
    bridge.loadDocument(page('a', { content: doc('') }))
    bridge.enterFromTitle()
    expect(stripIds(editor().getJSON().content)).toEqual([{ type: 'paragraph' }])
  })

  it('rejects unknown commands', () => {
    bridge.loadDocument(page('a'))
    expect(bridge.exec('rm -rf')).toBe(false)
  })

  describe('block ids', () => {
    it('stamps ids on load without counting it as an edit (viewing never saves)', () => {
      bridge.loadDocument(page('a', { content: doc('one', 'two') }))
      vi.advanceTimersByTime(5000)
      expect(changed()).toHaveLength(0)
      expect(bridge.flush()).toBeNull()
      const ids = editor()
        .getJSON()
        .content.map((n: any) => n.attrs?.id)
      expect(ids.every((id: unknown) => typeof id === 'string' && id.length > 0)).toBe(true)
    })

    it('saves the ids with the first real edit and keeps stored ones', () => {
      const stored = {
        type: 'doc',
        content: [
          { type: 'paragraph', attrs: { id: 'keep-me' }, content: [{ type: 'text', text: 'x' }] }
        ]
      }
      bridge.loadDocument(page('a', { content: stored }))
      editor().commands.insertContentAt(editor().state.doc.content.size, { type: 'paragraph' })
      const snapshot = bridge.flush()
      expect(snapshot?.content.content?.[0].attrs?.id).toBe('keep-me')
      expect(snapshot?.content.content?.[1].attrs?.id).toEqual(expect.any(String))
    })
  })

  describe('saving while typing', () => {
    it('continuous typing still saves at least every maxWaitMs', () => {
      bridge = new EditorBridge(
        host,
        { post: async (m) => void sent.push(m) },
        { debounceMs: 400, maxWaitMs: 2000 }
      )
      bridge.loadDocument(page('a'))
      // A keystroke every 100 ms never leaves a 400 ms pause.
      for (let i = 0; i < 25; i++) {
        editor().commands.insertContent('x')
        vi.advanceTimersByTime(100)
      }
      expect(changed().length).toBeGreaterThanOrEqual(1)
    })
  })

  describe('content that does not fit the schema', () => {
    const future = {
      type: 'doc',
      content: [
        { type: 'paragraph', content: [{ type: 'text', text: 'before' }] },
        { type: 'columns', content: [{ type: 'column', content: [{ type: 'paragraph' }] }] }
      ]
    }

    it('opens read-only and never saves, so the stored content stays intact', () => {
      bridge.loadDocument(page('a', { title: 'Future', content: future }))
      expect(bridge.page.get().readOnly).toBe(true)
      expect(editor().isEditable).toBe(false)
      editor().commands.insertContent('typed')
      bridge.setTitle('Renamed')
      vi.advanceTimersByTime(5000)
      expect(changed()).toHaveLength(0)
      expect(bridge.flush()).toBeNull()
      expect(bridge.page.get().title).toBe('Future')
    })

    it('a valid page loaded afterwards is editable again', () => {
      bridge.loadDocument(page('a', { content: future }))
      bridge.loadDocument(page('b'))
      expect(bridge.page.get().readOnly).toBe(false)
      expect(editor().isEditable).toBe(true)
    })

    it('a locked page refuses edits, commands and header changes until it is unlocked', () => {
      bridge.loadDocument(page('a', { title: 'Plan', locked: true }))
      expect(bridge.page.get()).toMatchObject({ locked: true, readOnly: false })
      expect(editor().isEditable).toBe(false)
      expect(bridge.exec('bold')).toBe(false)
      bridge.setTitle('Renamed')
      bridge.setIcon('🔒')
      bridge.setCover('gradient:dusk')
      vi.advanceTimersByTime(5000)
      expect(changed()).toHaveLength(0)
      expect(sent.filter((m) => m.type === 'setIcon' || m.type === 'setCover')).toHaveLength(0)
      expect(bridge.page.get().title).toBe('Plan')
      // Unlocked while open (Page → Unlock): editable again, and edits save. (act: the menus' React roots
      // re-render on editability; flushed here rather than after the test's DOM is gone.)
      act(() => bridge.setLocked(false))
      expect(editor().isEditable).toBe(true)
      bridge.setTitle('Renamed')
      vi.advanceTimersByTime(1000)
      expect(changed()).toHaveLength(1)
      act(() => bridge.setLocked(true))
      expect(editor().isEditable).toBe(false)
    })
  })

  describe('reload (page changed on another device)', () => {
    it('applies the new content in place without saving or adding an undo step', () => {
      bridge.loadDocument(page('a', { content: doc('old') }))
      expect(
        bridge.reload(page('a', { title: 'New title', icon: '🌱', content: doc('new') }))
      ).toBe(true)
      expect(bridge.snapshot()?.text).toBe('new')
      expect(bridge.page.get()).toMatchObject({ title: 'New title', icon: '🌱' })
      vi.advanceTimersByTime(5000)
      expect(changed()).toHaveLength(0)
      expect(editor().can().undo()).toBe(false)
    })

    it('keeps unsaved edits instead (they win and are saved over it)', () => {
      bridge.loadDocument(page('a', { content: doc('old') }))
      editor().commands.insertContent('mine ')
      expect(bridge.reload(page('a', { content: doc('theirs') }))).toBe(false)
      expect(bridge.snapshot()?.text).toContain('mine')
    })

    it('ignores another page and invalid content', () => {
      bridge.loadDocument(page('a', { content: doc('old') }))
      expect(bridge.reload(page('b', { content: doc('other') }))).toBe(false)
      expect(
        bridge.reload(page('a', { content: { type: 'doc', content: [{ type: 'columns' }] } }))
      ).toBe(false)
      expect(bridge.snapshot()?.text).toBe('old')
    })

    it('keeps the caret where it was (clamped to the new length)', () => {
      bridge.loadDocument(page('a', { content: doc('hello world') }))
      editor().commands.setTextSelection(4)
      bridge.reload(page('a', { content: doc('hello brave world') }))
      expect(editor().state.selection.from).toBe(4)
      bridge.reload(page('a', { content: doc('hi') }))
      expect(editor().state.selection.from).toBeLessThanOrEqual(editor().state.doc.content.size)
    })
  })
})
