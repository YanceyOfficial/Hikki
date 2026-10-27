import { describe, expect, it } from 'vitest'

import { isImeKey } from '../src/lib/ime'

const key = (init: KeyboardEventInit & { keyCode?: number }) => new KeyboardEvent('keydown', init)

describe('isImeKey', () => {
  it('is a key typed while the input method composes', () => {
    expect(isImeKey(key({ key: 'a', isComposing: true }))).toBe(true)
  })

  it("is WebKit's committing Enter, which comes after compositionend with isComposing false", () => {
    // ISSUE-258: this Enter sent the field's half-typed pinyin.
    expect(isImeKey(key({ key: 'Enter', keyCode: 229 }))).toBe(true)
  })

  it('is not a plain Enter', () => {
    expect(isImeKey(key({ key: 'Enter', keyCode: 13 }))).toBe(false)
    expect(isImeKey(key({ key: 'Enter' }))).toBe(false)
  })
})
