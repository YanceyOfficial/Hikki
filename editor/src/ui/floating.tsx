import { computePosition, flip, offset, shift, size, type VirtualElement } from '@floating-ui/dom'
import type { ReactElement } from 'react'
import { flushSync } from 'react-dom'
import { createRoot, type Root } from 'react-dom/client'

import { cn, ui } from './cn'

/**
 * A React tree rendered into a body-level layer and positioned next to a caret rect.
 * Reusable for every editor popup (slash menu, mentions, link editor…).
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
    this.element.className = cn(bare ? 'fixed top-0 left-0 z-50' : ui.floating, className)
    document.body.append(this.element)
    this.root = createRoot(this.element)
  }

  render(node: ReactElement, anchor: (() => DOMRect | null) | null | undefined): void {
    flushSync(() => this.root.render(node))
    void this.position(anchor)
  }

  destroy(): void {
    this.root.unmount()
    this.element.remove()
  }

  private async position(anchor: (() => DOMRect | null) | null | undefined): Promise<void> {
    const rect = anchor?.()
    if (!rect) return
    const reference: VirtualElement = { getBoundingClientRect: () => rect }
    // On iOS the software keyboard shrinks only the *visual* viewport; keep the popup inside it.
    const vv = window.visualViewport
    const rootBoundary = vv
      ? { x: vv.offsetLeft, y: vv.offsetTop, width: vv.width, height: vv.height }
      : undefined
    const { x, y } = await computePosition(reference, this.element, {
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
    })
    Object.assign(this.element.style, { left: `${x}px`, top: `${y}px` })
  }
}
