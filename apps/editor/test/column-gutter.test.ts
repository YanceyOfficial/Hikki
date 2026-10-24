import { readFileSync } from 'node:fs'
import { join } from 'node:path'

import { describe, expect, it } from 'vitest'

import { marginPlacement } from '../src/components/comments'
import { LAYOUT } from '../src/generated/layout'

// vitest runs from editor/ (happy-dom rewrites import.meta.url, so resolve from the cwd).
const css = readFileSync(join(process.cwd(), 'src/style.css'), 'utf8')
const tokens = JSON.parse(readFileSync(join(process.cwd(), '../../design/tokens.json'), 'utf8'))

/** The column's side margins on a fine pointer at `width` (style.css: 10% of the window, clamped by the tokens). */
const pads = (width: number) => ({
  left: Math.min(LAYOUT.columnGutter, Math.max(LAYOUT.columnGutterMin, width / 10)),
  right: Math.min(LAYOUT.columnGutter, Math.max(20, width / 10))
})

/** The + / ⋮⋮ handle: two 24px buttons and its 4px gap from the text (block-controls). */
const HANDLE_ROOM = 24 + 24 + 4

describe('the text column on a fine pointer', () => {
  it('takes its margins from the layout tokens', () => {
    expect(css).toContain(
      '--hk-column-pad-left: clamp(var(--layout-column-gutter-min), 10vw, var(--layout-column-gutter));'
    )
    expect(css).toContain(
      '--hk-column-pad-right: clamp(--spacing(5), 10vw, var(--layout-column-gutter));'
    )
  })

  it("keeps Notion's 96px margins in a wide window", () => {
    expect(pads(1440)).toEqual({ left: 96, right: 96 })
  })

  it('narrows its margins with a narrow window, never below the handle’s room on the left', () => {
    for (const width of [320, 420, 800]) {
      const { left, right } = pads(width)
      expect(left).toBeGreaterThanOrEqual(HANDLE_ROOM)
      // A split view's narrowest side (320px) keeps most of its width for the text.
      expect(width - left - right).toBeGreaterThanOrEqual(width * 0.7)
    }
  })
})

describe('page geometry has one source', () => {
  it('the comments breakpoint is the column, its gutters and a margin card with its gap', () => {
    expect(LAYOUT.breakpoint.comments).toBe(
      tokens.size.column + 2 * LAYOUT.columnGutter + LAYOUT.commentCard + LAYOUT.commentGap
    )
  })

  it('from that breakpoint on, the column moved left (style.css) leaves the cards their room (comments.tsx)', () => {
    for (const width of [LAYOUT.breakpoint.comments, 1440, 1920]) {
      // style.css: margin-left = (100vw − column − 2 gutters − card − gap) / 2; the text ends a gutter before the
      // column's right edge.
      const marginLeft =
        (width -
          tokens.size.column -
          2 * LAYOUT.columnGutter -
          LAYOUT.commentCard -
          LAYOUT.commentGap) /
        2
      const textRight = marginLeft + LAYOUT.columnGutter + tokens.size.column
      expect(marginPlacement(width, textRight).wide).toBe(true)
    }
  })

  it('CSS reads the breakpoints and sizes from the tokens, not from literals', () => {
    expect(css).not.toMatch(/@media \((?:min|max)-width: (?:639|640|1000|1240)px\)/u)
    expect(css).toContain('@variant comments')
    expect(css).toContain('@variant max-phone')
  })
})
