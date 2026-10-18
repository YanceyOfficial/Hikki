import { CheckIcon } from '@phosphor-icons/react'
import type { ReactNode } from 'react'

import { t } from '../core/i18n'
import { colorLabel, PALETTE, type PaletteColor } from '../extensions/colors'
import { MenuRow, MenuTitle } from './menu-row'

/** The "A" swatch in a text and background colour (`data-*-color`, styled from the `ink-*` / `wash-*` tokens). */
export function ColorSwatch({
  text,
  background
}: {
  text: PaletteColor | null
  background: PaletteColor | null
}) {
  return (
    <span
      className="grid size-5 place-items-center rounded-[5px] border border-border text-xs font-semibold"
      data-text-color={text ?? undefined}
      data-bg-color={background ?? undefined}
    >
      A
    </span>
  )
}

/**
 * Text colours, then background colours, the current ones checked. `kind`: a selection's colours are marks
 * (an "A" on the tint); a block's background is the block's own tint (`data-block-bg`).
 */
export function ColorList({
  kind,
  text,
  background,
  onText,
  onBackground
}: {
  kind: 'mark' | 'block'
  text: PaletteColor | null
  background: PaletteColor | null
  onText: (color: PaletteColor | null) => void
  onBackground: (color: PaletteColor | null) => void
}) {
  return (
    <>
      <MenuTitle>{t('color.text')}</MenuTitle>
      {[null, ...PALETTE].map((color) => (
        <ColorRow
          key={`text-${color}`}
          color={color}
          checked={text === color}
          onPick={() => onText(color)}
        >
          <ColorSwatch text={color} background={null} />
        </ColorRow>
      ))}
      <div className="mx-1 my-1 h-px bg-border" />
      <MenuTitle>{t('color.background')}</MenuTitle>
      {[null, ...PALETTE].map((color) => (
        <ColorRow
          key={`bg-${color}`}
          color={color}
          checked={background === color}
          onPick={() => onBackground(color)}
        >
          {kind === 'mark' ? (
            <ColorSwatch text={null} background={color} />
          ) : (
            <span
              className="size-5 rounded-[5px] border border-border"
              data-block-bg={color ?? undefined}
            />
          )}
        </ColorRow>
      ))}
    </>
  )
}

function ColorRow({
  color,
  checked,
  onPick,
  children
}: {
  color: PaletteColor | null
  checked: boolean
  onPick: () => void
  children: ReactNode
}) {
  return (
    <MenuRow role="menuitemradio" aria-checked={checked} onClick={onPick}>
      {children}
      <span className="flex-1 truncate">{colorLabel(color)}</span>
      {checked && <CheckIcon size={14} aria-hidden />}
    </MenuRow>
  )
}
