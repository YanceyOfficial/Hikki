import { useState } from 'react'

import { t } from '../i18n'

type Props = {
  base: string
  /** The reading the ruby already has ('' for a new one). */
  initial: string
  /** The host's suggestion for a new ruby, once it arrives (openRubyPanel re-renders with it). */
  suggestion: string | null
  suggesting: boolean
  canRemove: boolean
  onDone: (reading: string) => void
  onRemove: () => void
  onCancel: () => void
}

/**
 * The furigana field: the base text above, the reading typed below (Enter saves, Esc cancels). What the field
 * shows is derived — what was typed, else the existing reading, else the suggestion — so a suggestion arriving
 * late fills an untouched field without touching a typed one.
 */
export function RubyPanel({
  base,
  initial,
  suggestion,
  suggesting,
  canRemove,
  onDone,
  onRemove,
  onCancel
}: Props) {
  const [typed, setTyped] = useState<string | null>(null)
  const reading = typed ?? (initial || suggestion || '')

  return (
    <div className="flex flex-col gap-2" data-testid="ruby-panel">
      <div className="truncate px-0.5 text-xs text-muted-foreground">
        {t('ruby.baseLabel')} <span className="text-foreground">{base}</span>
      </div>
      <input
        // oxlint-disable-next-line jsx-a11y/no-autofocus -- the panel exists to type the reading
        autoFocus
        className="h-8 w-full rounded-md border border-input bg-transparent px-2 text-sm outline-none placeholder:text-placeholder focus:border-ring focus:ring-3 focus:ring-ring/50"
        placeholder={suggesting ? t('ruby.suggesting') : t('ruby.placeholder')}
        aria-label={t('ruby.label')}
        lang="ja"
        value={reading}
        onChange={(e) => setTyped(e.target.value)}
        onKeyDown={(e) => {
          if (e.nativeEvent.isComposing) return
          if (e.key === 'Enter') {
            e.preventDefault()
            onDone(reading)
          } else if (e.key === 'Escape') {
            e.preventDefault()
            onCancel()
          }
        }}
      />
      <div className="flex items-center justify-between">
        <span className="text-xs text-muted-foreground">{t('ruby.hint')}</span>
        <div className="flex gap-1">
          {canRemove && (
            <button
              type="button"
              className="inline-flex h-7 cursor-pointer items-center rounded-md px-2 text-xs text-destructive hover:bg-accent"
              onClick={onRemove}
            >
              {t('ruby.remove')}
            </button>
          )}
          <button
            type="button"
            className="inline-flex h-7 cursor-pointer items-center rounded-md bg-primary px-2.5 text-xs text-primary-foreground"
            onClick={() => onDone(reading)}
          >
            {t('ruby.done')}
          </button>
        </div>
      </div>
    </div>
  )
}
