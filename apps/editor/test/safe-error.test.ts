import { getSchema } from '@tiptap/core'
import { Node as PMNode } from '@tiptap/pm/model'
import { afterEach, describe, expect, it, vi } from 'vitest'

import { importDocument } from '../src/core/convert'
import { editorExtensions } from '../src/core/editor'
import { installErrorForwarding, reportError } from '../src/core/errors'
import type { ToNativeMessage } from '../src/core/protocol'
import { safeErrorMessage, safeMessageText, safeStack } from '../src/lib/safe-error'

const SECRET = 'SECRET DIARY TEXT'

/** ProseMirror's own error for content in the wrong place: it quotes the first 50 characters of it. */
function invalidContentError(): Error {
  const schema = getSchema(editorExtensions())
  try {
    PMNode.fromJSON(schema, {
      type: 'doc',
      content: [{ type: 'text', text: SECRET }]
    }).check()
  } catch (error) {
    return error as Error
  }
  throw new Error('expected check() to throw')
}

describe('safeErrorMessage', () => {
  it("keeps ProseMirror's reason and drops the content it quotes", () => {
    const error = invalidContentError()
    expect(error.message).toContain(SECRET)
    expect(safeErrorMessage(error)).toBe('RangeError: Invalid content for node doc')
  })

  it('keeps a schema name after the colon, and plain messages as they are', () => {
    expect(safeErrorMessage(new RangeError('Unknown node type: futureBlock'))).toBe(
      'RangeError: Unknown node type: futureBlock'
    )
    expect(safeErrorMessage(new Error('quota exceeded'))).toBe('quota exceeded')
    expect(
      safeErrorMessage(new RangeError(`Position 3 outside of fragment (<p("${SECRET}")>)`))
    ).toBe('RangeError: Position 3 outside of fragment')
    expect(
      safeErrorMessage(new TypeError("Cannot read properties of undefined (reading 'x')"))
    ).toBe('TypeError: Cannot read properties of undefined')
    expect(
      safeMessageText(`Uncaught RangeError: Invalid content for node doc: <"${SECRET}">`)
    ).toBe('Uncaught RangeError: Invalid content for node doc')
    expect(safeErrorMessage(`JSON Parse error: Unexpected identifier "${SECRET}"`)).toBe(
      'JSON Parse error'
    )
  })

  it("keeps a stack's frames, not V8's message line", () => {
    const stack = `RangeError: Invalid content for node doc: ${SECRET}\n    at check (index.js:1:2)\nfn@hikki-editor://app/index.js:3:4`
    expect(safeStack(stack)).toBe('    at check (index.js:1:2)\nfn@hikki-editor://app/index.js:3:4')
  })
})

/** Forwarding into a window of the test's own, whose console the spies route to. */
function forward() {
  const sent: ToNativeMessage[] = []
  const quiet = { ...console, warn: () => {}, error: () => {} } as Console
  const target = Object.assign(new EventTarget(), { console: quiet }) as any
  installErrorForwarding({ post: (m) => Promise.resolve(void sent.push(m)) }, target)
  vi.spyOn(console, 'warn').mockImplementation((...a) => quiet.warn(...a))
  vi.spyOn(console, 'error').mockImplementation((...a) => quiet.error(...a))
  return { sent, target }
}

describe('what reaches the native log carries no content from an error', () => {
  afterEach(() => vi.restoreAllMocks())

  it('reported errors, console errors and uncaught errors', () => {
    const { sent, target } = forward()
    const error = invalidContentError()
    reportError('pageReadOnly', error)
    console.error('[hikki] load failed', error)
    target.dispatchEvent(
      Object.assign(new Event('error'), {
        message: `Uncaught ${error.name}: ${error.message}`,
        filename: 'index.js',
        lineno: 1,
        colno: 2,
        error
      })
    )
    const rejection = Object.assign(new Event('unhandledrejection'), { reason: error })
    target.dispatchEvent(rejection)
    expect(sent).toHaveLength(4)
    expect(JSON.stringify(sent)).not.toContain('SECRET')
    expect(sent[0]).toMatchObject({ detail: 'RangeError: Invalid content for node doc' })
  })

  it("an import that falls back to text logs ProseMirror's reason without the file's words", () => {
    const { sent } = forward()
    const error = invalidContentError()
    // The schema check refusing what the parser made (the parsers fit most things before it gets there).
    vi.spyOn(PMNode.prototype, 'check').mockImplementationOnce(() => {
      throw error
    })
    const page = importDocument(`${SECRET}\n\nmore`, 'markdown', 'x')
    expect(page.content.content?.length).toBe(2)
    expect(sent).toEqual([
      expect.objectContaining({
        message: 'import fell back to text: RangeError: Invalid content for node doc'
      })
    ])
  })
})
