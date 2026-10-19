import { useState } from 'react'

import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'

import { t } from '../core/i18n'
import type { FloatingAnchor, FloatingLayer } from './floating'

type Props = {
  initial: string
  /** The caption typed (empty: none). */
  onSave: (caption: string) => void
}

/** Where an embed's caption is written: Return saves; Escape is the layers' bus (it cancels). */
export function CaptionPanel({ initial, onSave }: Props) {
  const [value, setValue] = useState(initial)
  return (
    <div className="flex items-center gap-2" data-testid="caption-panel">
      <Input
        // oxlint-disable-next-line jsx-a11y/no-autofocus -- the panel opens to type the caption
        autoFocus
        className="h-8 text-sm md:text-sm"
        placeholder={t('blockMenu.captionPlaceholder')}
        aria-label={t('blockMenu.caption')}
        value={value}
        onChange={(e) => setValue(e.target.value)}
        onKeyDown={(e) => {
          if (e.nativeEvent.isComposing) return
          if (e.key === 'Enter') {
            e.preventDefault()
            onSave(value)
          }
        }}
      />
      <Button size="xs" onClick={() => onSave(value)}>
        {t('blockMenu.captionSave')}
      </Button>
    </div>
  )
}

/** Shows the panel in its floating layer under the block (the extension holds no JSX). */
export function renderCaptionPanel(
  layer: FloatingLayer,
  props: Props,
  anchor: FloatingAnchor
): void {
  layer.render(<CaptionPanel {...props} />, anchor)
}
