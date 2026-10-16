import { useEffect, type ReactNode } from 'react'

import { Drawer, DrawerContent, DrawerTitle } from '@/components/ui/drawer'

import { useKeyboardViewport } from '../hooks/use-keyboard-viewport'
import { sheetOpened } from '../lib/sheet-presence'

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
  // While open, the native bars beside the page step aside (`sheet` message), so the sheet spans the screen.
  useEffect(() => (open ? sheetOpened() : undefined), [open])
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
        // iOS's own sheet: docked to the bottom edge (a device's rounded screen corners cut a floating one), its top
        // corners rounded large.
        className="rounded-t-sheet pt-1 [--drawer-content-height:auto] data-[swipe-direction=down]:rounded-t-sheet"
        style={
          {
            bottom: keyboard,
            '--drawer-content-max-height': `calc(${height}px - var(--hk-inset-top, 0px) - 12px)`,
            paddingBottom:
              keyboard > 0
                ? 'calc(var(--spacing) * 2)'
                : 'calc(env(safe-area-inset-bottom, 0px) + var(--hk-inset-bottom, 0px) + var(--spacing) * 2)'
          } as React.CSSProperties
        }
      >
        <DrawerTitle className="pt-1.5 pb-3 text-center text-base font-semibold">
          {title}
        </DrawerTitle>
        {children}
      </DrawerContent>
    </Drawer>
  )
}
