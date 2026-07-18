import { useEffect, useState } from 'react'

const isMacTauri = () =>
  typeof window !== 'undefined' &&
  '__TAURI_INTERNALS__' in window &&
  navigator.userAgent.includes('Mac')

/**
 * True when the macOS traffic lights overlay our window chrome (Tauri, macOS,
 * windowed). False in fullscreen — macOS hides the buttons there.
 */
export function useTrafficLightInset(): boolean {
  const [fullscreen, setFullscreen] = useState(false)

  useEffect(() => {
    if (!isMacTauri()) return
    let unlisten: (() => void) | undefined
    let cancelled = false
    import('@tauri-apps/api/window').then(async ({ getCurrentWindow }) => {
      if (cancelled) return
      const win = getCurrentWindow()
      const sync = () =>
        win
          .isFullscreen()
          .then(setFullscreen)
          .catch(() => {})
      sync()
      unlisten = await win.onResized(sync)
    })
    return () => {
      cancelled = true
      unlisten?.()
    }
  }, [])

  return isMacTauri() && !fullscreen
}
