import { Fragment, useEffect, useRef, type ReactNode } from 'react'

import type { FloatingAnchor, FloatingLayer } from './floating'
import { GlidingHighlight } from './gliding-highlight'
import { MenuRow, MenuTitle } from './menu-row'

export type CommandListItem = {
  id: string
  title: string
  hint?: string
  icon?: ReactNode
  /** A title over the rows that share it ("@": Date, then Pages); rows without one have none. */
  group?: string
}

type Props = {
  items: CommandListItem[]
  selectedIndex: number
  emptyText?: string
  onSelect: (index: number) => void
  onHover?: (index: number) => void
}

/**
 * Generic keyboard/touch command list: the "@" page mentions and ":" emoji suggestions.
 * Purely presentational: selection state and key handling live in the caller.
 */
export function CommandList({ items, selectedIndex, emptyText, onSelect, onHover }: Props) {
  const listRef = useRef<HTMLDivElement>(null)

  // `items` is a deliberate dependency: a new result list must scroll its selected row into view too.
  useEffect(() => {
    // Guard: the selected row may not exist yet during an items update.
    const row = listRef.current?.querySelector<HTMLElement>(`[data-index="${selectedIndex}"]`)
    row?.scrollIntoView?.({ block: 'nearest' })
    // oxlint-disable-next-line react/exhaustive-effect-dependencies
  }, [selectedIndex, items])

  return (
    <div
      className="hk-command-list relative flex flex-col gap-px p-(--layout-popover-padding)"
      role="listbox"
      ref={listRef}
    >
      <GlidingHighlight listRef={listRef} index={selectedIndex} />
      {items.length === 0 ? (
        <div className="hk-command-empty p-2 text-md text-muted-foreground">{emptyText}</div>
      ) : (
        items.map((item, index) => (
          <Fragment key={item.id}>
            {item.group && item.group !== items[index - 1]?.group && (
              <MenuTitle>{item.group}</MenuTitle>
            )}
            <MenuRow
              glide
              role="option"
              aria-selected={index === selectedIndex}
              aria-label={item.title}
              data-index={index}
              className="hk-command-item h-auto min-h-10 py-1 coarse:h-auto coarse:min-h-12"
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
                <span className="hk-command-title text-sm text-foreground">{item.title}</span>
                {item.hint && (
                  <span className="truncate text-xs text-muted-foreground">{item.hint}</span>
                )}
              </span>
            </MenuRow>
          </Fragment>
        ))
      )}
    </div>
  )
}

/** The row ↑ / ↓ moves to in a list of `count` (wrapping round), or null for any other key. */
export function listStep(key: string, count: number, selected: number): number | null {
  if (key !== 'ArrowDown' && key !== 'ArrowUp') return null
  if (!count) return selected
  return (selected + (key === 'ArrowDown' ? 1 : -1) + count) % count
}

/** Shared arrow/enter navigation for any CommandList-driven popup. Returns true when the key was handled. */
export function handleListKey(
  key: string,
  count: number,
  selected: number,
  setSelected: (i: number) => void,
  choose: (i: number) => void
): boolean {
  const step = listStep(key, count, selected)
  if (step !== null) {
    if (count) setSelected(step)
    return true
  }
  if (key === 'Enter' || key === 'Tab') {
    if (!count) return false
    choose(selected)
    return true
  }
  return false
}

/** Draws a CommandList in a floating layer (extensions/suggestion-menu.ts drives it). */
export function renderCommandList(
  layer: FloatingLayer,
  props: Props,
  anchor: FloatingAnchor
): void {
  layer.render(<CommandList {...props} />, anchor)
}
