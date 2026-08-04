import type {
  AiSettings,
  Doc,
  DocumentMeta,
  LogEntry,
  LogFilter,
  SearchHit,
  VaultInfo
} from '#lib/types'

export interface ImportedAsset {
  fileName: string
  url: string
}

export interface Backend {
  getVaultInfo(): Promise<VaultInfo>
  listDocuments(): Promise<DocumentMeta[]>
  createDocument(parentId: string | null, title: string): Promise<Doc>
  loadDocument(id: string): Promise<Doc>
  saveDocument(doc: Doc): Promise<Doc>
  deleteDocument(id: string): Promise<string[]>
  search(query: string): Promise<SearchHit[]>
  rebuildIndex(): Promise<number>
  importAsset(docId: string, file: File): Promise<ImportedAsset>
  assetUrl(docId: string, fileName: string): string
  getApiKey(provider: string): Promise<string | null>
  setApiKey(provider: string, key: string): Promise<void>
  deleteApiKey(provider: string): Promise<void>
  getAiSettings(): Promise<AiSettings>
  saveAiSettings(settings: AiSettings): Promise<AiSettings>
  setVaultPath(path: string): Promise<VaultInfo>
  appendLog(entry: LogEntry): Promise<void>
  readLogs(filter: LogFilter): Promise<LogEntry[]>
  clearLogs(): Promise<void>
}
