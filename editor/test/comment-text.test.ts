import { describe, expect, it } from 'vitest'

import { bodyFromDraft, commentParts, draftFromBody, mentionQuery } from '../src/lib/comment-text'

describe('comment text', () => {
  it('reads mentions out of the stored text', () => {
    expect(commentParts('see [@Kyoto](hikki://page/k-1) and [@N4](hikki://page/n4).')).toEqual([
      { text: 'see ' },
      { label: 'Kyoto', pageId: 'k-1' },
      { text: ' and ' },
      { label: 'N4', pageId: 'n4' },
      { text: '.' }
    ])
    // A link to anything else is just text.
    expect(commentParts('[@x](https://example.com)')).toEqual([
      { text: '[@x](https://example.com)' }
    ])
  })

  it('turns "@Title" back into mentions, left to right; one typed away stays text', () => {
    const mentions = [
      { label: 'Kyoto', pageId: 'k' },
      { label: 'N4', pageId: 'n4' }
    ]
    expect(bodyFromDraft('@N4 vs @Kyoto', mentions)).toBe(
      '[@N4](hikki://page/n4) vs [@Kyoto](hikki://page/k)'
    )
    expect(bodyFromDraft('just @Kyo', mentions)).toBe('just @Kyo')
    const stored = '看 [@Kyoto](hikki://page/k)！'
    const draft = draftFromBody(stored)
    expect(draft.text).toBe('看 @Kyoto！')
    expect(bodyFromDraft(draft.text, draft.mentions)).toBe(stored)
  })

  it('finds the "@query" before the caret only at a word start', () => {
    expect(mentionQuery('see @kyo', 8)).toEqual({ start: 4, query: 'kyo' })
    expect(mentionQuery('@', 1)).toEqual({ start: 0, query: '' })
    expect(mentionQuery('mail@host', 9)).toBeNull()
    expect(mentionQuery('no mention', 10)).toBeNull()
  })
})
