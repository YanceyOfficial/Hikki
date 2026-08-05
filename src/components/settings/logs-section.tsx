import { save as saveDialog } from '@tauri-apps/plugin-dialog'
import { useEffect, useState } from 'react'

import { backend } from '#lib/backend/index'
import { reportError } from '#lib/errors'
import type { LogEntry, LogLevel } from '#lib/types'

export function LogsSection() {
  const [entries, setEntries] = useState<LogEntry[]>([])
  const [level, setLevel] = useState<LogLevel | ''>('')
  const [query, setQuery] = useState('')

  const refresh = async (nextLevel: LogLevel | '', nextQuery: string) => {
    try {
      const logs = await backend.readLogs({
        level: nextLevel || undefined,
        query: nextQuery || undefined
      })
      setEntries(logs)
    } catch (err) {
      reportError('HK-6001', {
        message: err instanceof Error ? err.message : String(err)
      })
    }
  }

  useEffect(() => {
    refresh(level, query)
    // Deliberately re-runs only on level/query change, not on every render.
  }, [level, query])

  const clear = async () => {
    await backend.clearLogs()
    setEntries([])
  }

  const exportLogs = async () => {
    // No `isTauri()` guard: `save()` (like `open()` in general-section.tsx)
    // rejects rather than throws synchronously outside a real Tauri
    // webview, so the catch below already handles browser/dev mode safely
    // - an extra guard here would only make this untestable in jsdom
    // (isTauri() never reports true there), the same gap Task 8 hit and
    // fixed for AboutSection's getVersion() call.
    try {
      const path = await saveDialog({ defaultPath: 'hikki-logs.jsonl' })
      if (!path) return
      await backend.exportLogs(path, {
        level: level || undefined,
        query: query || undefined
      })
    } catch (err) {
      reportError('HK-6002', {
        message: err instanceof Error ? err.message : String(err)
      })
    }
  }

  return (
    <div className="flex h-full flex-col gap-3">
      <div className="flex gap-2">
        <select
          data-testid="log-level-filter"
          value={level}
          onChange={(e) => setLevel(e.target.value as LogLevel | '')}
          className="border-input h-8 rounded-lg border bg-transparent px-2.5 text-sm"
        >
          <option value="">All levels</option>
          <option value="info">Info</option>
          <option value="warn">Warn</option>
          <option value="error">Error</option>
        </select>
        <input
          data-testid="log-search"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search…"
          className="border-input h-8 flex-1 rounded-lg border bg-transparent px-2.5 text-sm"
        />
        <button
          type="button"
          data-testid="logs-export"
          onClick={exportLogs}
          className="border-input h-8 rounded-lg border px-2.5 text-sm"
        >
          Export…
        </button>
        <button
          type="button"
          data-testid="logs-clear"
          onClick={clear}
          className="border-input h-8 rounded-lg border px-2.5 text-sm"
        >
          Clear
        </button>
      </div>
      <div className="min-h-0 flex-1 overflow-y-auto">
        {entries.map((entry, i) => (
          <div
            key={i}
            data-testid="log-row"
            className="flex gap-2 border-b py-1 text-xs"
          >
            <span className="text-muted-foreground">{entry.timestamp}</span>
            <span className="font-medium">{entry.level}</span>
            <span className="text-muted-foreground">{entry.scope}</span>
            <span>{entry.message}</span>
          </div>
        ))}
      </div>
    </div>
  )
}
