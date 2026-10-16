import { useSyncExternalStore } from 'react'

/** Whether a CSS media query matches now, kept current (e.g. `(pointer: coarse)`: a touch screen). */
export function useMediaQuery(query: string): boolean {
  return useSyncExternalStore(
    (notify) => {
      const list = window.matchMedia?.(query)
      list?.addEventListener('change', notify)
      return () => list?.removeEventListener('change', notify)
    },
    () => window.matchMedia?.(query).matches ?? false,
    () => false
  )
}
