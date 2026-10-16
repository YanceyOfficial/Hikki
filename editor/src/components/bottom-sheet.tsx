import type { ReactNode } from 'react'

import { Drawer, DrawerContent, DrawerTitle } from '@/components/ui/drawer'

import { useKeyboardViewport } from '../hooks/use-keyboard-viewport'

/**
 * A touch screen's panel as a bottom sheet over the dimmed page (the shadcn Drawer, as the comments' phone sheet):
 * the screen's width (short of a vertical bar or notch beside it), a grabber to swipe it away, above the software keyboard while a field in it is typing, clear of
 * the home indicator and the native bottom bar otherwise. The cover's actions and picker, the page icon's picker.
 */
export function BottomSheet({
  open,
  onClose,
  title,
  testId,
  children
}: {
  open: boolean
  onClose: () => void
  /** Read by screen readers (the sheet's name). */
  title: string
  testId?: string
  children: ReactNode
}) {
  const { height, keyboard } = useKeyboardViewport()
  return (
    <Drawer
      open={open}
      onOpenChange={(next) => {
        if (!next) onClose()
      }}
      showSwipeHandle
    >
      <DrawerContent
        data-testid={testId}
        finalFocus={false}
        className="pt-1 [--drawer-content-height:auto]"
        style={
          {
            bottom: keyboard,
            // Clear of a vertical bar beside it (an iPhone Duo's, folded or not) or a notch on its side: the page runs
            // under those, the sheet doesn't (0 everywhere else).
            left: 'env(safe-area-inset-left, 0px)',
            right: 'env(safe-area-inset-right, 0px)',
            '--drawer-content-max-height': `calc(${height}px - var(--hk-inset-top, 0px) - 12px)`,
            paddingBottom:
              keyboard > 0
                ? 'calc(var(--spacing) * 2)'
                : 'calc(env(safe-area-inset-bottom, 0px) + var(--hk-inset-bottom, 0px) + var(--spacing) * 2)'
          } as React.CSSProperties
        }
      >
        <DrawerTitle className="sr-only">{title}</DrawerTitle>
        {children}
      </DrawerContent>
    </Drawer>
  )
}
