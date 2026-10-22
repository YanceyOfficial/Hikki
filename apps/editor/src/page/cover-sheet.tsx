import { cn } from 'cn'
import type { ReactNode } from 'react'
import { useTranslation } from 'react-i18next'

import { Button } from '@/components/ui/button'

import { BottomSheet } from '../components/bottom-sheet'
import { ImageIcon, TrashIcon } from '../generated/icons'
import { CoverPicker } from './cover-picker'

/** What the cover's sheet shows: its actions (a long press on the cover), or the picker (Change cover). */
export type CoverSheetMode = 'actions' | 'picker'

/**
 * A touch screen's cover controls, as a bottom sheet instead of buttons always over the picture: a long press on the
 * cover lists Change cover and Remove (no Reposition on iPhone and iPad); Change cover shows the picker in the same sheet, the width of the
 * screen rather than a popover squeezed under the cover.
 */
export function CoverSheet({
  mode,
  current,
  onClose,
  onMode,
  onSelect,
  onRemove,
  onUpload
}: {
  mode: CoverSheetMode | null
  current: string | null
  onClose: () => void
  onMode: (mode: CoverSheetMode) => void
  onSelect: (cover: string) => void
  onRemove: () => void
  onUpload: (file: File) => Promise<void>
}) {
  const { t } = useTranslation()
  return (
    <BottomSheet
      open={mode !== null}
      onClose={onClose}
      title={t('page.coverOptions')}
      testId="cover-sheet"
    >
      {mode === 'picker' ? (
        <CoverPicker
          current={current}
          onSelect={(cover) => {
            onSelect(cover)
            onClose()
          }}
          onRemove={() => {
            onRemove()
            onClose()
          }}
          onUpload={async (file) => {
            await onUpload(file)
            onClose()
          }}
        />
      ) : (
        // iOS's grouped rows (the native ⋯ sheet's): one card, an icon before each label, hairlines between.
        <div className="px-4 pb-2">
          <div className="overflow-hidden rounded-2xl bg-muted">
            <SheetRow
              testId="cover-sheet-change"
              icon={<ImageIcon size={22} />}
              onClick={() => onMode('picker')}
            >
              {t('page.changeCover')}
            </SheetRow>
            <SheetRow
              testId="cover-sheet-remove"
              icon={<TrashIcon size={22} />}
              destructive
              onClick={() => {
                onRemove()
                onClose()
              }}
            >
              {t('page.removeCover')}
            </SheetRow>
          </div>
        </div>
      )}
    </BottomSheet>
  )
}

/**
 * A row of a sheet's grouped card, as iOS draws one: 56 pt tall, icon then label, a hairline above every row but the
 * first that starts after the icon. Plain rows (no border, no press shrink, no hover fill — the card is the surface).
 */
function SheetRow({
  testId,
  icon,
  destructive = false,
  onClick,
  children
}: {
  testId: string
  icon: ReactNode
  destructive?: boolean
  onClick: () => void
  children: ReactNode
}) {
  return (
    <Button
      variant="ghost"
      data-testid={testId}
      className={cn(
        'group/row relative h-14 w-full cursor-pointer justify-start gap-3.5 rounded-none border-0 px-4 text-left text-base font-normal hover:bg-transparent active:not-aria-[haspopup]:scale-100 active:bg-foreground/5 dark:hover:bg-transparent',
        // The hairline: above each row but the first, from the label's start to the card's edge.
        '[&+&]:before:absolute [&+&]:before:top-0 [&+&]:before:right-0 [&+&]:before:left-14 [&+&]:before:h-px [&+&]:before:bg-border',
        destructive ? 'text-destructive hover:text-destructive' : 'text-foreground'
      )}
      onClick={onClick}
    >
      <span className={cn('flex w-6 justify-center', !destructive && 'text-subtle-foreground')}>
        {icon}
      </span>
      {children}
    </Button>
  )
}
