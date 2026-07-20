import { invoke } from '@tauri-apps/api/core'

import { protocolAssetUrl } from '#lib/asset-url'
import type { Backend, ImportedAsset } from '#lib/backend/backend'
import type { Doc, DocumentMeta, SearchHit, VaultInfo } from '#lib/types'

export class TauriBackend implements Backend {
  getVaultInfo() {
    return invoke<VaultInfo>('get_vault_info')
  }
  listDocuments() {
    return invoke<DocumentMeta[]>('list_documents')
  }
  createDocument(parentId: string | null, title: string) {
    return invoke<Doc>('create_document', { parentId, title })
  }
  loadDocument(id: string) {
    return invoke<Doc>('load_document', { id })
  }
  saveDocument(doc: Doc) {
    return invoke<Doc>('save_document', { doc })
  }
  deleteDocument(id: string) {
    return invoke<string[]>('delete_document', { id })
  }
  search(query: string) {
    return invoke<SearchHit[]>('search', { query })
  }
  rebuildIndex() {
    return invoke<number>('rebuild_index')
  }
  async importAsset(docId: string, file: File): Promise<ImportedAsset> {
    const bytes = Array.from(new Uint8Array(await file.arrayBuffer()))
    const stored = await invoke<string>('import_asset', {
      docId,
      fileName: file.name,
      bytes
    })
    return { fileName: stored, url: protocolAssetUrl(docId, stored) }
  }
  assetUrl(docId: string, fileName: string): string {
    return protocolAssetUrl(docId, fileName)
  }
}
