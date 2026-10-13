import { useState, useSyncExternalStore } from 'react'
import { useTranslation } from 'react-i18next'

import type { EditorBridge } from '../bridge'
import { cn } from '../ui/cn'

/** The closed rail never shows more bars than this (Notion's stays a loose stack on long pages too). */
const MAX_BARS = 20

/** Up to `limit` items spread evenly over the list (first and last kept), the whole list when it fits. */
export function sampleEvenly<T>(items: T[], limit: number): T[] {
  if (items.length <= limit) return items
  if (limit <= 1) return [items[0]]
  const step = (items.length - 1) / (limit - 1)
  return Array.from({ length: limit }, (_, i) => items[Math.round(i * step)])
}

/**
 * Notion-style outline on the right edge: a stack of short bars (one per heading, indented by level)
 * that expands into a clickable table of contents on hover/focus. Hidden for fewer than two headings.
 */
export function Outline({ bridge }: { bridge: EditorBridge }) {
  const { t } = useTranslation()
  const { headings } = useSyncExternalStore(bridge.page.subscribe, bridge.page.get)
  const [open, setOpen] = useState(false)
  if (headings.length < 2) return null
  const minLevel = Math.min(...headings.map((h) => h.level))
  // Long pages have dozens of headings; the closed rail shows a sample of them, not a solid bar.
  const bars = sampleEvenly(headings, MAX_BARS)

  return (
    <nav
      className="fixed top-1/2 right-4 z-20 flex -translate-y-1/2 justify-end max-[1000px]:hidden"
      aria-label={t('page.outline')}
      onMouseEnter={() => setOpen(true)}
      onMouseLeave={() => setOpen(false)}
      onFocus={() => setOpen(true)}
      onBlur={(e) => {
        if (!e.currentTarget.contains(e.relatedTarget as Node)) setOpen(false)
      }}
    >
      {/* The rail keeps its size while the list is open: the nav is vertically centred, so swapping the
          bars for the (taller) list would move the nav under the pointer and flip it closed again. */}
      <div
        className={cn(
          'flex flex-col items-end gap-2.5 px-1 py-2 transition-opacity duration-(--motion-pop-in) ease-out',
          open && 'opacity-0'
        )}
        aria-hidden
      >
        {bars.map((h) => (
          <span
            key={h.pos}
            className="h-0.5 rounded-full bg-muted-foreground/35"
            style={{ width: `${16 - (h.level - minLevel) * 4}px` }}
          />
        ))}
      </div>
      {/* The list stays mounted and shows/hides with the shared motion, from the rail's edge. */}
      <div className="absolute top-1/2 right-0 -translate-y-1/2">
        <ol
          data-open={open}
          className="hk-pop-toggle m-0 max-h-[60vh] w-60 list-none overflow-y-auto rounded-xl bg-popover p-2 shadow-popover [--hk-pop-dx:2px] [--hk-pop-dy:0px] [--hk-pop-origin:right_center]"
        >
          {headings.map((h) => (
            <li key={h.pos} style={{ paddingLeft: `${(h.level - minLevel) * 12}px` }}>
              <button
                type="button"
                className="block w-full cursor-pointer truncate rounded-md px-2 py-1 text-left text-md text-subtle-foreground hover:bg-accent hover:text-foreground"
                onClick={() => bridge.scrollToHeading(h.pos)}
              >
                {h.text}
              </button>
            </li>
          ))}
        </ol>
      </div>
    </nav>
  )
}
