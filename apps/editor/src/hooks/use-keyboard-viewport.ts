import { useEffect, useState } from 'react'

function readViewport(): { height: number; keyboard: number } {
  const viewport = window.visualViewport
  const height = Math.round(viewport?.height ?? window.innerHeight)
  const keyboard = viewport
    ? Math.max(0, Math.round(window.innerHeight - viewport.height - viewport.offsetTop))
    : 0
  return { height, keyboard }
}

/**
 * The visual viewport against the layout one: its height, and how much of the window's bottom the software keyboard
 * covers (WKWebView, like Safari, keeps the layout viewport and shrinks the visual one).
 */
export function useKeyboardViewport(): { height: number; keyboard: number } {
  const [state, setState] = useState(readViewport)
  useEffect(() => {
    const update = () =>
      setState((previous) => {
        const next = readViewport()
        return next.height === previous.height && next.keyboard === previous.keyboard
          ? previous
          : next
      })
    const viewport = window.visualViewport
    viewport?.addEventListener('resize', update)
    viewport?.addEventListener('scroll', update)
    window.addEventListener('resize', update)
    return () => {
      viewport?.removeEventListener('resize', update)
      viewport?.removeEventListener('scroll', update)
      window.removeEventListener('resize', update)
    }
  }, [])
  return state
}
