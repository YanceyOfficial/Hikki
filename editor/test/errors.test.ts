import { describe, expect, it, vi } from 'vitest'

import { installErrorForwarding } from '../src/errors'
import type { ToNativeMessage } from '../src/protocol'

describe('installErrorForwarding', () => {
  it('forwards console.error, uncaught errors and unhandled rejections as log messages', async () => {
    const sent: ToNativeMessage[] = []
    const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {})
    installErrorForwarding({ post: async (m) => void sent.push(m) })

    console.error('boom', new Error('detail'))
    window.dispatchEvent(
      new ErrorEvent('error', { message: 'kaput', filename: 'main.js', lineno: 3, colno: 7 })
    )
    const rejection = new Event('unhandledrejection') as Event & { reason: unknown }
    rejection.reason = new Error('nope')
    window.dispatchEvent(rejection)

    expect(sent).toEqual([
      { type: 'log', level: 'error', message: 'boom detail', context: undefined },
      expect.objectContaining({
        type: 'log',
        level: 'error',
        message: 'uncaught: kaput',
        context: expect.objectContaining({ source: 'main.js:3:7' })
      }),
      expect.objectContaining({ type: 'log', level: 'error', message: 'unhandled rejection: nope' })
    ])
    errorSpy.mockRestore()
  })
})
