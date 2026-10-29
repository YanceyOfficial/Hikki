import { onCleanup, onMount } from 'solid-js'

/**
 * A scene that plays as the page scrolls: the track's scroll sets `--p` (0 … 1) on the stage, and CSS turns that into
 * the motion. The first stretch holds the start and the last the end, so each can be looked at.
 *
 * With Reduce Motion nothing moves: the track loses `data-moving` (no extra scroll) and the stage gets `data-still`,
 * which shows the end. Without the script the markup's own `data-still` does the same.
 */
export function scrollScene(trackSelector: string, stageSelector: string) {
  onMount(() => {
    const track = document.querySelector<HTMLElement>(trackSelector)
    const stage = document.querySelector<HTMLElement>(stageSelector)
    if (!track || !stage) return
    const still = window.matchMedia('(prefers-reduced-motion: reduce)')
    let frame = 0
    const measure = () => {
      frame = 0
      const box = track.getBoundingClientRect()
      const run = box.height - window.innerHeight
      const raw = run > 0 ? -box.top / run : 1
      const p = Math.min(1, Math.max(0, (raw - 0.12) / 0.7))
      stage.style.setProperty('--p', p.toFixed(4))
    }
    const schedule = () => {
      if (!frame) frame = requestAnimationFrame(measure)
    }
    const apply = () => {
      const moving = !still.matches
      track.toggleAttribute('data-moving', moving)
      stage.toggleAttribute('data-still', !moving)
      if (moving) measure()
      else stage.style.removeProperty('--p')
    }
    apply()
    window.addEventListener('scroll', schedule, { passive: true })
    window.addEventListener('resize', schedule)
    still.addEventListener('change', apply)
    onCleanup(() => {
      cancelAnimationFrame(frame)
      window.removeEventListener('scroll', schedule)
      window.removeEventListener('resize', schedule)
      still.removeEventListener('change', apply)
    })
  })
}
