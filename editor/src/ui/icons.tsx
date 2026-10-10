import { IconContext } from '@phosphor-icons/react'
import type { ReactNode } from 'react'

/**
 * Phosphor weight for every icon in the editor. Mirrors `baseWeight` in design/icons.json (the native side's
 * source) so both sides draw the same stroke — test/icons.test.ts fails when they drift.
 */
export const ICON_WEIGHT = 'bold' as const

export function IconProvider({ children }: { children: ReactNode }) {
  return <IconContext.Provider value={{ weight: ICON_WEIGHT }}>{children}</IconContext.Provider>
}
