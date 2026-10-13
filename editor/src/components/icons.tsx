import { IconContext } from '@phosphor-icons/react'
import type { ReactNode } from 'react'

/**
 * Phosphor weight and extra outline stroke (256-grid units) for every icon in the editor. Mirrors `baseWeight`
 * and `strokeBoost` in design/icons.json (the native side's source) so both sides draw the same line —
 * test/icons.test.ts fails when they drift. Phosphor has no weight between regular and bold; the stroke fills
 * that gap.
 */
export const ICON_WEIGHT = 'regular' as const
export const ICON_STROKE_BOOST = 4

export function IconProvider({ children }: { children: ReactNode }) {
  return (
    <IconContext.Provider
      value={{
        weight: ICON_WEIGHT,
        stroke: 'currentColor',
        strokeWidth: ICON_STROKE_BOOST,
        strokeLinejoin: 'round'
      }}
    >
      {children}
    </IconContext.Provider>
  )
}
