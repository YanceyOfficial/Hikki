import { useEffect, useMemo, useRef, useState } from 'react'
import { loadEmojiCategories, recentEmoji, rememberEmoji, searchEmoji, type EmojiCategory } from './emoji-data'

type Props = {
  onSelect: (emoji: string) => void
  onRemove?: () => void
  onRandom?: () => void
  locale?: 'en' | 'zh'
}

const text = {
  en: { search: 'Search emoji…', remove: 'Remove', random: 'Random', recent: 'Recent', empty: 'No emoji found', loading: 'Loading…', failed: 'Could not load emoji' },
  zh: { search: '搜索表情…', remove: '移除', random: '随机', recent: '最近使用', empty: '没有找到', loading: '加载中…', failed: '表情加载失败' },
}

/**
 * Offline emoji picker. A plain CSS grid that always fills the panel width (no virtualized rows to
 * drift out of sync with the layout), sticky category headers and a category jump bar.
 * Reusable for page icons, callouts and reactions.
 */
export function EmojiPickerPanel({ onSelect, onRemove, onRandom, locale = preferredLocale() }: Props) {
  const t = text[locale]
  const [categories, setCategories] = useState<EmojiCategory[] | null>(null)
  const [failed, setFailed] = useState(false)
  const [query, setQuery] = useState('')
  const [recent] = useState(recentEmoji)
  const scroller = useRef<HTMLDivElement>(null)

  useEffect(() => {
    let alive = true
    loadEmojiCategories(locale).then((c) => alive && setCategories(c), (error) => {
      console.error('[hikki] emoji data failed to load', error)
      if (alive) setFailed(true)
    })
    return () => { alive = false }
  }, [locale])

  const results = useMemo(() => (categories && query ? searchEmoji(categories, query) : null), [categories, query])

  const choose = (emoji: string) => {
    rememberEmoji(emoji)
    onSelect(emoji)
  }

  const jump = (key: string) => {
    const header = scroller.current?.querySelector<HTMLElement>(`[data-category="${key}"]`)
    if (header && scroller.current) scroller.current.scrollTop = header.offsetTop - 4
  }

  return (
    <div className="hk-emoji-panel">
      <div className="hk-emoji-toolbar">
        <input
          className="hk-input"
          type="search"
          placeholder={t.search}
          value={query}
          autoFocus={!isTouch()}
          onChange={(e) => setQuery(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter' && results?.[0]) choose(results[0].emoji)
          }}
          aria-label={t.search}
        />
        {onRandom && <button type="button" className="hk-button" onClick={onRandom} title={t.random} aria-label={t.random}>🎲</button>}
        {onRemove && <button type="button" className="hk-button" onClick={onRemove}>{t.remove}</button>}
      </div>

      {categories && !query && (
        <div className="hk-emoji-jump" role="tablist">
          {categories.map((c) => (
            <button key={c.key} type="button" role="tab" title={c.label} aria-label={c.label} onClick={() => jump(c.key)}>
              {c.emojis[0]?.emoji}
            </button>
          ))}
        </div>
      )}

      <div className="hk-emoji-scroll" ref={scroller}>
        {failed && <div className="hk-emoji-status">{t.failed}</div>}
        {!categories && !failed && <div className="hk-emoji-status">{t.loading}</div>}
        {results && (results.length ? <EmojiGrid emojis={results} onPick={choose} /> : <div className="hk-emoji-status">{t.empty}</div>)}
        {categories && !query && (
          <>
            {recent.length > 0 && (
              <section>
                <h3 className="hk-emoji-category">{t.recent}</h3>
                <EmojiGrid emojis={recent.map((emoji) => ({ emoji, label: emoji }))} onPick={choose} />
              </section>
            )}
            {categories.map((c) => (
              <section key={c.key} className="hk-emoji-section">
                <h3 className="hk-emoji-category" data-category={c.key}>{c.label}</h3>
                <EmojiGrid emojis={c.emojis} onPick={choose} />
              </section>
            ))}
          </>
        )}
      </div>
    </div>
  )
}

function EmojiGrid({ emojis, onPick }: { emojis: { emoji: string; label: string }[]; onPick: (emoji: string) => void }) {
  return (
    <div className="hk-emoji-grid">
      {emojis.map((e) => (
        <button key={e.emoji} type="button" className="hk-emoji" title={e.label} aria-label={e.label} onClick={() => onPick(e.emoji)}>
          {e.emoji}
        </button>
      ))}
    </div>
  )
}

function preferredLocale(): 'en' | 'zh' {
  return navigator.language.toLowerCase().startsWith('zh') ? 'zh' : 'en'
}

function isTouch(): boolean {
  return matchMedia?.('(pointer: coarse)').matches ?? false
}
