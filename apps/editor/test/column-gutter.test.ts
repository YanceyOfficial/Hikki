import { readFileSync } from 'node:fs'
import { join } from 'node:path'

import { describe, expect, it } from 'vitest'

// vitest runs from editor/ (happy-dom rewrites import.meta.url, so resolve from the cwd).
const css = readFileSync(join(process.cwd(), 'src/style.css'), 'utf8')

/** `--hk-column-pad-<side>`'s clamp (fine pointers), as [min px, vw, max px]. */
function pad(side: 'left' | 'right'): [number, number, number] {
  const match = new RegExp(
    `--hk-column-pad-${side}: clamp\\(--spacing\\((\\d+)\\), (\\d+)vw, --spacing\\((\\d+)\\)\\)`,
    'u'
  ).exec(css)
  if (!match) throw new Error(`no clamp for --hk-column-pad-${side}`)
  return [Number(match[1]) * 4, Number(match[2]), Number(match[3]) * 4]
}

const at = ([min, vw, max]: [number, number, number], width: number) =>
  Math.min(max, Math.max(min, (width * vw) / 100))

/** The + / ⋮⋮ handle: two 24px buttons and its 4px gap from the text (block-controls). */
const HANDLE_ROOM = 24 + 24 + 4

describe('the text column on a fine pointer', () => {
  it("keeps Notion's 96px margins in a wide window", () => {
    expect(at(pad('left'), 1440)).toBe(96)
    expect(at(pad('right'), 1440)).toBe(96)
  })

  it('narrows its margins with a narrow window, never below the handle’s room on the left', () => {
    for (const width of [320, 420, 800]) {
      const left = at(pad('left'), width)
      const right = at(pad('right'), width)
      expect(left).toBeGreaterThanOrEqual(HANDLE_ROOM)
      // A split view's narrowest side (320px) keeps most of its width for the text.
      expect(width - left - right).toBeGreaterThanOrEqual(width * 0.7)
    }
  })
})
