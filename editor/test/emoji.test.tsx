import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import {
  buildCategories,
  rememberEmoji,
  recentEmoji,
  searchEmoji,
  type RawEmoji
} from '../src/ui/emoji-data'
import { EmojiPickerPanel } from '../src/ui/emoji-picker-panel'

const messages = {
  groups: [
    { key: 'smileys-emotion', message: 'smileys & emotion', order: 0 },
    { key: 'component', message: 'component', order: 2 },
    { key: 'animals-nature', message: 'animals & nature', order: 3 }
  ]
}
const data: RawEmoji[] = [
  {
    emoji: '🙂',
    hexcode: '1F642',
    label: 'slightly smiling face',
    tags: ['face', 'smile'],
    group: 0,
    order: 2,
    version: 1
  },
  {
    emoji: '😀',
    hexcode: '1F600',
    label: 'grinning face',
    tags: ['smile', 'happy'],
    group: 0,
    order: 1,
    version: 1
  },
  { emoji: '🏻', hexcode: '1F3FB', label: 'light skin tone', group: 2, order: 5, version: 1 },
  {
    emoji: '🐶',
    hexcode: '1F436',
    label: 'dog face',
    tags: ['pet'],
    group: 3,
    order: 9,
    version: 1
  },
  { emoji: '🫎', hexcode: '1FACE', label: 'moose', group: 3, order: 10, version: 99 },
  { emoji: '🇦', hexcode: '1F1E6', label: 'regional indicator A', version: 0 }
]

describe('emoji data', () => {
  it('groups by category in order, skipping components, ungrouped and too-new emoji', () => {
    const cats = buildCategories(data, messages)
    expect(cats.map((c) => c.key)).toEqual(['smileys-emotion', 'animals-nature'])
    expect(cats[0].label).toBe('Smileys & emotion')
    expect(cats[0].emojis.map((e) => e.emoji)).toEqual(['😀', '🙂'])
    expect(cats[1].emojis.map((e) => e.emoji)).toEqual(['🐶'])
  })

  it('searches label prefixes first, then keywords (incl. extra English keywords)', () => {
    const cats = buildCategories(data, messages, new Map([['1F436', 'puppy']]))
    expect(searchEmoji(cats, 'smile').map((e) => e.emoji)).toEqual(['😀', '🙂'])
    expect(searchEmoji(cats, 'grin').map((e) => e.emoji)).toEqual(['😀'])
    expect(searchEmoji(cats, 'PUPPY').map((e) => e.emoji)).toEqual(['🐶'])
    expect(searchEmoji(cats, '  ')).toEqual([])
  })

  it('remembers recents most-recent-first without duplicates', () => {
    localStorage.clear()
    rememberEmoji('🐶')
    rememberEmoji('😀')
    rememberEmoji('🐶')
    expect(recentEmoji()).toEqual(['🐶', '😀'])
  })
})

describe('EmojiPickerPanel', () => {
  beforeEach(() => {
    localStorage.clear()
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: URL) => {
        const path = String(url)
        const body = path.endsWith('messages.json') ? messages : data
        return new Response(JSON.stringify(body), { status: 200 })
      })
    )
  })
  afterEach(() => {
    cleanup()
    vi.unstubAllGlobals()
  })

  it('renders categories from bundled data, filters by search and picks', async () => {
    const onSelect = vi.fn()
    render(<EmojiPickerPanel onSelect={onSelect} locale="en" />)
    await waitFor(() => expect(screen.getByRole('button', { name: 'dog face' })).toBeTruthy())
    expect(screen.getByText('Animals & nature')).toBeTruthy()

    fireEvent.change(screen.getByLabelText('Search emoji…'), { target: { value: 'dog' } })
    expect(screen.queryByRole('button', { name: 'grinning face' })).toBeNull()
    fireEvent.click(screen.getByRole('button', { name: 'dog face' }))
    expect(onSelect).toHaveBeenCalledWith('🐶')
    expect(recentEmoji()).toEqual(['🐶'])
  })

  it('Enter in search picks the first result', async () => {
    const onSelect = vi.fn()
    render(<EmojiPickerPanel onSelect={onSelect} locale="en" />)
    const input = screen.getByLabelText('Search emoji…')
    await waitFor(() => expect(screen.getByRole('button', { name: 'dog face' })).toBeTruthy())
    fireEvent.change(input, { target: { value: 'smile' } })
    fireEvent.keyDown(input, { key: 'Enter' })
    expect(onSelect).toHaveBeenCalledWith('😀')
  })
})
