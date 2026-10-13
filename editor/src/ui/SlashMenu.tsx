import { useEffect, useLayoutEffect, useRef, useState } from 'react'

import { BLOCK_GROUPS, type BlockGroup, type BlockType } from '../blocks'
import { t } from '../i18n'
import { BlockPreview } from './BlockPreview'
import { cn } from './cn'
import { GlidingHighlight } from './GlidingHighlight'

type Props = {
  items: BlockType[]
  /** With a query the list is a flat ranking; without, it's grouped like the catalog. */
  query: string
  selectedIndex: number
  onSelect: (index: number) => void
  onHover: (index: number) => void
  onClose: () => void
}

/** Section titles, spelled out so the l10n audit sees every key. */
const GROUP_LABEL: Record<BlockGroup, () => string> = {
  basic: () => t('slash.group.basic'),
  lists: () => t('slash.group.lists'),
  media: () => t('slash.group.media'),
  other: () => t('slash.group.other'),
  advanced: () => t('slash.group.advanced')
}

/** The preview waits this long the first time, then follows the selection instantly. */
const PREVIEW_DELAY_MS = 450
const PREVIEW_WIDTH = 200

/**
 * The "/" block menu (Notion-like): grouped rows with the Markdown shortcut at the end, a "Close menu"
 * footer, and a preview card beside the selected row on wide pointer screens. Opened by typing, so it
 * appears without animation. Selection state and keys live in the caller (SlashCommand).
 */
export function SlashMenu({ items, query, selectedIndex, onSelect, onHover, onClose }: Props) {
  const listRef = useRef<HTMLDivElement>(null)
  const cardRef = useRef<HTMLDivElement>(null)
  const [previewReady, setPreviewReady] = useState(false)
  const [previewTop, setPreviewTop] = useState(0)
  /** Beside the card on the right, or on the left when the right edge is too close. */
  const [previewLeft, setPreviewLeft] = useState(false)
  const selected = items[selectedIndex]

  useEffect(() => {
    const timer = setTimeout(() => setPreviewReady(true), PREVIEW_DELAY_MS)
    return () => clearTimeout(timer)
  }, [])

  // Keep the selected row visible and the preview level with it. `items` is a deliberate dependency: a
  // new result list moves the selected row too.
  /* oxlint-disable react/exhaustive-effect-dependencies */
  useLayoutEffect(() => {
    const row = listRef.current?.querySelector<HTMLElement>(`[data-index="${selectedIndex}"]`)
    row?.scrollIntoView?.({ block: 'nearest' })
    const card = cardRef.current
    if (row && card) {
      const top = row.getBoundingClientRect().top - card.getBoundingClientRect().top
      setPreviewTop(Math.max(0, top - 6))
      setPreviewLeft(card.getBoundingClientRect().right + PREVIEW_WIDTH + 16 > window.innerWidth)
    }
  }, [selectedIndex, items])
  /* oxlint-enable react/exhaustive-effect-dependencies */

  const grouped = !query.trim()
  let index = -1
  const row = (item: BlockType) => {
    index += 1
    const i = index
    const Icon = item.icon
    return (
      <button
        key={item.id}
        type="button"
        role="option"
        aria-selected={i === selectedIndex}
        aria-label={item.label()}
        data-index={i}
        className="relative flex h-8 w-full cursor-pointer items-center gap-2.5 rounded-md px-2 text-left text-sm select-none coarse:h-11"
        // Keep editor focus (and the iOS keyboard) when tapping an item.
        onMouseDown={(e) => e.preventDefault()}
        onMouseMove={() => i !== selectedIndex && onHover(i)}
        onClick={() => onSelect(i)}
      >
        <Icon size={18} className="flex-none text-subtle-foreground" aria-hidden />
        <span className="min-w-0 flex-1 truncate text-foreground">{item.label()}</span>
        {item.shortcut && (
          <span className="flex-none font-mono text-xs text-placeholder">{item.shortcut}</span>
        )}
      </button>
    )
  }

  return (
    <div className="relative" data-testid="slash-menu">
      <div
        ref={cardRef}
        className="flex w-[280px] max-w-[calc(100vw-16px)] flex-col overflow-hidden rounded-xl bg-popover text-popover-foreground shadow-popover"
        style={{ maxHeight: 'var(--hk-available-height, 360px)' }}
      >
        <div
          ref={listRef}
          role="listbox"
          className="relative min-h-0 flex-1 overflow-y-auto overscroll-contain p-1"
        >
          <GlidingHighlight listRef={listRef} index={selectedIndex} />
          {items.length === 0 ? (
            <div className="px-2 py-1.5 text-sm text-muted-foreground">{t('editor.noResults')}</div>
          ) : grouped ? (
            BLOCK_GROUPS.map((group) => {
              const members = items.filter((item) => item.group === group)
              if (members.length === 0) return null
              return (
                <div key={group} role="group" aria-label={GROUP_LABEL[group]()}>
                  <div className="px-2 pt-2 pb-1 text-xs font-medium text-muted-foreground">
                    {GROUP_LABEL[group]()}
                  </div>
                  {members.map(row)}
                </div>
              )
            })
          ) : (
            items.map(row)
          )}
        </div>
        <button
          type="button"
          className="flex h-9 flex-none cursor-pointer items-center justify-between border-t border-border px-3 text-sm text-muted-foreground transition-colors duration-(--motion-pop-out) ease-out hover:bg-accent coarse:hidden"
          onMouseDown={(e) => e.preventDefault()}
          onClick={onClose}
        >
          <span>{t('slash.close')}</span>
          <span className="text-xs text-placeholder">esc</span>
        </button>
      </div>
      {selected && previewReady && (
        <div
          className={cn(
            'hk-pop pointer-events-none absolute rounded-lg bg-popover p-2 shadow-popover max-md:hidden coarse:hidden',
            previewLeft ? 'right-full mr-2' : 'left-full ml-2'
          )}
          style={{ top: previewTop, width: PREVIEW_WIDTH }}
          data-testid="slash-preview"
          aria-hidden
        >
          <div className="rounded-md border border-border bg-background px-3 py-2.5">
            <BlockPreview id={selected.id} />
          </div>
          <p className="mt-2 px-0.5 text-xs leading-snug text-muted-foreground">
            {selected.description()}
          </p>
        </div>
      )}
    </div>
  )
}
