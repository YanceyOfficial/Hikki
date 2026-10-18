import { readFileSync } from 'node:fs'
import { join } from 'node:path'

import { describe, expect, it } from 'vitest'

// vitest runs from editor/ (happy-dom rewrites import.meta.url, so resolve from the cwd).
const tokens = JSON.parse(
  readFileSync(join(process.cwd(), '../../design/tokens.json'), 'utf8')
) as {
  tone: { default: string; presets: Record<string, unknown> }
}
const css = readFileSync(join(process.cwd(), 'src/theme.css'), 'utf8')

describe('color tones', () => {
  const names = Object.keys(tokens.tone.presets)

  it('has a light and a dark palette for every preset in design/tokens.json', () => {
    for (const name of names) {
      const blocks = css.split(`[data-tone='${name}']`).length - 1
      expect(blocks, name).toBe(2)
    }
  })

  it('paints the default tone before the native side sets one', () => {
    expect(names).toContain(tokens.tone.default)
    expect(css).toContain(`:root[data-tone='${tokens.tone.default}'], :root:not([data-tone])`)
  })

  it('gives each palette a primary, its foreground and a ring', () => {
    const block = css.slice(css.indexOf(`[data-tone='${names[1]}']`))
    for (const v of ['--primary:', '--primary-foreground:', '--ring:', '--tone-ink:'])
      expect(block).toContain(v)
  })
})
