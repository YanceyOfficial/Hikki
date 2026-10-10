import { Shuffle } from '@phosphor-icons/react'
import { useEffect, useMemo, useRef, useState } from 'react'
import { useTranslation } from 'react-i18next'

import { cn, ui } from './cn'
import {
  loadEmojiCategories,
  recentEmoji,
  rememberEmoji,
  searchEmoji,
  type EmojiCategory
} from './emoji-data'

type Props = {
  onSelect: (emoji: string) => void
  onRemove?: () => void
  onRandom?: () => void
  locale?: 'en' | 'zh'
}

/**
 * Offline emoji picker. A plain CSS grid that always fills the panel width (no virtualized rows to
 * drift out of sync with the layout), sticky category headers and a category jump bar.
 * Reusable for page icons, callouts and reactions.
 */
export function EmojiPickerPanel({ onSelect, onRemove, onRandom, locale: localeProp }: Props) {
  const { t, i18n } = useTranslation()
  // Emoji names/keywords follow the UI language.
  const locale = localeProp ?? (i18n.language.startsWith('zh') ? 'zh' : 'en')
  const text = {
    search: t('emoji.search'),
    remove: t('emoji.remove'),
    random: t('emoji.random'),
    recent: t('emoji.recent'),
    empty: t('emoji.empty'),
    loading: t('emoji.loading'),
    failed: t('emoji.failed')
  }
  const [categories, setCategories] = useState<EmojiCategory[] | null>(null)
  const [failed, setFailed] = useState(false)
  const [query, setQuery] = useState('')
  const [recent] = useState(recentEmoji)
  const scroller = useRef<HTMLDivElement>(null)

  useEffect(() => {
    let alive = true
    loadEmojiCategories(locale).then(
      (c) => alive && setCategories(c),
      (error) => {
        console.error('[hikki] emoji data failed to load', error)
        if (alive) setFailed(true)
      }
    )
    return () => {
      alive = false
    }
  }, [locale])

  const results = useMemo(
    () => (categories && query ? searchEmoji(categories, query) : null),
    [categories, query]
  )

  const choose = (emoji: string) => {
    rememberEmoji(emoji)
    onSelect(emoji)
  }

  const jump = (key: string) => {
    const header = scroller.current?.querySelector<HTMLElement>(`[data-category="${key}"]`)
    if (header && scroller.current) scroller.current.scrollTop = header.offsetTop - 4
  }

  return (
    <div className="flex h-[380px] max-h-[inherit] flex-col">
      <div className="flex gap-1 px-2.5 pt-2.5 pb-1.5">
        <input
          className={ui.input}
          type="search"
          placeholder={text.search}
          value={query}
          autoFocus={!isTouch()}
          onChange={(e) => setQuery(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter' && results?.[0]) choose(results[0].emoji)
          }}
          aria-label={text.search}
        />
        {onRandom && (
          <button
            type="button"
            className={ui.button}
            onClick={onRandom}
            title={text.random}
            aria-label={text.random}
          >
            <Shuffle size={16} aria-hidden />
          </button>
        )}
        {onRemove && (
          <button type="button" className={ui.button} onClick={onRemove}>
            {text.remove}
          </button>
        )}
      </div>

      {categories && !query && (
        <div className="flex justify-between border-b border-border px-2.5 pb-1.5" role="tablist">
          {categories.map((c) => (
            <button
              key={c.key}
              type="button"
              role="tab"
              className="grid h-6.5 w-7 cursor-pointer place-items-center rounded-md font-emoji text-sm opacity-70 grayscale hover:bg-accent hover:opacity-100 hover:grayscale-0"
              title={c.label}
              aria-label={c.label}
              onClick={() => jump(c.key)}
            >
              {c.emojis[0]?.emoji}
            </button>
          ))}
        </div>
      )}

      <div
        className="relative flex-1 overflow-y-auto overscroll-contain px-2.5 pb-2.5"
        ref={scroller}
      >
        {failed && <Status>{text.failed}</Status>}
        {!categories && !failed && <Status>{text.loading}</Status>}
        {results &&
          (results.length ? (
            <EmojiGrid emojis={results} onPick={choose} />
          ) : (
            <Status>{text.empty}</Status>
          ))}
        {categories && !query && (
          <>
            {recent.length > 0 && (
              <section>
                <CategoryTitle>{text.recent}</CategoryTitle>
                <EmojiGrid
                  emojis={recent.map((emoji) => ({ emoji, label: emoji }))}
                  onPick={choose}
                />
              </section>
            )}
            {categories.map((c) => (
              <section
                key={c.key}
                className="[contain-intrinsic-size:auto_400px] [content-visibility:auto]"
              >
                <CategoryTitle category={c.key}>{c.label}</CategoryTitle>
                <EmojiGrid emojis={c.emojis} onPick={choose} />
              </section>
            ))}
          </>
        )}
      </div>
    </div>
  )
}

function EmojiGrid({
  emojis,
  onPick
}: {
  emojis: { emoji: string; label: string }[]
  onPick: (emoji: string) => void
}) {
  return (
    <div className="grid grid-cols-[repeat(auto-fill,minmax(34px,1fr))]">
      {emojis.map((e) => (
        <button
          key={e.emoji}
          type="button"
          className="hk-emoji grid aspect-square cursor-pointer place-items-center rounded-md font-emoji text-2xl leading-none hover:bg-accent focus-visible:bg-accent focus-visible:outline-none"
          title={e.label}
          aria-label={e.label}
          onClick={() => onPick(e.emoji)}
        >
          {e.emoji}
        </button>
      ))}
    </div>
  )
}

function CategoryTitle({ category, children }: { category?: string; children: string }) {
  return (
    <h3
      className={cn(
        'sticky top-0 z-10 m-0 bg-popover px-0.5 pb-1.5 pt-2.5 text-xs font-medium text-muted-foreground'
      )}
      data-category={category}
    >
      {children}
    </h3>
  )
}

function Status({ children }: { children: string }) {
  return <div className="p-7 text-center text-md text-muted-foreground">{children}</div>
}

function isTouch(): boolean {
  return matchMedia?.('(pointer: coarse)').matches ?? false
}
