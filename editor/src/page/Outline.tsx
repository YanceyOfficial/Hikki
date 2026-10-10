import { useState, useSyncExternalStore } from 'react'

import type { EditorBridge } from '../bridge'
import { cn } from '../ui/cn'

/**
 * Notion-style outline on the right edge: a stack of short bars (one per heading, indented by level)
 * that expands into a clickable table of contents on hover/focus. Hidden for fewer than two headings.
 */
export function Outline({ bridge }: { bridge: EditorBridge }) {
  const { headings } = useSyncExternalStore(bridge.page.subscribe, bridge.page.get)
  const [open, setOpen] = useState(false)
  if (headings.length < 2) return null
  const minLevel = Math.min(...headings.map((h) => h.level))

  return (
    <nav
      className="fixed top-1/2 right-4 z-20 flex -translate-y-1/2 justify-end max-[1000px]:hidden"
      aria-label="Outline"
      onMouseEnter={() => setOpen(true)}
      onMouseLeave={() => setOpen(false)}
      onFocus={() => setOpen(true)}
      onBlur={(e) => {
        if (!e.currentTarget.contains(e.relatedTarget as Node)) setOpen(false)
      }}
    >
      <div
        className={cn('flex flex-col items-end gap-2.5 px-1 py-2', open && 'hidden')}
        aria-hidden
      >
        {headings.map((h) => (
          <span
            key={h.pos}
            className="h-0.5 rounded-full bg-placeholder"
            style={{ width: `${16 - (h.level - minLevel) * 4}px` }}
          />
        ))}
      </div>
      <ol
        className={cn(
          'm-0 max-h-[60vh] w-60 list-none overflow-y-auto rounded-xl bg-popover p-2 shadow-popover',
          !open && 'hidden'
        )}
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
    </nav>
  )
}
