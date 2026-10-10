import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { EditorBridge, type Transport } from '../src/bridge'
import type { ToNativeMessage } from '../src/protocol'

const para = (text: string) => ({
  type: 'doc',
  content: [{ type: 'title', content: [{ type: 'text', text }] }, { type: 'paragraph' }],
})

describe('EditorBridge', () => {
  let sent: ToNativeMessage[]
  let bridge: EditorBridge
  let host: HTMLElement

  beforeEach(() => {
    vi.useFakeTimers()
    sent = []
    const transport: Transport = { post: async (m) => void sent.push(m) }
    host = document.createElement('div')
    document.body.append(host)
    bridge = new EditorBridge(host, transport, { debounceMs: 400 })
  })
  afterEach(() => {
    vi.useRealTimers()
    host.remove()
  })

  const changed = () => sent.filter((m) => m.type === 'changed')

  it('loading a document does not emit a change', () => {
    bridge.loadDocument({ id: 'a', content: para('hi') })
    vi.advanceTimersByTime(1000)
    expect(changed()).toHaveLength(0)
    expect(bridge.snapshot()).toMatchObject({ docId: 'a', title: 'hi', text: 'hi', wordCount: 1 })
  })

  it('debounces edits into one changed message', () => {
    bridge.loadDocument({ id: 'a', content: para('hi') })
    bridge.exec('bold')
    ;(bridge as any).editor.commands.insertContent(' there')
    ;(bridge as any).editor.commands.insertContent(' again')
    vi.advanceTimersByTime(399)
    expect(changed()).toHaveLength(0)
    vi.advanceTimersByTime(1)
    expect(changed()).toHaveLength(1)
  })

  it('flushes a pending edit of the previous doc before loading the next', () => {
    bridge.loadDocument({ id: 'a', content: para('hi') })
    ;(bridge as any).editor.commands.insertContent('!')
    bridge.loadDocument({ id: 'b', content: para('other') })
    expect(changed()).toHaveLength(1)
    const msg = changed()[0]
    expect(msg.type === 'changed' && msg.snapshot.docId).toBe('a')
  })

  it('flush() returns the snapshot and cancels the pending debounce', () => {
    bridge.loadDocument({ id: 'a', content: para('hi') })
    ;(bridge as any).editor.commands.insertContent('!')
    expect(bridge.flush()?.docId).toBe('a')
    vi.advanceTimersByTime(1000)
    expect(changed()).toHaveLength(0)
  })

  it('does not share undo history across documents', () => {
    bridge.loadDocument({ id: 'a', content: para('hi') })
    ;(bridge as any).editor.commands.insertContent('!')
    bridge.loadDocument({ id: 'b', content: para('other') })
    bridge.exec('undo')
    expect(bridge.snapshot()?.text).toBe('other')
  })

  it('blur() drops editor focus and is safe before any document is loaded', () => {
    expect(() => bridge.blur()).not.toThrow()
    bridge.loadDocument({ id: 'a', content: para('hi') })
    bridge.focus()
    vi.advanceTimersByTime(50) // Tiptap applies focus on the next frame
    expect((bridge as any).editor.isFocused).toBe(true)
    bridge.blur()
    vi.advanceTimersByTime(50)
    expect((bridge as any).editor.isFocused).toBe(false)
  })

  it('rejects unknown commands', () => {
    bridge.loadDocument({ id: 'a', content: null })
    expect(bridge.exec('rm -rf')).toBe(false)
  })
})
