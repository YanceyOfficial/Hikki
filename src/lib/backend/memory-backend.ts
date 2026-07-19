import type { Backend, ImportedAsset } from '#lib/backend/backend'
import type { Doc, DocumentMeta, SearchHit, VaultInfo } from '#lib/types'

const notFound = (id: string) =>
  Object.assign(new Error(`document not found: ${id}`), { code: 'HK-1003' })
const toMeta = ({
  schemaVersion: _s,
  cover: _c,
  blocks: _b,
  ...meta
}: Doc): DocumentMeta => meta

export class MemoryBackend implements Backend {
  private docs = new Map<string, Doc>()
  private assets = new Map<string, string>()

  async getVaultInfo(): Promise<VaultInfo> {
    const alive = [...this.docs.values()].filter((d) => d.deletedAt === null)
    return { vaultPath: '(in-memory)', documentCount: alive.length }
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
      createdAt: now,
      updatedAt: now,
      deletedAt: null
    }
    this.docs.set(doc.id, doc)
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
}
