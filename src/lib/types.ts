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
