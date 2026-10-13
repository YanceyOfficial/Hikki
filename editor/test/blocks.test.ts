import { describe, expect, it } from 'vitest'

import { BLOCK_TYPES, filterBlockTypes } from '../src/core/blocks'

const ids = (q: string) => filterBlockTypes(q).map((t) => t.id)

describe('filterBlockTypes', () => {
  it('returns the whole catalog in order for an empty query', () => {
    expect(ids('')).toEqual(BLOCK_TYPES.map((t) => t.id))
  })

  it('ranks exact alias matches first', () => {
    expect(ids('h2')[0]).toBe('heading2')
    expect(ids('todo')).toEqual(['taskList'])
  })

  it('matches Chinese and pinyin aliases', () => {
    expect(ids('待办')).toEqual(['taskList'])
    expect(ids('标题')).toEqual(['heading1', 'heading2', 'heading3', 'heading4'])
    expect(ids('daima')).toEqual(['codeBlock'])
    expect(ids('fenge')).toEqual(['divider'])
  })

  it('matches pinyin initials', () => {
    expect(ids('bt')).toEqual(['heading1', 'heading2', 'heading3', 'heading4'])
    expect(ids('db')).toEqual(['taskList'])
    expect(ids('dm')).toEqual(['codeBlock'])
  })

  it('matches word prefixes in titles and is case-insensitive', () => {
    expect(ids('LIST')).toEqual(expect.arrayContaining(['bulletList', 'orderedList', 'taskList']))
    expect(ids('numb')).toEqual(['orderedList'])
  })

  it('returns nothing for unrelated text', () => {
    expect(ids('zzz')).toEqual([])
  })
})
