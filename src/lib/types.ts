export interface DocumentMeta {
  id: string
  parentId: string | null
  title: string
  icon: string | null
  createdAt: string
  updatedAt: string
  deletedAt: string | null
}

export interface Doc extends DocumentMeta {
  schemaVersion: number
  cover: string | null
  blocks: unknown[]
  threads: unknown
}

export interface SearchHit {
  id: string
  title: string
  snippet: string
}

export interface VaultInfo {
  vaultPath: string
  documentCount: number
}

export interface AiSettings {
  defaultAiProvider: string | null
  defaultAiModel: string | null
}

export type LogLevel = 'info' | 'warn' | 'error'

export interface LogEntry {
  level: LogLevel
  scope: string
  message: string
  data?: unknown
  timestamp: string
}

export interface LogFilter {
  level?: LogLevel
  query?: string
}

export interface DailyWordCount {
  date: string
  wordDelta: number
}

export interface DailyActivity {
  date: string
  activityCount: number
}

export interface DashboardStats {
  totalDocuments: number
  totalWords: number
  streakDays: number
  docsEditedThisWeek: number
  dailyWords: DailyWordCount[]
  dailyActivity: DailyActivity[]
}
