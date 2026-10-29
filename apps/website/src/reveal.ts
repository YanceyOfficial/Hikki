import { onCleanup, onMount } from 'solid-js'

/**
 * Small one-time moments (`.reveal`): drawn in their start state until they come into view, then they play once.
 *
 * REVEAL_SCRIPT runs in <head> before the page paints: without Reduce Motion it sets `data-reveal` on <html>, which
 * is what holds a `.reveal` in its start state — so nothing is shown, hidden and drawn again while the page hydrates.
 * Should the page's script never run, it lifts that after three seconds and everything simply shows.
 */
export const REVEAL_SCRIPT = `(function(){var r=document.documentElement;if(matchMedia('(prefers-reduced-motion: reduce)').matches)return;r.setAttribute('data-reveal','');setTimeout(function(){if(!r.hasAttribute('data-revealing'))r.removeAttribute('data-reveal')},3000)})()`

/** Marks each `.reveal` `data-shown` once most of it is on screen; CSS plays its transition from there. */
export function revealOnView() {
  onMount(() => {
    const root = document.documentElement
    if (!root.hasAttribute('data-reveal')) return
    root.setAttribute('data-revealing', '')
    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (!entry.isIntersecting) continue
          entry.target.setAttribute('data-shown', '')
          observer.unobserve(entry.target)
        }
      },
      { threshold: 0.6 }
    )
    for (const element of document.querySelectorAll('.reveal')) observer.observe(element)
    onCleanup(() => observer.disconnect())
  })
}
