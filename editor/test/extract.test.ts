import { describe, expect, it } from 'vitest'

import { blockTexts, plainText, wordCount } from '../src/core/extract'

const doc = {
  type: 'doc',
  content: [
    { type: 'heading', attrs: { level: 1 } },
    { type: 'heading', attrs: { level: 1 }, content: [{ type: 'text', text: '  会议纪要 ' }] },
    {
      type: 'paragraph',
      content: [
        { type: 'text', text: 'Hello ' },
        { type: 'text', marks: [{ type: 'bold' }], text: 'world' }
      ]
    },
    {
      type: 'bulletList',
      content: [
        {
          type: 'listItem',
          content: [{ type: 'paragraph', content: [{ type: 'text', text: 'item' }] }]
        }
      ]
    },
    { type: 'codeBlock', content: [{ type: 'text', text: 'let x = 1' }] }
  ]
}

describe('extract', () => {
  it('flattens nested blocks to one line each', () => {
    expect(blockTexts(doc)).toEqual(['  会议纪要 ', 'Hello world', 'item', 'let x = 1'])
    expect(plainText(doc)).toBe('  会议纪要 \nHello world\nitem\nlet x = 1')
  })

  it('counts CJK per character and other scripts per word', () => {
    expect(wordCount('会议纪要')).toBe(4)
    expect(wordCount("Hello world, it's v2")).toBe(4)
    expect(wordCount('今天 review 了 PR123')).toBe(5)
    expect(wordCount('')).toBe(0)
  })
})
