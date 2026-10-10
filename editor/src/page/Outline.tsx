import { useState, useSyncExternalStore } from 'react'
import type { EditorBridge } from '../bridge'

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
      className={`hk-outline ${open ? 'is-open' : ''}`}
      aria-label="Outline"
      onMouseEnter={() => setOpen(true)}
      onMouseLeave={() => setOpen(false)}
      onFocus={() => setOpen(true)}
      onBlur={(e) => { if (!e.currentTarget.contains(e.relatedTarget as Node)) setOpen(false) }}
    >
      <div className="hk-outline-bars" aria-hidden>
        {headings.map((h) => (
          <span key={h.pos} className="hk-outline-bar" style={{ width: `${16 - (h.level - minLevel) * 4}px` }} />
        ))}
      </div>
      <ol className="hk-outline-panel">
        {headings.map((h) => (
          <li key={h.pos} style={{ paddingLeft: `${(h.level - minLevel) * 12}px` }}>
            <button type="button" onClick={() => bridge.scrollToHeading(h.pos)}>{h.text}</button>
          </li>
        ))}
      </ol>
    </nav>
  )
}
