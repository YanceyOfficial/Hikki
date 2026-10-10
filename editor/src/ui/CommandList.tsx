import { useEffect, useRef } from 'react'

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
export function CommandList({ items, selectedIndex, emptyText = 'No results', onSelect, onHover }: Props) {
  const listRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    // Guard: the selected row may not exist yet during an items update.
    const row = listRef.current?.querySelector<HTMLElement>(`[data-index="${selectedIndex}"]`)
    row?.scrollIntoView?.({ block: 'nearest' })
  }, [selectedIndex, items])

  return (
    <div className="hk-command-list" role="listbox" ref={listRef}>
      {items.length === 0 ? (
        <div className="hk-command-empty">{emptyText}</div>
      ) : (
        items.map((item, index) => (
          <button
            key={item.id}
            type="button"
            role="option"
            aria-selected={index === selectedIndex}
            aria-label={item.title}
            data-index={index}
            className="hk-command-item"
            // Keep editor focus (and the iOS keyboard) when tapping an item.
            onMouseDown={(e) => e.preventDefault()}
            onMouseEnter={() => onHover?.(index)}
            onClick={() => onSelect(index)}
          >
            {item.icon && <span className="hk-command-icon" aria-hidden>{item.icon}</span>}
            <span className="hk-command-text">
              <span className="hk-command-title">{item.title}</span>
              {item.hint && <span className="hk-command-hint">{item.hint}</span>}
            </span>
          </button>
        ))
      )}
    </div>
  )
}

/** Shared arrow/enter navigation for any CommandList-driven popup. Returns true when the key was handled. */
export function handleListKey(key: string, count: number, selected: number, setSelected: (i: number) => void, choose: (i: number) => void): boolean {
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
