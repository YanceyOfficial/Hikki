import { readFileSync } from 'node:fs'
import { join } from 'node:path'

import { describe, expect, it } from 'vitest'

import {
  GRADIENTS,
  coverBackground,
  coverImageURL,
  coverPosition,
  isImageCover,
  randomGradient,
  randomIcon,
  repositionedCover,
  withCoverPosition
} from '../src/lib/covers'

describe('covers', () => {
  it('resolves gradients and image URLs, rejects junk', () => {
    expect(coverBackground('gradient:ocean')).toBe(GRADIENTS.find((g) => g.id === 'ocean')!.css)
    expect(coverBackground('hikki-editor://assets/a.png')).toContain(
      'url("hikki-editor://assets/a.png")'
    )
    expect(coverBackground('gradient:nope')).toBeNull()
    expect(coverBackground('javascript:alert(1)')).toBeNull()
    expect(coverBackground(null)).toBeNull()
  })

  it('the built-in covers are the design tokens’ (the native side draws the same list)', () => {
    // vitest runs from apps/editor (happy-dom rewrites import.meta.url, so resolve from the cwd).
    const tokens = JSON.parse(
      readFileSync(join(process.cwd(), '../../design/tokens.json'), 'utf8')
    ) as { cover: Record<string, unknown> }
    const ids = Object.keys(tokens.cover).filter((k) => !k.startsWith('$'))
    expect(GRADIENTS.map((g) => g.id)).toEqual(ids)
    expect(coverBackground('gradient:night')).toBe('var(--cover-night)')
  })

  it('escapes quotes in image URLs', () => {
    expect(coverBackground('https://x/a".png')).toContain('a%22.png')
  })

  it('an image cover carries its vertical position as a fragment; gradients have none', () => {
    const url = 'hikki-editor://assets/a.png'
    expect(coverPosition(url)).toBe(50)
    expect(withCoverPosition(url, 35)).toBe(`${url}#y=35`)
    expect(coverPosition(`${url}#y=35`)).toBe(35)
    // Re-placing replaces the fragment; back to the middle drops it; out of range is clamped and rounded.
    expect(withCoverPosition(`${url}#y=35`, 80.4)).toBe(`${url}#y=80`)
    expect(withCoverPosition(`${url}#y=35`, 50)).toBe(url)
    expect(withCoverPosition(url, 140)).toBe(`${url}#y=100`)
    expect(withCoverPosition(url, -3)).toBe(`${url}#y=0`)
    expect(withCoverPosition('gradient:ocean', 20)).toBe('gradient:ocean')
    expect(coverPosition('gradient:ocean')).toBe(50)
    expect(isImageCover('gradient:ocean')).toBe(false)
    expect(isImageCover(url)).toBe(true)
    // The picture to load has no fragment; the background places it.
    expect(coverImageURL(`${url}#y=35`)).toBe(url)
    expect(coverImageURL('gradient:ocean')).toBeNull()
    expect(coverBackground(`${url}#y=35`)).toBe(`50% 35% / cover no-repeat url("${url}#y=35")`)
    expect(coverBackground(url)).toBe(`50% 50% / cover no-repeat url("${url}")`)
  })

  it('a drag moves the picture one pixel per pixel over its overflow, clamped to the range', () => {
    // 100 px of overflow: dragging down 25 px shows more of the top (the position goes down a quarter).
    expect(repositionedCover(50, 25, 200, 100)).toBe(25)
    expect(repositionedCover(50, -25, 200, 100)).toBe(75)
    expect(repositionedCover(90, -25, 200, 100)).toBe(100)
    expect(repositionedCover(10, 25, 200, 100)).toBe(0)
    // Overflow unknown: the cover's height is the range; nothing known at all: a fixed stretch.
    expect(repositionedCover(50, 50, 200, null)).toBe(25)
    expect(repositionedCover(50, 50, 0, null)).toBe(25)
    expect(repositionedCover(50, 50, 200, 0)).toBe(25)
  })

  it('random picks stay within the catalogs', () => {
    expect(randomGradient(() => 0)).toBe(`gradient:${GRADIENTS[0].id}`)
    expect(randomGradient(() => 0.9999)).toBe(`gradient:${GRADIENTS.at(-1)!.id}`)
  })

  it('a random icon is any emoji shown on its own — gaps and skin-tone modifiers drawn again', () => {
    const emoji = /^\p{Emoji_Presentation}$/u
    for (let i = 0; i < 200; i++) expect(randomIcon()).toMatch(emoji)
    // The first draws land on a skin-tone modifier (U+1F3FB, offset 251) and U+1F322 (offset 34, no emoji): again.
    const span =
      0x1f64f -
      0x1f300 +
      1 +
      (0x1f6ff - 0x1f680 + 1) +
      (0x1f9ff - 0x1f900 + 1) +
      (0x1faff - 0x1fa70 + 1)
    const draws = [251.5 / span, 34.5 / span, 0]
    expect(randomIcon(() => draws.shift()!)).toBe(String.fromCodePoint(0x1f300))
    // Nothing usable at all: a fixed fallback.
    expect(randomIcon(() => 251.5 / span)).toBe('📝')
  })
})
