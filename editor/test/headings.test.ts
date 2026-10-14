import { describe, expect, it } from 'vitest'

import { activeHeadingIndex } from '../src/core/headings'

describe('activeHeadingIndex (the outline follows the scroll)', () => {
  it('is the last heading whose top has passed the line', () => {
    expect(activeHeadingIndex([200, 600, 1200], 96, false)).toBe(-1)
    expect(activeHeadingIndex([40, 600, 1200], 96, false)).toBe(0)
    expect(activeHeadingIndex([-900, -300, 90], 96, false)).toBe(2)
    expect(activeHeadingIndex([-900, 100, 400], 96, false)).toBe(0)
  })

  it('is the last heading at the end of the page, even one that never reaches the line', () => {
    expect(activeHeadingIndex([-900, 300, 700], 96, true)).toBe(2)
    expect(activeHeadingIndex([], 96, true)).toBe(-1)
  })
})
