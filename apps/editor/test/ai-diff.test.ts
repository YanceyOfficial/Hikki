import { describe, expect, it } from 'vitest'

import { changeCount, changePairs, diffSide, diffText, diffUnits } from '../src/lib/ai-diff'

describe('diffUnits', () => {
  it('splits CJK by character, other text by word with its spaces, punctuation on its own', () => {
    expect(diffUnits('あまりません。')).toEqual(['あ', 'ま', 'り', 'ま', 'せ', 'ん', '。'])
    expect(diffUnits('the quick fox.')).toEqual(['the ', 'quick ', 'fox', '.'])
    expect(diffUnits('用 Swift 写')).toEqual(['用', ' ', 'Swift ', '写'])
  })
})

describe('diffText', () => {
  it('finds the characters a Japanese fix adds and removes', () => {
    expect(
      diffText(
        'いいえ、あまりません。うちからが遠いんです。',
        'いいえ、あまり行きません。うちから遠いんです。'
      )
    ).toEqual([
      { type: 'same', text: 'いいえ、あまり' },
      { type: 'add', text: '行き' },
      { type: 'same', text: 'ません。うちから' },
      { type: 'del', text: 'が' },
      { type: 'same', text: '遠いんです。' }
    ])
  })

  it('changes whole words in English', () => {
    expect(diffText('the quick fox', 'the fast fox')).toEqual([
      { type: 'same', text: 'the ' },
      { type: 'del', text: 'quick ' },
      { type: 'add', text: 'fast ' },
      { type: 'same', text: 'fox' }
    ])
  })

  it('handles empty sides and identical text', () => {
    expect(diffText('', 'new')).toEqual([{ type: 'add', text: 'new' }])
    expect(diffText('old', '')).toEqual([{ type: 'del', text: 'old' }])
    expect(diffText('same', 'same')).toEqual([{ type: 'same', text: 'same' }])
  })

  it('gives up on alignment for huge texts instead of hanging', () => {
    const before = '字'.repeat(3000)
    const after = '文'.repeat(3000)
    expect(diffText(before, after)).toEqual([
      { type: 'del', text: before },
      { type: 'add', text: after }
    ])
  })
})

describe('changeCount', () => {
  it('counts a replacement once and separate changes apart', () => {
    expect(changeCount(diffText('the quick fox', 'the fast fox'))).toBe(1)
    expect(
      changeCount(
        diffText(
          'いいえ、あまりません。うちからが遠いんです。',
          'いいえ、あまり行きません。うちから遠いんです。'
        )
      )
    ).toBe(2)
    expect(changeCount([{ type: 'same', text: 'x' }])).toBe(0)
  })
})

describe('changePairs / diffSide', () => {
  const diff = diffText(
    'いいえ、あまりません。うちからが遠いんです。',
    'いいえ、あまり行きません。うちから遠いんです。'
  )

  it('lists each change as what it replaced and with what', () => {
    expect(changePairs(diff)).toEqual([
      { from: '', to: '行き' },
      { from: 'が', to: '' }
    ])
    expect(changePairs(diffText('the quick fox', 'the fast fox'))).toEqual([
      { from: 'quick ', to: 'fast ' }
    ])
  })

  it('gives back either text', () => {
    expect(diffSide(diff, 'before')).toBe('いいえ、あまりません。うちからが遠いんです。')
    expect(diffSide(diff, 'after')).toBe('いいえ、あまり行きません。うちから遠いんです。')
  })
})
