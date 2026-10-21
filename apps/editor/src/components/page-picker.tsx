import { useRef, useState } from 'react'

import { Input } from '@/components/ui/input'

import { t } from '../core/i18n'
import type { PageIndexEntry } from '../extensions/page-links'
import { pageMentionItems } from '../extensions/page-mention'
import { GlidingHighlight } from './gliding-highlight'
import { MenuRow, MenuTitle } from './menu-row'

/** A page to send something to (the block menu's Move to): a search over the sidebar's pages, best matches first. */
export function PagePicker({
  title,
  pages,
  onPick
}: {
  title: string
  pages: PageIndexEntry[]
  onPick: (page: PageIndexEntry) => void
}) {
  const [query, setQuery] = useState('')
  const [selected, setSelected] = useState(0)
  const listRef = useRef<HTMLDivElement>(null)
  const untitled = t('page.untitled')
  const shown = pageMentionItems(pages, query, untitled)
  return (
    <div
      onKeyDown={(e) => {
        if (e.nativeEvent.isComposing) return
        if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
          e.preventDefault()
          const step = e.key === 'ArrowDown' ? 1 : -1
          setSelected((i) => (i + step + shown.length) % Math.max(1, shown.length))
        } else if (e.key === 'Enter' && shown[selected]) {
          e.preventDefault()
          onPick(shown[selected])
        }
      }}
    >
      <MenuTitle>{title}</MenuTitle>
      <Input
        className="m-1 mb-1.5 h-8 w-auto md:text-sm"
        placeholder={t('blockMenu.searchPages')}
        aria-label={t('blockMenu.searchPages')}
        data-testid="page-picker-search"
        value={query}
        onChange={(e) => {
          setQuery(e.target.value)
          setSelected(0)
        }}
      />
      <div ref={listRef} role="listbox" aria-label={title} className="relative">
        <GlidingHighlight listRef={listRef} index={selected} />
        {shown.length === 0 && (
          <div className="px-2 py-1.5 text-sm text-muted-foreground">{t('editor.noResults')}</div>
        )}
        {shown.map((page, i) => (
          <MenuRow
            key={page.id}
            glide
            role="option"
            aria-selected={i === selected}
            data-index={i}
            data-testid={`page-picker-${page.id}`}
            onMouseMove={() => setSelected(i)}
            onClick={() => onPick(page)}
          >
            <span aria-hidden className="w-5 text-center">
              {page.icon ?? '📄'}
            </span>
            <span className="flex-1 truncate">{page.title || untitled}</span>
          </MenuRow>
        ))}
      </div>
    </div>
  )
}
