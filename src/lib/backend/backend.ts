import type { Doc, DocumentMeta, SearchHit, VaultInfo } from '#lib/types'

export interface Backend {
  getVaultInfo(): Promise<VaultInfo>
  listDocuments(): Promise<DocumentMeta[]>
  createDocument(parentId: string | null, title: string): Promise<Doc>
  loadDocument(id: string): Promise<Doc>
  saveDocument(doc: Doc): Promise<Doc>
  deleteDocument(id: string): Promise<string[]>
  search(query: string): Promise<SearchHit[]>
  rebuildIndex(): Promise<number>
}
