import { readFileSync } from 'node:fs'
import { join } from 'node:path'

import { ImageIcon } from '@phosphor-icons/react'
import { Fragment, act, createElement } from 'react'
import { createRoot } from 'react-dom/client'
import { describe, expect, it } from 'vitest'

import { ICON_STROKE_BOOST, ICON_WEIGHT } from '../src/components/icons'
import { ImageIcon as PageImageIcon, TextHOneIcon } from '../src/generated/icons'
import { setIconStyle, sfIcon, sfURL } from '../src/lib/sf-icons'

describe('icons', () => {
  // vitest runs from editor/ (happy-dom rewrites import.meta.url, so resolve from the cwd).
  it('uses the same Phosphor weight and stroke as the native app (design/icons.json)', () => {
    const manifest = JSON.parse(
      readFileSync(join(process.cwd(), '../../design/icons.json'), 'utf8')
    ) as { baseWeight: string; strokeBoost?: number }
    expect(ICON_WEIGHT).toBe(manifest.baseWeight)
    expect(ICON_STROKE_BOOST).toBe(manifest.strokeBoost ?? 0)
  })

  it('draws the SF Symbol as a mask on iOS, Phosphor elsewhere, and Phosphor where there is no symbol', () => {
    const host = document.createElement('div')
    const root = createRoot(host)
    const Icon = sfIcon(ImageIcon, 'photo')
    act(() => root.render(createElement(Icon, { size: 20, className: 'x' })))
    expect(host.querySelector('svg')).not.toBeNull()
    act(() => setIconStyle('sf'))
    const span = host.querySelector('span.hk-sf.x') as HTMLElement | null
    expect(span).not.toBeNull()
    expect(span?.style.width).toBe('20px')
    expect(span?.style.getPropertyValue('--sf')).toContain(sfURL('photo'))
    expect(host.querySelector('svg')).toBeNull()
    // The generated wrappers: one with a symbol, one without (the headings have no SF glyph).
    act(() =>
      root.render(
        createElement(Fragment, null, createElement(PageImageIcon), createElement(TextHOneIcon))
      )
    )
    expect(host.querySelectorAll('span.hk-sf').length).toBe(1)
    expect(host.querySelectorAll('svg').length).toBe(1)
    act(() => setIconStyle('phosphor'))
    expect(host.querySelectorAll('svg').length).toBe(2)
    act(() => root.unmount())
  })
})
