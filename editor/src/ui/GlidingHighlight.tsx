import { useEffect, useRef, type RefObject } from 'react'

/**
 * The selected row's background as one surface that glides between rows (keyboard or hover) instead of
 * switching from row to row. The list container is `relative` (and may scroll); rows carry `data-index`
 * and are `relative` themselves, so they paint above the surface. The first placement is instant, the
 * rest move with the shared motion (`.hk-glide`, style.css).
 */
export function GlidingHighlight({
  listRef,
  index
}: {
  listRef: RefObject<HTMLElement | null>
  index: number
}) {
  const ref = useRef<HTMLDivElement>(null)
  const placed = useRef(false)

  // Measured after every render (a passive effect: the list's ref is attached by then, which a layout
  // effect in a child runs before), since the rows may have changed with the list's content.
  useEffect(() => {
    const list = listRef.current
    const surface = ref.current
    if (!list || !surface) return
    const row = list.querySelector<HTMLElement>(`[data-index="${index}"]`)
    if (!row) {
      surface.style.opacity = '0'
      placed.current = false
      return
    }
    surface.toggleAttribute('data-instant', !placed.current)
    placed.current = true
    Object.assign(surface.style, {
      opacity: '1',
      translate: `${row.offsetLeft}px ${row.offsetTop}px`,
      width: `${row.offsetWidth}px`,
      height: `${row.offsetHeight}px`
    })
  })

  return <div ref={ref} aria-hidden className="hk-glide" data-testid="glide" />
}
