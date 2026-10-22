import type { Icon, IconProps } from '@phosphor-icons/react'
import { createElement, type Ref, useSyncExternalStore } from 'react'

/**
 * The page's icons on iOS are SF Symbols — the glyphs the native chrome around the page draws — instead of Phosphor's
 * (two stroke weights side by side read as two apps). The native side says so once the page is up
 * (`window.hikki.setIconStyle('sf')`); the Mac's page keeps Phosphor. A symbol comes from the app as a picture
 * (`hikki-editor://sf/<name>.png`, drawn by EditorSchemeHandler) and is painted as a mask in the text's colour.
 */
export type IconStyle = 'phosphor' | 'sf'

let current: IconStyle = 'phosphor'
const listeners = new Set<() => void>()

export function setIconStyle(style: IconStyle): void {
  if (style === current) return
  current = style
  for (const listener of listeners) listener()
}

export function iconStyle(): IconStyle {
  return current
}

function subscribe(listener: () => void): () => void {
  listeners.add(listener)
  return () => listeners.delete(listener)
}

/** Where the app serves a symbol's picture. */
export function sfURL(name: string): string {
  return `hikki-editor://sf/${encodeURIComponent(name)}.png`
}

/**
 * A Phosphor icon component that draws the SF Symbol `sf` instead while the style is `sf` (null: this icon has no
 * symbol and stays Phosphor's). Same props: `size`, `className`, `color`, the DOM's; Phosphor's `weight` and
 * `mirrored` don't apply to a symbol. A ref (to the svg) rides along as a prop, as React 19 passes it.
 */
export function sfIcon(phosphor: Icon, sf: string | null): Icon {
  function SFIcon(props: IconProps & { ref?: Ref<SVGSVGElement> }) {
    const style = useSyncExternalStore(subscribe, iconStyle, iconStyle)
    if (style !== 'sf' || !sf) return createElement(phosphor, props)
    const {
      size = '1em',
      className,
      style: inline,
      color,
      alt,
      weight: _weight,
      mirrored: _mirrored,
      ref: _ref,
      ...rest
    } = props
    const dimension = typeof size === 'number' ? `${size}px` : size
    return createElement('span', {
      ...rest,
      role: alt ? 'img' : undefined,
      'aria-label': alt,
      'aria-hidden': alt ? undefined : true,
      className: className ? `hk-sf ${className}` : 'hk-sf',
      style: {
        ...inline,
        width: dimension,
        height: dimension,
        color,
        '--sf': `url("${sfURL(sf)}")`
      }
    })
  }
  SFIcon.displayName = phosphor.displayName ?? 'Icon'
  return SFIcon as unknown as Icon
}
