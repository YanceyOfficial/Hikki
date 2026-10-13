import { computePosition, flip, offset, shift, size, type VirtualElement } from '@floating-ui/dom'
import { cn } from 'cn'
import { useEffect, useState, type ReactElement, type RefObject } from 'react'
import { flushSync } from 'react-dom'
import { createRoot, type Root } from 'react-dom/client'

/** Where a layer sits: a function giving the anchor's rect (null while it has none); nothing leaves it in place. */
export type FloatingAnchor = (() => DOMRect | null) | null | undefined

/**
 * A React tree rendered into a body-level layer and positioned next to a caret rect.
 * Reusable for every editor popup (slash menu, mentions, link editor…). It enters and leaves with the
 * shared motion (`hk-pop`, style.css).
 */
export class FloatingLayer {
  readonly element: HTMLDivElement
  private readonly root: Root
  private readonly bare: boolean

  /**
   * `bare`: only positioned — the content draws its own surface(s) and may overflow (a menu with a side
   * preview). Its height budget is then the `--hk-available-height` variable instead of max-height.
   */
  constructor(className: string, { bare = false }: { bare?: boolean } = {}) {
    this.bare = bare
    this.element = document.createElement('div')
    this.element.className = cn(
      'hk-pop',
      bare ? 'fixed top-0 left-0 z-50' : 'hk-floating',
      className
    )
    document.body.append(this.element)
    this.root = createRoot(this.element)
  }

  render(node: ReactElement, anchor: FloatingAnchor): void {
    flushSync(() => this.root.render(node))
    void this.position(anchor)
  }

  /** Plays the leave motion, then takes the layer down. */
  destroy(): void {
    leave(this.element, () => {
      this.root.unmount()
      this.element.remove()
    })
  }

  private async position(anchor: FloatingAnchor): Promise<void> {
    const rect = anchor?.()
    if (!rect) return
    const reference: VirtualElement = { getBoundingClientRect: () => rect }
    // On iOS the software keyboard shrinks only the *visual* viewport; keep the popup inside it.
    const vv = window.visualViewport
    const rootBoundary = vv
      ? { x: vv.offsetLeft, y: vv.offsetTop, width: vv.width, height: vv.height }
      : undefined
    let x: number
    let y: number
    let placement: string
    try {
      ;({ x, y, placement } = await computePosition(reference, this.element, {
        placement: 'bottom-start',
        strategy: 'fixed',
        middleware: [
          offset(6),
          flip({ rootBoundary, padding: 8 }),
          shift({ rootBoundary, padding: 8 }),
          size({
            rootBoundary,
            padding: 8,
            apply: ({ availableHeight, elements }) => {
              const height = `${Math.max(120, Math.min(this.bare ? 420 : 360, availableHeight))}px`
              if (this.bare) elements.floating.style.setProperty('--hk-available-height', height)
              else elements.floating.style.maxHeight = height
            }
          })
        ]
      }))
    } catch {
      // The layer was destroyed (or the document torn down) before the position came back.
      return
    }
    if (!this.element.isConnected) return
    Object.assign(this.element.style, { left: `${x}px`, top: `${y}px` })
    // Flipped above the anchor: the motion comes from below instead.
    this.element.toggleAttribute('data-above', placement.startsWith('top'))
  }
}

/**
 * Plays the shared leave motion on a surface (`.hk-pop[data-closing]`, style.css) and then calls `remove`
 * — at once when nothing animates (reduced motion, tests). The returned function cancels: the surface
 * stays, as if it had never been closing.
 */
export function leave(element: HTMLElement | null, remove: () => void): () => void {
  if (!element) {
    remove()
    return () => {}
  }
  element.dataset.closing = ''
  // The attribute's animation exists only once styles are recalculated.
  void element.offsetWidth
  const animations = element.getAnimations?.() ?? []
  let settled = false
  const finish = () => {
    if (settled) return
    settled = true
    remove()
  }
  if (animations.length === 0) {
    finish()
    return () => {}
  }
  void Promise.allSettled(animations.map((a) => a.finished)).then(finish)
  // Should the animation never report (a hidden tab pauses them), the surface still goes.
  const fallback = setTimeout(finish, 1000)
  return () => {
    settled = true
    clearTimeout(fallback)
    delete element.dataset.closing
  }
}

/**
 * Keeps a React-owned surface rendered after `open` turns false until its leave motion ends (`leave`).
 * Returns whether to render it; the element at `ref` carries `hk-pop`.
 */
export function usePresence(open: boolean, ref: RefObject<HTMLElement | null>): boolean {
  const [present, setPresent] = useState(open)
  // Reopened: back at once (a leave in progress is cancelled by the effect's cleanup).
  if (open && !present) setPresent(true)
  useEffect(() => {
    if (open || !present) return
    return leave(ref.current, () => setPresent(false))
  }, [open, present, ref])
  return open || present
}
