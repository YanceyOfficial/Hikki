import { useState } from 'react'

import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover'
import { cn } from '@/lib/utils'

import { DEFAULT_CALLOUT_ICON } from '../extensions/callout'
import { colorLabel, PALETTE, type PaletteColor } from '../extensions/colors'
import { t } from '../i18n'
import { EmojiPickerPanel } from './emoji-picker-panel'

type Props = {
  icon: string
  color: PaletteColor | null
  editable: boolean
  onIcon: (icon: string) => void
  onColor: (color: PaletteColor | null) => void
}

/** The callout's emoji: a button opening the emoji picker, with the callout's background colors below. */
export function CalloutIcon({ icon, color, editable, onIcon, onColor }: Props) {
  const [open, setOpen] = useState(false)
  const glyph = <span className="text-lg leading-none">{icon || DEFAULT_CALLOUT_ICON}</span>
  if (!editable) return <span className="grid size-7 place-items-center">{glyph}</span>
  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger
        render={
          <button
            type="button"
            className="grid size-7 cursor-pointer place-items-center rounded-md hover:bg-foreground/5"
            aria-label={t('callout.icon')}
          />
        }
      >
        {glyph}
      </PopoverTrigger>
      <PopoverContent align="start" className="w-[400px] max-w-[calc(100vw-16px)] gap-0 p-0">
        <EmojiPickerPanel
          onSelect={(emoji) => {
            onIcon(emoji)
            setOpen(false)
          }}
        />
        <div
          className="flex items-center gap-1.5 border-t border-border px-3 py-2"
          role="radiogroup"
          aria-label={t('callout.color')}
        >
          {[null, ...PALETTE].map((swatch) => (
            <button
              key={swatch ?? 'default'}
              type="button"
              role="radio"
              aria-checked={color === swatch}
              aria-label={colorLabel(swatch)}
              data-bg-color={swatch ?? 'gray'}
              className={cn(
                'size-5 cursor-pointer rounded-full border border-border',
                color === swatch && 'ring-2 ring-ring'
              )}
              onClick={() => onColor(swatch)}
            />
          ))}
        </div>
      </PopoverContent>
    </Popover>
  )
}
