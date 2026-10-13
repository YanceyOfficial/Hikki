import { useState } from 'react'

import { wholeReading, type RubySegment } from '../extensions/ruby'
import { t } from '../i18n'
import { cn } from './cn'

type Props = {
  base: string
  /** The reading the ruby already has ('' for a new one). */
  initial: string
  /** The host's suggestion for a new ruby, once it arrives: kanji runs with readings, kana bare. */
  segments: RubySegment[] | null
  suggesting: boolean
  canRemove: boolean
  onDone: (reading: string) => void
  onDoneSegments: (segments: RubySegment[]) => void
  onRemove: () => void
  onCancel: () => void
}

const field =
  'h-8 min-w-0 flex-1 rounded-md border border-input bg-transparent px-2 text-sm outline-none placeholder:text-placeholder focus:border-ring focus:ring-3 focus:ring-ring/50'

/**
 * The furigana fields (Enter saves, Esc cancels). A phrase with several kanji runs gets one field per run
 * (役 → やく, 立 → た), with a switch to one reading over the whole phrase. What a field shows is derived —
 * what was typed, else the existing reading, else the suggestion — so a suggestion arriving late fills
 * untouched fields without touching typed ones.
 */
export function RubyPanel({
  base,
  initial,
  segments,
  suggesting,
  canRemove,
  onDone,
  onDoneSegments,
  onRemove,
  onCancel
}: Props) {
  const [typed, setTyped] = useState<Record<string, string>>({})
  const [wholeChosen, setWholeChosen] = useState(false)
  const kanjiRuns = segments?.filter((s) => s.reading !== undefined) ?? []
  const perKanji = !initial && kanjiRuns.length > 0 && segments!.length > 1 && !wholeChosen
  const whole = typed.whole ?? (initial || (segments ? wholeReading(segments) : ''))

  const keys = (e: React.KeyboardEvent, save: () => void) => {
    if (e.nativeEvent.isComposing) return
    if (e.key === 'Enter') {
      e.preventDefault()
      save()
    } else if (e.key === 'Escape') {
      e.preventDefault()
      onCancel()
    }
  }
  const saveSegments = () =>
    onDoneSegments(
      segments!.map((s, i) =>
        s.reading === undefined ? s : { ...s, reading: typed[String(i)] ?? s.reading }
      )
    )

  return (
    <div className="flex flex-col gap-2" data-testid="ruby-panel">
      <div className="flex items-center gap-2">
        <div className="min-w-0 flex-1 truncate px-0.5 text-xs text-muted-foreground">
          {t('ruby.baseLabel')} <span className="text-foreground">{base}</span>
        </div>
        {kanjiRuns.length > 0 && segments!.length > 1 && !initial && (
          <div
            className="flex rounded-md bg-muted p-0.5 text-xs"
            role="radiogroup"
            aria-label={t('ruby.mode')}
          >
            {(['perKanji', 'whole'] as const).map((mode) => {
              const active = mode === 'perKanji' ? perKanji : !perKanji
              return (
                <button
                  key={mode}
                  type="button"
                  role="radio"
                  aria-checked={active}
                  className={cn(
                    'cursor-pointer rounded-[5px] px-2 py-0.5',
                    active && 'bg-background shadow-xs'
                  )}
                  onClick={() => setWholeChosen(mode === 'whole')}
                >
                  {mode === 'perKanji' ? t('ruby.perKanji') : t('ruby.whole')}
                </button>
              )
            })}
          </div>
        )}
      </div>
      {perKanji ? (
        <div className="flex flex-col gap-1.5">
          {segments!.map((segment, i) =>
            segment.reading === undefined ? null : (
              <label key={i} className="flex items-center gap-2 text-sm">
                <span className="w-16 shrink-0 truncate text-right">{segment.text}</span>
                <input
                  // oxlint-disable-next-line jsx-a11y/no-autofocus -- the first field takes the caret
                  autoFocus={i === segments!.findIndex((s) => s.reading !== undefined)}
                  className={field}
                  lang="ja"
                  aria-label={t('ruby.readingFor', { text: segment.text })}
                  value={typed[String(i)] ?? segment.reading}
                  onChange={(e) =>
                    setTyped((current) => ({ ...current, [String(i)]: e.target.value }))
                  }
                  onKeyDown={(e) => keys(e, saveSegments)}
                />
              </label>
            )
          )}
        </div>
      ) : (
        <input
          // oxlint-disable-next-line jsx-a11y/no-autofocus -- the panel exists to type the reading
          autoFocus
          className={field}
          placeholder={suggesting ? t('ruby.suggesting') : t('ruby.placeholder')}
          aria-label={t('ruby.label')}
          lang="ja"
          value={whole}
          onChange={(e) => setTyped((current) => ({ ...current, whole: e.target.value }))}
          onKeyDown={(e) => keys(e, () => onDone(whole))}
        />
      )}
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
            onClick={() => (perKanji ? saveSegments() : onDone(whole))}
          >
            {t('ruby.done')}
          </button>
        </div>
      </div>
    </div>
  )
}
