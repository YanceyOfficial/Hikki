import { useEffect, useRef } from 'react'

import { cn } from './cn'

export type CommandListItem = {
  id: string
  title: string
  hint?: string
  icon?: string
}

type Props = {
  items: CommandListItem[]
  selectedIndex: number
  emptyText?: string
  onSelect: (index: number) => void
  onHover?: (index: number) => void
}

/**
 * Generic keyboard/touch command list (slash menu today; mentions, emoji, "turn into" later).
 * Purely presentational: selection state and key handling live in the caller.
 */
export function CommandList({
  items,
  selectedIndex,
  emptyText = 'No results',
  onSelect,
  onHover
}: Props) {
  const listRef = useRef<HTMLDivElement>(null)

  // `items` is a deliberate dependency: a new result list must scroll its selected row into view too.
  useEffect(() => {
    // Guard: the selected row may not exist yet during an items update.
    const row = listRef.current?.querySelector<HTMLElement>(`[data-index="${selectedIndex}"]`)
    row?.scrollIntoView?.({ block: 'nearest' })
    // oxlint-disable-next-line react/exhaustive-effect-dependencies
  }, [selectedIndex, items])

  return (
    <div className="hk-command-list flex flex-col gap-px p-1.5" role="listbox" ref={listRef}>
      {items.length === 0 ? (
        <div className="hk-command-empty p-2 text-md text-muted-foreground">{emptyText}</div>
      ) : (
        items.map((item, index) => (
          <button
            key={item.id}
            type="button"
            role="option"
            aria-selected={index === selectedIndex}
            aria-label={item.title}
            data-index={index}
            className={cn(
              'hk-command-item flex min-h-10 cursor-pointer select-none items-center gap-2.5 rounded-md px-2 py-1 text-left coarse:min-h-12',
              index === selectedIndex && 'bg-accent'
            )}
            // Keep editor focus (and the iOS keyboard) when tapping an item.
            onMouseDown={(e) => e.preventDefault()}
            onMouseEnter={() => onHover?.(index)}
            onClick={() => onSelect(index)}
          >
            {item.icon && (
              <span
                className="grid size-10 flex-none place-items-center rounded-md border border-border bg-background text-md font-semibold text-subtle-foreground"
                aria-hidden
              >
                {item.icon}
              </span>
            )}
            <span className="flex min-w-0 flex-col">
              <span className="hk-command-title text-base text-foreground">{item.title}</span>
              {item.hint && (
                <span className="truncate text-sm text-muted-foreground">{item.hint}</span>
              )}
            </span>
          </button>
        ))
      )}
    </div>
  )
}

/** Shared arrow/enter navigation for any CommandList-driven popup. Returns true when the key was handled. */
export function handleListKey(
  key: string,
  count: number,
  selected: number,
  setSelected: (i: number) => void,
  choose: (i: number) => void
): boolean {
  if (key === 'ArrowDown') {
    if (count) setSelected((selected + 1) % count)
    return true
  }
  if (key === 'ArrowUp') {
    if (count) setSelected((selected - 1 + count) % count)
    return true
  }
  if (key === 'Enter' || key === 'Tab') {
    if (!count) return false
    choose(selected)
    return true
  }
  return false
}
