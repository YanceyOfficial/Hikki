import { cn } from 'cn'
import { useState } from 'react'
import type { Root } from 'react-dom/client'

import { Button } from '@/components/ui/button'
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover'

import { t } from '../core/i18n'
import { DEFAULT_CALLOUT_ICON } from '../extensions/callout'
import { colorLabel, PALETTE, type PaletteColor } from '../extensions/colors'
import { useMediaQuery } from '../hooks/use-media-query'
import { TOUCH } from '../lib/device'
import { BottomSheet } from './bottom-sheet'
import { EmojiPickerPanel } from './emoji-picker-panel'
import { IconProvider } from './icons'

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
  const touch = useMediaQuery(TOUCH)
  const glyph = <span className="text-lg leading-none">{icon || DEFAULT_CALLOUT_ICON}</span>
  if (!editable) return <span className="grid size-7 place-items-center">{glyph}</span>
  const picker = (
    <>
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
          <Button
            key={swatch ?? 'default'}
            variant="ghost"
            role="radio"
            aria-checked={color === swatch}
            aria-label={colorLabel(swatch)}
            className={cn(
              'size-5 cursor-pointer rounded-full p-0',
              color === swatch && 'ring-2 ring-ring'
            )}
            onClick={() => onColor(swatch)}
          >
            {/* The tint on its own surface: the button's hover never paints over it. */}
            <span
              className="size-full rounded-full border border-border"
              data-bg-color={swatch ?? 'gray'}
            />
          </Button>
        ))}
      </div>
    </>
  )
  const trigger = (
    <Button
      variant="ghost"
      className="size-7 cursor-pointer rounded-md p-0 hover:bg-foreground/5 dark:hover:bg-foreground/5"
      aria-label={t('callout.icon')}
    />
  )
  // A touch screen: the picker is a bottom sheet the screen's width, as the page icon's.
  if (touch)
    return (
      <>
        <Button
          variant="ghost"
          className="size-7 cursor-pointer rounded-md p-0 hover:bg-foreground/5 dark:hover:bg-foreground/5"
          aria-label={t('callout.icon')}
          onClick={() => setOpen(true)}
        >
          {glyph}
        </Button>
        <BottomSheet open={open} onClose={() => setOpen(false)} title={t('callout.icon')}>
          {picker}
        </BottomSheet>
      </>
    )
  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger render={trigger}>{glyph}</PopoverTrigger>
      <PopoverContent align="start" className="w-[400px] max-w-[calc(100vw-16px)] gap-0 p-0">
        {picker}
      </PopoverContent>
    </Popover>
  )
}

/** Draws the icon into the callout node view's React root (the extension holds no JSX). */
export function renderCalloutIcon(root: Root, props: Props): void {
  root.render(
    <IconProvider>
      <CalloutIcon {...props} />
    </IconProvider>
  )
}
