import { readFileSync } from 'node:fs'
import { join } from 'node:path'

import { describe, expect, it } from 'vitest'

import { ICON_STROKE_BOOST, ICON_WEIGHT } from '../src/ui/icons'

describe('icons', () => {
  // vitest runs from editor/ (happy-dom rewrites import.meta.url, so resolve from the cwd).
  it('uses the same Phosphor weight and stroke as the native app (design/icons.json)', () => {
    const manifest = JSON.parse(
      readFileSync(join(process.cwd(), '../design/icons.json'), 'utf8')
    ) as { baseWeight: string; strokeBoost?: number }
    expect(ICON_WEIGHT).toBe(manifest.baseWeight)
    expect(ICON_STROKE_BOOST).toBe(manifest.strokeBoost ?? 0)
  })
})
