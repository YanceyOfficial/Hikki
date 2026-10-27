import { useState } from 'react'

import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs'

import { t } from '../core/i18n'
import { keyLabel } from '../core/shortcuts'
import { wholeReading, type RubySegment } from '../extensions/ruby'
import { isImeKey } from '../lib/ime'
import type { FloatingAnchor, FloatingLayer } from './floating'
import { IconProvider } from './icons'

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
}

/** Enter saves; Escape is the layers' bus (onDismiss cancels), it never reaches the fields. */
function keys(e: React.KeyboardEvent, save: () => void) {
  if (isImeKey(e.nativeEvent)) return
  if (e.key === 'Enter') {
    e.preventDefault()
    save()
  }
}

/** The panel's fields are a size smaller than the default form control. */
const field = 'h-8 text-sm md:text-sm'

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
  onRemove
}: Props) {
  const [typed, setTyped] = useState<Record<string, string>>({})
  const [wholeChosen, setWholeChosen] = useState(false)
  const kanjiRuns = segments?.filter((s) => s.reading !== undefined) ?? []
  const segmented = kanjiRuns.length > 0 && segments!.length > 1 && !initial
  const perKanji = segmented && !wholeChosen
  const whole = typed.whole ?? (initial || (segments ? wholeReading(segments) : ''))

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
        {segmented && (
          <Tabs
            value={perKanji ? 'perKanji' : 'whole'}
            onValueChange={(mode) => setWholeChosen(mode === 'whole')}
          >
            <TabsList className="h-7" aria-label={t('ruby.mode')}>
              <TabsTrigger value="perKanji" className="h-6 px-2 text-xs">
                {t('ruby.perKanji')}
              </TabsTrigger>
              <TabsTrigger value="whole" className="h-6 px-2 text-xs">
                {t('ruby.whole')}
              </TabsTrigger>
            </TabsList>
          </Tabs>
        )}
      </div>
      {perKanji ? (
        <div className="flex flex-col gap-1.5">
          {segments!.map((segment, i) =>
            segment.reading === undefined ? null : (
              <label key={i} className="flex items-center gap-2 text-sm">
                <span className="w-16 shrink-0 truncate text-right">{segment.text}</span>
                <Input
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
        <Input
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
        <span className="text-xs text-muted-foreground">
          {t('ruby.hint', { confirm: keyLabel('return'), cancel: keyLabel('escape') })}
        </span>
        <div className="flex gap-1">
          {canRemove && (
            <Button variant="ghost" size="xs" className="text-destructive" onClick={onRemove}>
              {t('ruby.remove')}
            </Button>
          )}
          <Button size="xs" onClick={() => (perKanji ? saveSegments() : onDone(whole))}>
            {t('ruby.done')}
          </Button>
        </div>
      </div>
    </div>
  )
}

/** Shows the panel in its floating layer under the selection (the extension holds no JSX). */
export function renderRubyPanel(layer: FloatingLayer, props: Props, anchor: FloatingAnchor): void {
  layer.render(
    <IconProvider>
      <RubyPanel {...props} />
    </IconProvider>,
    anchor
  )
}
