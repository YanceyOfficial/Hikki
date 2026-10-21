import { storedLibraryItems, type StoredLibraryItem } from './scene'

/** Where Excalidraw's Library is kept: read when a drawing opens, written whenever it changes. */
export type DrawingLibraryHost = {
  /** The stored items (checked here); rejects when they can't be read — the Library is then never written over. */
  load: () => Promise<unknown>
  save: (items: StoredLibraryItem[]) => void
}

/**
 * One opening's Library: `load` reads the stored items (checked), `changed` writes Excalidraw's items back — checked,
 * only when they differ from what was read or last written, and never when the stored ones couldn't be read (an
 * empty Library over an unreadable file would lose it).
 */
export function libraryKeeper(host: DrawingLibraryHost) {
  /** The Library as last read or written (JSON); null while it may not be written. */
  let saved: string | null = null
  return {
    async load(): Promise<StoredLibraryItem[]> {
      try {
        const items = storedLibraryItems(await host.load())
        saved = JSON.stringify(items)
        return items
      } catch {
        return []
      }
    },
    changed(items: readonly unknown[]): void {
      if (saved === null) return
      const stored = storedLibraryItems(items)
      const json = JSON.stringify(stored)
      if (json === saved) return
      saved = json
      host.save(stored)
    }
  }
}
