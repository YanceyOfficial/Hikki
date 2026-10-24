import { describe, expect, it } from 'vitest'

import { aiErrorText } from '../src/core/ai-errors'
import { setLocale } from '../src/core/i18n'

describe('aiErrorText', () => {
  it('says the trial is over when the app refuses AI (read only)', () => {
    setLocale('en')
    expect(aiErrorText({ code: 'locked' })).toBe(
      'The free trial has ended: unlock Hikki to use AI.'
    )
    setLocale('zh-Hans')
    expect(aiErrorText({ code: 'locked' })).toContain('解锁 Hikki')
    setLocale('en')
  })
})
