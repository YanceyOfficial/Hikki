import { computePosition, flip, offset, shift, size, type VirtualElement } from '@floating-ui/dom'
import { cn } from 'cn'
import { useEffect, useState, type ReactElement, type RefObject } from 'react'
import { flushSync } from 'react-dom'
import { createRoot, type Root } from 'react-dom/client'

/** Where a layer sits: a function giving the anchor's rect (null while it has none); nothing leaves it in place. */
export type FloatingAnchor = (() => DOMRect | null) | null | undefined

/**
 * The open layers, newest last. One pair of document listeners serves them all: Escape and a press outside
 * every open layer dismiss the newest one (its own `onDismiss` decides what that means — close the menu, cancel
 * the panel). So every popup closes the same way, and a press on something else closes what was open before
 * it opens anything new.
 */
const openLayers: FloatingLayer[] = []

function dismissOnPress(event: PointerEvent): void {
  const top = openLayers.at(-1)
  if (!top || openLayers.some((layer) => layer.element.contains(event.target as Node))) return
  top.dismiss()
}

function dismissOnEscape(event: KeyboardEvent): void {
  if (event.key !== 'Escape') return
  const top = openLayers.at(-1)
  if (!top) return
  event.preventDefault()
  event.stopPropagation()
  top.dismiss()
}

function register(layer: FloatingLayer): void {
  if (openLayers.length === 0) {
    document.addEventListener('pointerdown', dismissOnPress, true)
    document.addEventListener('keydown', dismissOnEscape, true)
  }
  openLayers.push(layer)
}

function unregister(layer: FloatingLayer): void {
  const index = openLayers.indexOf(layer)
  if (index >= 0) openLayers.splice(index, 1)
  if (openLayers.length === 0) {
    document.removeEventListener('pointerdown', dismissOnPress, true)
    document.removeEventListener('keydown', dismissOnEscape, true)
  }
}

/** The layers the bus is managing right now (tests). */
export const openFloatingLayers = (): readonly FloatingLayer[] => openLayers

/**
 * A React tree rendered into a body-level layer and positioned next to a caret rect.
 * Reusable for every editor popup (slash menu, mentions, link editor…). It enters and leaves with the
 * shared motion (`hk-pop`, style.css), and with `onDismiss` it joins the dismiss bus above.
 */
export class FloatingLayer {
  readonly element: HTMLDivElement
  private readonly root: Root
  private readonly bare: boolean
  private readonly onDismiss: (() => void) | null
  private dismissed = false
  /** The anchor of the last render: the layer is placed against it again when the page scrolls under it. */
  private anchor: FloatingAnchor | null = null
  private frame = 0
  private readonly follow = () => {
    if (this.frame) return
    this.frame = requestAnimationFrame(() => {
      this.frame = 0
      if (this.anchor) void this.position(this.anchor)
    })
  }

  /**
   * `bare`: only positioned — the content draws its own surface(s) and may overflow (a menu with a side
   * preview). Its height budget is then the `--hk-available-height` variable instead of max-height.
   * `onDismiss`: what Escape or a press outside does (the caller closes the layer in it).
   */
  constructor(
    className: string,
    { bare = false, onDismiss = null }: { bare?: boolean; onDismiss?: (() => void) | null } = {}
  ) {
    this.bare = bare
    this.onDismiss = onDismiss
    this.element = document.createElement('div')
    this.element.className = cn(
      'hk-pop',
      bare ? 'fixed top-0 left-0 z-50' : 'hk-floating',
      className
    )
    document.body.append(this.element)
    this.root = createRoot(this.element)
    if (onDismiss) register(this)
    // The page scrolling (or the iOS keyboard moving the visual viewport) moves the anchor: the layer follows it.
    window.addEventListener('scroll', this.follow, { capture: true, passive: true })
    window.visualViewport?.addEventListener('resize', this.follow)
  }

  /** Escape or a press outside: once. */
  dismiss(): void {
    if (this.dismissed) return
    this.dismissed = true
    unregister(this)
    this.onDismiss?.()
  }

  render(node: ReactElement, anchor: FloatingAnchor): void {
    this.anchor = anchor
    flushSync(() => this.root.render(node))
    void this.position(anchor)
  }

  /** Plays the leave motion, then takes the layer down. */
  destroy(): void {
    unregister(this)
    this.anchor = null
    cancelAnimationFrame(this.frame)
    window.removeEventListener('scroll', this.follow, { capture: true })
    window.visualViewport?.removeEventListener('resize', this.follow)
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
