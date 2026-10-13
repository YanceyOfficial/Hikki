import {
  autoUpdate,
  computePosition,
  flip,
  offset,
  shift,
  size,
  type Placement
} from '@floating-ui/dom'
import { useEffect, useLayoutEffect, useRef, type ReactNode } from 'react'
import { createPortal } from 'react-dom'

import { cn, ui } from './cn'
import { usePresence } from './floating'

type Props = {
  anchor: HTMLElement | null
  open: boolean
  onClose: () => void
  placement?: Placement
  className?: string
  label: string
  children: ReactNode
}

/**
 * Anchored popover for React-owned UI (pickers, menus). Closes on outside press and Escape,
 * repositions on scroll/resize, and stays inside the visual viewport (iOS keyboard).
 */
export function Popover({
  anchor,
  open,
  onClose,
  placement = 'bottom-start',
  className = '',
  label,
  children
}: Props) {
  const ref = useRef<HTMLDivElement>(null)

  useLayoutEffect(() => {
    const floating = ref.current
    if (!open || !anchor || !floating) return
    return autoUpdate(anchor, floating, () => {
      const vv = window.visualViewport
      const rootBoundary = vv
        ? { x: vv.offsetLeft, y: vv.offsetTop, width: vv.width, height: vv.height }
        : undefined
      void computePosition(anchor, floating, {
        placement,
        strategy: 'fixed',
        middleware: [
          offset(6),
          flip({ rootBoundary, padding: 8 }),
          shift({ rootBoundary, padding: 8 }),
          size({
            rootBoundary,
            padding: 8,
            apply: ({ availableHeight, elements }) => {
              elements.floating.style.maxHeight = `${Math.max(160, availableHeight)}px`
            }
          })
        ]
      }).then(({ x, y, placement: placed }) => {
        Object.assign(floating.style, { left: `${x}px`, top: `${y}px` })
        floating.toggleAttribute('data-above', placed.startsWith('top'))
      })
    })
  }, [open, anchor, placement])

  useEffect(() => {
    if (!open) return
    const onPointerDown = (e: PointerEvent) => {
      const target = e.target as Node
      if (ref.current?.contains(target) || anchor?.contains(target)) return
      onClose()
    }
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.preventDefault()
        onClose()
      }
    }
    document.addEventListener('pointerdown', onPointerDown, true)
    document.addEventListener('keydown', onKeyDown, true)
    return () => {
      document.removeEventListener('pointerdown', onPointerDown, true)
      document.removeEventListener('keydown', onKeyDown, true)
    }
  }, [open, anchor, onClose])

  const present = usePresence(open, ref)

  if (!present) return null
  return createPortal(
    <div
      ref={ref}
      role="dialog"
      aria-label={label}
      className={cn('hk-pop', ui.floating, 'max-w-[calc(100vw-16px)]', className)}
    >
      {children}
    </div>,
    document.body
  )
}
