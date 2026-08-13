import { differenceInCalendarDays, format, subDays } from 'date-fns'

import type { Backend, ImportedAsset } from '#lib/backend/backend'
import type {
  AiSettings,
  DashboardStats,
  Doc,
  DocumentMeta,
  LogEntry,
  LogFilter,
  SearchHit,
  VaultInfo
} from '#lib/types'
import { countWords } from '#lib/word-count'

const notFound = (id: string) =>
  Object.assign(new Error(`document not found: ${id}`), { code: 'HK-1003' })
const toMeta = ({
  schemaVersion: _s,
  cover: _c,
  blocks: _b,
  threads: _t,
  ...meta
}: Doc): DocumentMeta => meta

interface ActivityEntry {
  docId: string
  wordDelta: number
  at: string
}

export class MemoryBackend implements Backend {
  private docs = new Map<string, Doc>()
  private assets = new Map<string, string>()
  private apiKeys = new Map<string, string>()
  private aiSettings: AiSettings = {
    defaultAiProvider: null,
    defaultAiModel: null
  }
  private vaultPath = '(in-memory)'
  private logs: LogEntry[] = []
  private activity: ActivityEntry[] = []
  private wordCounts = new Map<string, number>()

  async getVaultInfo(): Promise<VaultInfo> {
    const alive = [...this.docs.values()].filter((d) => d.deletedAt === null)
    return { vaultPath: this.vaultPath, documentCount: alive.length }
  }

  async listDocuments(): Promise<DocumentMeta[]> {
    return [...this.docs.values()]
      .map(toMeta)
      .sort((a, b) => a.createdAt.localeCompare(b.createdAt))
  }

  async createDocument(parentId: string | null, title: string): Promise<Doc> {
    const now = new Date().toISOString()
    const doc: Doc = {
      schemaVersion: 1,
      id: crypto.randomUUID(),
      parentId,
      title,
      icon: null,
      cover: null,
      blocks: [],
      threads: {},
      createdAt: now,
      updatedAt: now,
      deletedAt: null
    }
    this.docs.set(doc.id, doc)
    const wordCount = countWords(doc.blocks)
    this.wordCounts.set(doc.id, wordCount)
    this.activity.push({
      docId: doc.id,
      wordDelta: wordCount,
      at: doc.updatedAt
    })
    return structuredClone(doc)
  }

  async loadDocument(id: string): Promise<Doc> {
    const doc = this.docs.get(id)
    if (!doc) throw notFound(id)
    return structuredClone(doc)
  }

  async saveDocument(doc: Doc): Promise<Doc> {
    const existing = this.docs.get(doc.id)
    if (!existing) throw notFound(doc.id)
    const saved = {
      ...structuredClone(doc),
      // A pending autosave must never resurrect a trashed document;
      // restoring from Trash is an explicit separate operation.
      deletedAt: existing.deletedAt,
      updatedAt: new Date().toISOString()
    }
    const previousWordCount = this.wordCounts.get(doc.id) ?? 0
    const newWordCount = countWords(saved.blocks)
    this.wordCounts.set(saved.id, newWordCount)
    this.activity.push({
      docId: saved.id,
      wordDelta: newWordCount - previousWordCount,
      at: saved.updatedAt
    })
    this.docs.set(saved.id, saved)
    return structuredClone(saved)
  }

  async deleteDocument(id: string): Promise<string[]> {
    if (!this.docs.has(id)) throw notFound(id)
    const affected = [id]
    const seen = new Set<string>([id])
    // Walk down the tree collecting descendants, guarding against cycles
    // (e.g. a hand-edited parentId loop).
    for (let i = 0; i < affected.length; i++) {
      for (const doc of this.docs.values()) {
        if (doc.parentId === affected[i] && !seen.has(doc.id)) {
          seen.add(doc.id)
          affected.push(doc.id)
        }
      }
    }
    const now = new Date().toISOString()
    for (const docId of affected) {
      const doc = this.docs.get(docId)!
      this.docs.set(docId, { ...doc, deletedAt: now, updatedAt: now })
    }
    return affected
  }

  async search(query: string): Promise<SearchHit[]> {
    const q = query.trim().toLowerCase()
    if (!q) return []
    return [...this.docs.values()]
      .filter((d) => d.deletedAt === null)
      .filter(
        (d) =>
          d.title.toLowerCase().includes(q) ||
          JSON.stringify(d.blocks).toLowerCase().includes(q)
      )
      .map((d) => ({ id: d.id, title: d.title, snippet: '' }))
  }

