import { afterEach, describe, expect, it } from 'vitest'

import { EditorBridge } from '../src/core/bridge'
import { installErrorForwarding } from '../src/core/errors'
import type { ToNativeMessage } from '../src/core/protocol'
import { page } from './helpers'

const SECRET = 'SECRET DIARY TEXT'

describe('the native log never holds page content', () => {
  const restore: (() => void)[] = []
  afterEach(() => {
    for (const r of restore.splice(0)) r()
    document.body.replaceChildren()
  })

  /** A window whose console is this test's own, so the forwarding wraps it and not the real console. */
  const forwardingWindow = (sent: ToNativeMessage[]) => {
    const quiet = { ...console, warn: () => {}, error: () => {} } as Console
    const target = Object.assign(new EventTarget(), { console: quiet }) as any
    installErrorForwarding({ post: (m) => Promise.resolve(void sent.push(m)) }, target)
    const realWarn = console.warn
    const realError = console.error
    console.warn = (...a: unknown[]) => quiet.warn(...a)
    console.error = (...a: unknown[]) => quiet.error(...a)
    restore.push(() => {
      console.warn = realWarn
      console.error = realError
    })
  }

  it('loading content that does not fit the schema logs no word of it', () => {
    const logs: ToNativeMessage[] = []
    forwardingWindow(logs)
    const host = document.createElement('div')
    document.body.append(host)
    const bridge = new EditorBridge(
      host,
      { post: () => Promise.resolve(null) },
      { debounceMs: 400 }
    )
    bridge.loadDocument(
      page('p1', {
        content: {
          type: 'doc',
          content: [
            { type: 'paragraph', content: [{ type: 'text', text: SECRET }] },
            { type: 'futureBlock', content: [{ type: 'text', text: SECRET }] }
          ]
        }
      })
    )
    const lines = logs
      .filter((m) => m.type === 'log')
      .map((m) => (m as { message: string }).message)
    expect(lines.length).toBeGreaterThan(0)
    for (const line of lines) expect(line).not.toContain('SECRET')
  })

  it('forwards strings and errors only — objects and the rest of a Tiptap warning are left out', () => {
    const logs: ToNativeMessage[] = []
    forwardingWindow(logs)
    console.warn('[tiptap warn]: Invalid content.', 'Passed value:', `<p>${SECRET}</p>`)
    console.error('saving failed', { text: SECRET }, 3)
    const lines = logs.map((m) => (m as { message: string }).message)
    expect(lines).toEqual(['[tiptap warn]: Invalid content.', 'saving failed'])
  })
})
