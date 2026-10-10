import { describe, expect, it } from 'vitest'
import { normalizeDocument } from '../src/normalize'

describe('normalizeDocument', () => {
  it('creates a title and an empty paragraph for new documents', () => {
    expect(normalizeDocument(null)).toEqual({ type: 'doc', content: [{ type: 'title' }, { type: 'paragraph' }] })
  })

  it('migrates a leading level-1 heading (pre-title documents) into the title, dropping marks', () => {
    const old = {
      type: 'doc',
      content: [
        { type: 'heading', attrs: { level: 1 }, content: [{ type: 'text', text: 'Hello ' }, { type: 'text', marks: [{ type: 'bold' }], text: 'Hikki' }] },
        { type: 'paragraph', content: [{ type: 'text', text: 'body' }] },
      ],
    }
    expect(normalizeDocument(old)).toEqual({
      type: 'doc',
      content: [{ type: 'title', content: [{ type: 'text', text: 'Hello Hikki' }] }, { type: 'paragraph', content: [{ type: 'text', text: 'body' }] }],
    })
  })

  it('keeps other first blocks as body content under an empty title', () => {
    const doc = { type: 'doc', content: [{ type: 'heading', attrs: { level: 2 }, content: [{ type: 'text', text: 'h2' }] }] }
    expect(normalizeDocument(doc).content).toEqual([{ type: 'title' }, doc.content[0]])
  })

  it('is idempotent', () => {
    const once = normalizeDocument({ type: 'doc', content: [{ type: 'heading', attrs: { level: 1 } }] })
    expect(normalizeDocument(once)).toEqual(once)
  })
})
