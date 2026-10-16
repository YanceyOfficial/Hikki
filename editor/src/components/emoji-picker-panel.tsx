import { ShuffleIcon } from '@phosphor-icons/react'
import { cn } from 'cn'
import { useEffect, useMemo, useRef, useState } from 'react'
import { useTranslation } from 'react-i18next'

import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'

import {
  loadEmojiCategories,
  recentEmoji,
  rememberEmoji,
  searchEmoji,
  type EmojiCategory
} from '../lib/emoji-data'

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
        <Input
          className="h-8 md:text-sm"
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
          <Button
            variant="ghost"
            size="icon-sm"
            onClick={onRandom}
            title={text.random}
            aria-label={text.random}
          >
            <ShuffleIcon size={16} aria-hidden />
          </Button>
        )}
        {onRemove && (
          <Button variant="ghost" size="sm" onClick={onRemove}>
            {text.remove}
          </Button>
        )}
      </div>

      {categories && !query && (
        <div className="flex justify-between border-b border-border px-2.5 pb-1.5" role="tablist">
          {categories.map((c) => (
            <Button
              key={c.key}
              variant="ghost"
              role="tab"
              className="h-6.5 w-7 cursor-pointer rounded-md p-0 font-emoji text-sm font-normal opacity-70 grayscale hover:bg-accent hover:opacity-100 hover:grayscale-0 dark:hover:bg-accent"
              title={c.label}
              aria-label={c.label}
              onClick={() => jump(c.key)}
            >
              {c.emojis[0]?.emoji}
            </Button>
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
        // One cell per emoji, about 1,900 of them: a plain button each (a Base UI Button per cell is hooks × 1,900
        // on every open); the look is the ghost Button's.
        <button // design-lint: allow
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
