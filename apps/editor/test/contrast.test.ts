import { readFileSync } from 'node:fs'
import { join } from 'node:path'

import { describe, expect, it } from 'vitest'

// vitest runs from editor/ (happy-dom rewrites import.meta.url, so resolve from the cwd).
const colors = (
  JSON.parse(readFileSync(join(process.cwd(), '../../design/tokens.json'), 'utf8')) as {
    color: Record<string, { light: string; dark: string }>
  }
).color

type RGBA = [number, number, number, number]

function parse(value: string): RGBA {
  const hex = /^#([\da-f]{6})$/iu.exec(value)
  if (hex) {
    const n = Number.parseInt(hex[1], 16)
    return [n >> 16, (n >> 8) & 255, n & 255, 1]
  }
  const rgba = /^rgba?\(([^)]+)\)$/u.exec(value)
  if (!rgba) throw new Error(`unreadable colour ${value}`)
  const [r, g, b, a = 1] = rgba[1].split(',').map(Number)
  return [r, g, b, a]
}

/** `top` painted over an opaque `under`. */
function over(top: RGBA, under: RGBA): RGBA {
  const a = top[3]
  return [0, 1, 2].map((i) => top[i] * a + under[i] * (1 - a)).concat(1) as RGBA
}

function lin(c: number): number {
  const s = c / 255
  return s <= 0.039_28 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4
}

function luminance([r, g, b]: RGBA): number {
  return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
}

function contrast(a: RGBA, b: RGBA): number {
  const [hi, lo] = [luminance(a), luminance(b)].toSorted((x, y) => y - x)
  return (hi + 0.05) / (lo + 0.05)
}

/** The token's colour over each surface text sits on (a hover tint under it included), in one scheme. */
function worst(token: string, scheme: 'light' | 'dark'): number {
  const fg = parse(colors[token][scheme])
  const surfaces = ['background', 'card', 'popover'].map((s) => parse(colors[s][scheme]))
  const hovered = surfaces.map((s) => over(parse(colors.muted[scheme]), s))
  return Math.min(...[...surfaces, ...hovered].map((s) => contrast(over(fg, s), s)))
}

describe('text colours are readable (WCAG 2.2)', () => {
  for (const scheme of ['light', 'dark'] as const) {
    it(`secondary text reaches 4.5:1 (${scheme})`, () => {
      expect(worst('muted-foreground', scheme)).toBeGreaterThanOrEqual(4.5)
      expect(worst('subtle-foreground', scheme)).toBeGreaterThanOrEqual(4.5)
    })

    it(`placeholders and quiet icons reach 3:1 (${scheme})`, () => {
      expect(worst('placeholder', scheme)).toBeGreaterThanOrEqual(3)
    })
  }
})
