import { describe, expect, it } from 'vitest'

import {
  GRADIENTS,
  coverBackground,
  randomGradient,
  randomIcon,
  STARTER_ICONS
} from '../src/page/covers'

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

  it('escapes quotes in image URLs', () => {
    expect(coverBackground('https://x/a".png')).toContain('a%22.png')
  })

  it('random picks stay within the catalogs', () => {
    expect(randomGradient(() => 0)).toBe(`gradient:${GRADIENTS[0].id}`)
    expect(randomGradient(() => 0.9999)).toBe(`gradient:${GRADIENTS.at(-1)!.id}`)
    expect(STARTER_ICONS).toContain(randomIcon(() => 0.5))
  })
})
