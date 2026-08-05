import { invoke } from '@tauri-apps/api/core'

import { protocolAssetUrl } from '#lib/asset-url'
import type { Backend, ImportedAsset } from '#lib/backend/backend'
import type {
  AiSettings,
  Doc,
  DocumentMeta,
  LogEntry,
  LogFilter,
  SearchHit,
  VaultInfo
} from '#lib/types'

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
  getApiKey(provider: string) {
    return invoke<string | null>('get_api_key', { provider })
  }
  setApiKey(provider: string, key: string) {
    return invoke<void>('set_api_key', { provider, key })
  }
  deleteApiKey(provider: string) {
    return invoke<void>('delete_api_key', { provider })
  }
  getAiSettings() {
    return invoke<AiSettings>('get_ai_settings')
  }
  saveAiSettings(settings: AiSettings) {
    return invoke<AiSettings>('save_ai_settings', {
      defaultAiProvider: settings.defaultAiProvider,
      defaultAiModel: settings.defaultAiModel
    })
  }
  setVaultPath(path: string) {
    return invoke<VaultInfo>('set_vault_path', { path })
  }
  appendLog(entry: LogEntry) {
    return invoke<void>('append_log', { entry })
  }
  readLogs(filter: LogFilter) {
    return invoke<LogEntry[]>('read_logs', { filter })
  }
  clearLogs() {
    return invoke<void>('clear_logs')
  }
  exportLogs(path: string, filter: LogFilter) {
    return invoke<void>('export_logs', { path, filter })
  }
}
