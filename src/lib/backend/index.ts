import type { Backend } from '#lib/backend/backend'
import { MemoryBackend } from '#lib/backend/memory-backend'
import { TauriBackend } from '#lib/backend/tauri-backend'

export const isTauri = () =>
  typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window

/** Singleton backend: real Tauri IPC inside the app, in-memory in plain browsers (dev + Playwright). */
export const backend: Backend = isTauri()
  ? new TauriBackend()
  : new MemoryBackend()
