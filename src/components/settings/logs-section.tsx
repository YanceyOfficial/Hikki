import { save as saveDialog } from '@tauri-apps/plugin-dialog'
import { useEffect, useState } from 'react'

import { Button } from '#components/ui/button'
import { Field } from '#components/ui/field'
import { Input } from '#components/ui/input'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue
} from '#components/ui/select'
import { backend } from '#lib/backend/index'
import { reportError } from '#lib/errors'
import type { LogEntry, LogLevel } from '#lib/types'

const LEVEL_OPTIONS: { value: LogLevel; label: string }[] = [
  { value: 'info', label: 'Info' },
  { value: 'warn', label: 'Warn' },
  { value: 'error', label: 'Error' }
]

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
      <Field orientation="horizontal">
        <Select
          items={[{ label: 'All levels', value: 'all' }, ...LEVEL_OPTIONS]}
          value={level || 'all'}
          onValueChange={(value) =>
            setLevel(value === 'all' ? '' : (value as LogLevel))
          }
        >
          <SelectTrigger data-testid="log-level-filter" size="sm">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All levels</SelectItem>
            {LEVEL_OPTIONS.map((opt) => (
              <SelectItem key={opt.value} value={opt.value}>
                {opt.label}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        <Input
          data-testid="log-search"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search…"
        />
        <Button
          variant="outline"
          size="sm"
          data-testid="logs-export"
          onClick={exportLogs}
        >
          Export…
        </Button>
        <Button
          variant="outline"
          size="sm"
          data-testid="logs-clear"
          onClick={clear}
        >
          Clear
        </Button>
      </Field>
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
