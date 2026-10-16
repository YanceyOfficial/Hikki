import { readdirSync, readFileSync } from 'node:fs'
import { join } from 'node:path'

import * as hugeicons from '@hugeicons/core-free-icons'
import { describe, expect, it } from 'vitest'

import { ICON_STROKE_WIDTH, iconElements, iconSvg } from '../src/lib/icon-svg'

// vitest runs from editor/ (happy-dom rewrites import.meta.url, so resolve from the cwd).
const src = join(process.cwd(), 'src')
const files = (dir: string): string[] =>
  readdirSync(dir, { withFileTypes: true }).flatMap((e) =>
    e.isDirectory() ? files(join(dir, e.name)) : /\.tsx?$/u.test(e.name) ? [join(dir, e.name)] : []
  )
const sources = files(src).map((path) => ({ path, text: readFileSync(path, 'utf8') }))
const library = hugeicons as unknown as Record<string, unknown>

describe('icons', () => {
  it('draws with the same stroke as the native app (design/icons.json)', () => {
    const manifest = JSON.parse(
      readFileSync(join(process.cwd(), '../design/icons.json'), 'utf8')
    ) as {
      strokeWidth: number
      icons: Record<string, { hugeicons: string }>
    }
    expect(ICON_STROKE_WIDTH).toBe(manifest.strokeWidth)
    // Every native icon names a real Hugeicons icon.
    for (const [name, { hugeicons: icon }] of Object.entries(manifest.icons)) {
      expect(Array.isArray(library[icon]), `${name} → ${icon}`).toBe(true)
    }
  })

  it('resolves every icon the editor imports to a drawing', () => {
    let count = 0
    for (const { path, text } of sources) {
      for (const match of text.matchAll(
        /import \{([^}]*)\} from '@hugeicons\/core-free-icons'/gu
      )) {
        for (const name of match[1]
          .split(',')
          .map((n) => n.trim())
          .filter(Boolean)) {
          const data = library[name]
          expect(Array.isArray(data) && data.length > 0, `${name} in ${path}`).toBe(true)
          count += 1
        }
      }
    }
    expect(count).toBeGreaterThan(50)
  })

  it('passes no other stroke than the editor’s (shadcn components included)', () => {
    for (const { path, text } of sources) {
      for (const match of text.matchAll(/strokeWidth=\{([\d.]+)\}/gu)) {
        expect(Number(match[1]), path).toBe(ICON_STROKE_WIDTH)
      }
    }
  })

  it('renders markup for plain DOM controls at the editor’s stroke', () => {
    const svg = iconSvg(hugeicons.Add01Icon, { size: 18 })
    expect(svg).toContain('width="18"')
    expect(svg).toContain(`stroke-width="${ICON_STROKE_WIDTH}"`)
    expect(svg).toContain('stroke-linecap="round"')
    expect(svg).not.toContain('key=')
    expect(svg.match(/<path /gu)?.length).toBe(hugeicons.Add01Icon.length)
  })

  it('fills the shapes for the fill weight', () => {
    const filled = iconElements(hugeicons.SparklesIcon, 'fill')
    expect(filled.every(([, attrs]) => attrs.fill === 'currentColor')).toBe(true)
    expect(iconElements(hugeicons.SparklesIcon)).toBe(hugeicons.SparklesIcon)
  })
})
