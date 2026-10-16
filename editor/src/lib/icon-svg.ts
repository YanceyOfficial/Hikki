import type { IconSvgElement } from '@hugeicons/react'

/**
 * Hugeicons line weight for every icon in the editor (24-grid units, scaled with the icon). Mirrors
 * `strokeWidth` in design/icons.json, which the native fallback assets are drawn with, so both sides draw the
 * same line — test/icons.test.ts fails when they drift. 2 is also what shadcn's generated components pass.
 * `bold` marks an active toggle; Hugeicons' free set has no filled style, so `fill` paints the outline's
 * shapes solid (a sparkle, a star).
 */
export const ICON_STROKE_WIDTH = 2
export const ICON_BOLD_STROKE_WIDTH = 2.5

export type IconWeight = 'regular' | 'bold' | 'fill'

/** The icon's elements for a weight: `fill` fills every shape with the current color. */
export function iconElements(icon: IconSvgElement, weight: IconWeight = 'regular'): IconSvgElement {
  if (weight !== 'fill') return icon
  return icon.map(([tag, attrs]) => [tag, { ...attrs, fill: 'currentColor' }] as const)
}

const kebab = (name: string) => name.replace(/[A-Z]/gu, (c) => `-${c.toLowerCase()}`)
const escape = (value: string) => value.replace(/&/gu, '&amp;').replace(/"/gu, '&quot;')

/** Markup for an icon outside React (node views, plain DOM controls), at the editor's stroke. */
export function iconSvg(
  icon: IconSvgElement,
  { size = 18, weight = 'regular' }: { size?: number; weight?: IconWeight } = {}
): string {
  const stroke = weight === 'bold' ? ICON_BOLD_STROKE_WIDTH : ICON_STROKE_WIDTH
  const children = iconElements(icon, weight)
    .map(([tag, attrs]) => {
      const list = Object.entries({ ...attrs, strokeWidth: stroke })
        .filter(([key]) => key !== 'key')
        .map(([key, value]) => `${kebab(key)}="${escape(String(value))}"`)
      return `<${tag} ${list.join(' ')}/>`
    })
    .join('')
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" aria-hidden="true">${children}</svg>`
}
