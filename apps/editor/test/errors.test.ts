import { describe, expect, it, vi } from 'vitest'

import { installErrorForwarding, notify, reportError } from '../src/core/errors'
import type { ToNativeMessage } from '../src/core/protocol'
import { ERRORS, errorDisplay, errorForCode, errorMessage } from '../src/generated/errors'

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

  it("sends toasts and reported failures (by code, the error's message as detail) to the app", async () => {
    const sent: ToNativeMessage[] = []
    installErrorForwarding({ post: async (m) => void sent.push(m) })
    notify('success', 'Link copied')
    reportError('uploadFailed', new Error('quota exceeded'), { kind: 'image' })
    reportError('copyFailed')
    expect(sent).toEqual([
      { type: 'toast', kind: 'success', message: 'Link copied' },
      { type: 'reportError', code: 4004, detail: 'quota exceeded', context: { kind: 'image' } },
      { type: 'reportError', code: 3004, detail: undefined, context: undefined }
    ])
  })
})

describe('error codes', () => {
  it('every code is unique, named HK-<number>, with a message in each language', () => {
    const codes = Object.values(ERRORS).map((e) => e.code)
    expect(new Set(codes).size).toBe(codes.length)
    expect(errorDisplay('pageSaveFailed')).toBe('HK-2001')
    expect(errorForCode(7101)).toBe('unsplashNotConfigured')
    expect(errorForCode(1)).toBe('unknown')
    expect(errorMessage('pageSaveFailed')).toBe("Couldn't save the page.")
  })
})
