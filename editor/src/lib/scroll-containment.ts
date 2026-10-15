/** Every popup surface (menus, popovers, panels) — the motion classes they all carry. */
const POPUP = '.hk-pop, .hk-pop-toggle'

const popupOf = (target: EventTarget | null) =>
  target instanceof Element ? target.closest(POPUP) : null

/** Whether something from `target` up to `root` can still scroll by `dy` (or `dx`) — a list not yet at its end. */
export function canScrollWithin(target: Element, root: Element, dy: number, dx = 0): boolean {
  for (let node: Element | null = target; node; node = node.parentElement) {
    const style = getComputedStyle(node)
    if (
      dy !== 0 &&
      /(auto|scroll)/u.test(style.overflowY) &&
      node.scrollHeight > node.clientHeight
    ) {
      if (dy < 0 && node.scrollTop > 0) return true
      if (dy > 0 && node.scrollTop + node.clientHeight < node.scrollHeight - 1) return true
    }
    if (dx !== 0 && /(auto|scroll)/u.test(style.overflowX) && node.scrollWidth > node.clientWidth) {
      if (dx < 0 && node.scrollLeft > 0) return true
      if (dx > 0 && node.scrollLeft + node.clientWidth < node.scrollWidth - 1) return true
    }
    if (node === root) break
  }
  return false
}

/** A wheel over a popup that can't use it is cancelled. */
function onWheel(event: WheelEvent) {
  const popup = popupOf(event.target)
  if (popup && !canScrollWithin(event.target as Element, popup, event.deltaY, event.deltaX))
    event.preventDefault()
}

/**
 * A scroll over a popup never moves the page behind it — whether the popup scrolls or not (CSS
 * `overscroll-behavior` only holds for an element that scrolls). Wheel and touch: a gesture the popup can't use
 * itself is cancelled. One set of document listeners; returns their removal.
 */
export function installScrollContainment(doc: Document = document): () => void {
  let last: { x: number; y: number } | null = null
  const onTouchStart = (event: TouchEvent) => {
    const touch = event.touches[0]
    last = touch ? { x: touch.clientX, y: touch.clientY } : null
  }
  const onTouchMove = (event: TouchEvent) => {
    const popup = popupOf(event.target)
    const touch = event.touches[0]
    if (!popup || !touch || !last || event.touches.length > 1) return
    // A finger moving up scrolls the content down.
    const dy = last.y - touch.clientY
    const dx = last.x - touch.clientX
    last = { x: touch.clientX, y: touch.clientY }
    if (!canScrollWithin(event.target as Element, popup, dy, dx)) event.preventDefault()
  }
  doc.addEventListener('wheel', onWheel, { passive: false, capture: true })
  doc.addEventListener('touchstart', onTouchStart, { passive: true, capture: true })
  doc.addEventListener('touchmove', onTouchMove, { passive: false, capture: true })
  return () => {
    doc.removeEventListener('wheel', onWheel, { capture: true })
    doc.removeEventListener('touchstart', onTouchStart, { capture: true })
    doc.removeEventListener('touchmove', onTouchMove, { capture: true })
  }
}
