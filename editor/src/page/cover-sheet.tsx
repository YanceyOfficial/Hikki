import { useTranslation } from 'react-i18next'

import { Drawer, DrawerContent, DrawerTitle } from '@/components/ui/drawer'

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
    <Drawer
      open={mode !== null}
      onOpenChange={(open) => {
        if (!open) onClose()
      }}
      showSwipeHandle
    >
      <DrawerContent
        data-testid="cover-sheet"
        className="pt-1 [--drawer-content-height:auto]"
        style={
          {
            '--drawer-content-max-height': 'calc(100dvh - var(--hk-inset-top, 0px) - 12px)',
            paddingBottom:
              'calc(env(safe-area-inset-bottom, 0px) + var(--hk-inset-bottom, 0px) + var(--spacing) * 2)'
          } as React.CSSProperties
        }
      >
        <DrawerTitle className="sr-only">{t('page.coverOptions')}</DrawerTitle>
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
          <div className="flex flex-col p-2">
            <MenuRow data-testid="cover-sheet-change" onClick={() => onMode('picker')}>
              {t('page.changeCover')}
            </MenuRow>
            <MenuRow
              data-testid="cover-sheet-remove"
              className="text-destructive hover:text-destructive"
              onClick={() => {
                onRemove()
                onClose()
              }}
            >
              {t('page.removeCover')}
            </MenuRow>
          </div>
        )}
      </DrawerContent>
    </Drawer>
  )
}
