import { ImageIcon, TrashIcon } from '@phosphor-icons/react'
import { cn } from 'cn'
import type { ReactNode } from 'react'
import { useTranslation } from 'react-i18next'

import { BottomSheet } from '../components/bottom-sheet'
import { MenuRow } from '../components/menu-row'
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

/** A row of a sheet's grouped card: icon, label; a hairline above every row but the first. */
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
    <MenuRow
      data-testid={testId}
      className={cn(
        'h-13 gap-3.5 rounded-none px-4 text-base hover:bg-accent [&+&]:border-t [&+&]:border-border',
        destructive && 'text-destructive hover:text-destructive'
      )}
      onClick={onClick}
    >
      <span className={cn('flex w-6 justify-center', !destructive && 'text-subtle-foreground')}>
        {icon}
      </span>
      {children}
    </MenuRow>
  )
}