  async rebuildIndex(): Promise<number> {
    return [...this.docs.values()].length
  }

  async getDashboardStats(): Promise<DashboardStats> {
    const alive = [...this.docs.values()].filter((d) => d.deletedAt === null)
    const totalWords = alive.reduce(
      (sum, d) => sum + (this.wordCounts.get(d.id) ?? 0),
      0
    )

    const today = new Date()
    const dayKey = (date: Date) => format(date, 'yyyy-MM-dd')
    const todayKey = dayKey(today)

    const wordsByDay = new Map<string, number>()
    const activityByDay = new Map<string, number>()
    const docsThisWeek = new Set<string>()

    for (const entry of this.activity) {
      const entryDate = new Date(entry.at)
      const key = dayKey(entryDate)
      wordsByDay.set(key, (wordsByDay.get(key) ?? 0) + entry.wordDelta)
      activityByDay.set(key, (activityByDay.get(key) ?? 0) + 1)
      const daysAgo = differenceInCalendarDays(today, entryDate)
      if (daysAgo >= 0 && daysAgo < 7) docsThisWeek.add(entry.docId)
    }

    const dailyWords = Array.from({ length: 30 }, (_, i) => {
      const key = dayKey(subDays(today, 29 - i))
      return { date: key, wordDelta: wordsByDay.get(key) ?? 0 }
    })

    const dailyActivity = Array.from({ length: 35 }, (_, i) => {
      const key = dayKey(subDays(today, 34 - i))
      return { date: key, activityCount: activityByDay.get(key) ?? 0 }
    })

    let streakDays = 0
    let cursor = activityByDay.has(todayKey) ? today : subDays(today, 1)
    while (activityByDay.has(dayKey(cursor))) {
      streakDays++
      cursor = subDays(cursor, 1)
    }

    return {
      totalDocuments: alive.length,
      totalWords,
      streakDays,
      docsEditedThisWeek: docsThisWeek.size,
      dailyWords,
      dailyActivity
    }
  }

  async getRecentDocuments(limit: number): Promise<DocumentMeta[]> {
    return [...this.docs.values()]
      .filter((d) => d.deletedAt === null)
      .map(toMeta)
      .sort((a, b) => b.updatedAt.localeCompare(a.updatedAt))
      .slice(0, limit)
  }

  async importAsset(docId: string, file: File): Promise<ImportedAsset> {
    const url =
      typeof URL.createObjectURL === 'function'
        ? URL.createObjectURL(file)
        : `memory-asset:${docId}/${file.name}`
    this.assets.set(`${docId}/${file.name}`, url)
    return { fileName: file.name, url }
  }

  assetUrl(docId: string, fileName: string): string {
    return (
      this.assets.get(`${docId}/${fileName}`) ??
      `memory-asset:${docId}/${fileName}`
    )
  }

  async getApiKey(provider: string): Promise<string | null> {
    return this.apiKeys.get(provider) ?? null
  }

  async setApiKey(provider: string, key: string): Promise<void> {
    this.apiKeys.set(provider, key)
  }

  async deleteApiKey(provider: string): Promise<void> {
    this.apiKeys.delete(provider)
  }

  async getAiSettings(): Promise<AiSettings> {
    return this.aiSettings
  }

  async saveAiSettings(settings: AiSettings): Promise<AiSettings> {
    this.aiSettings = settings
    return this.aiSettings
  }

  async setVaultPath(path: string): Promise<VaultInfo> {
    this.vaultPath = path
    return { vaultPath: this.vaultPath, documentCount: this.docs.size }
  }

  async appendLog(entry: LogEntry): Promise<void> {
    this.logs.push(entry)
  }

  async readLogs(filter: LogFilter): Promise<LogEntry[]> {
    return this.logs
      .filter((e) => !filter.level || e.level === filter.level)
      .filter(
        (e) =>
          !filter.query ||
          e.message.toLowerCase().includes(filter.query.toLowerCase())
      )
      .slice()
      .reverse()
  }

  async clearLogs(): Promise<void> {
    this.logs = []
  }

  // No real filesystem exists in browser/dev mode to write an export file
  // to - this deliberately no-ops rather than simulating a write, matching
  // how other native-only affordances (the native folder/save pickers
  // themselves) already behave outside a real Tauri webview.
  async exportLogs(): Promise<void> {}
}
