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
    let cancelled = false
    let unlisten: (() => void) | undefined
    import('@tauri-apps/api/window').then(async ({ getCurrentWindow }) => {
      if (cancelled) return
      const win = getCurrentWindow()
      const sync = () =>
        win
          .isFullscreen()
          .then(setFullscreen)
          .catch(() => {})
      sync()
      const stop = await win.onResized(sync)
      if (cancelled) stop()
      else unlisten = stop
    })
    return () => {
      cancelled = true
      unlisten?.()
    }
  }, [])

  return isMacTauri() && !fullscreen
}
