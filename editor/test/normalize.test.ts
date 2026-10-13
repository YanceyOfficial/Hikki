import { describe, expect, it } from 'vitest'

import { normalizeBody } from '../src/core/normalize'

const p = (text: string) => ({ type: 'paragraph', content: [{ type: 'text', text }] })

describe('normalizeBody', () => {
  it('gives new pages one empty paragraph', () => {
    expect(normalizeBody(null, '')).toEqual({
      body: { type: 'doc', content: [{ type: 'paragraph' }] },
      title: ''
    })
  })

  it('drops a leading title node (previous build) and recovers its text when the stored title is empty', () => {
    const content = {
      type: 'doc',
      content: [{ type: 'title', content: [{ type: 'text', text: 'Old title' }] }, p('body')]
    }
    expect(normalizeBody(content, '')).toEqual({
      body: { type: 'doc', content: [p('body')] },
      title: 'Old title'
    })
    expect(normalizeBody(content, 'Stored').title).toBe('Stored')
  })

  it('drops a leading H1 only when it duplicates the stored title (first build)', () => {
    const h1 = { type: 'heading', attrs: { level: 1 }, content: [{ type: 'text', text: 'Plan' }] }
    expect(normalizeBody({ type: 'doc', content: [h1, p('x')] }, 'Plan').body.content).toEqual([
      p('x')
    ])
    // A real H1 that isn't the title stays.
    expect(normalizeBody({ type: 'doc', content: [h1, p('x')] }, 'Other').body.content).toEqual([
      h1,
      p('x')
    ])
    expect(normalizeBody({ type: 'doc', content: [h1] }, '').body.content).toEqual([h1])
  })

  it('is idempotent', () => {
    const once = normalizeBody({ type: 'doc', content: [{ type: 'title' }, p('a')] }, 'T')
    expect(normalizeBody(once.body, once.title)).toEqual(once)
  })
})
