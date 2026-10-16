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
    </BottomSheet>
  )
}
