// Mirrors `src-tauri/src/index.rs`'s `extract_text`/`collect_text` walk
// exactly (same four child keys, same depth-first order) so the frontend's
// own word count - used by `MemoryBackend`'s dashboard-stats simulation -
// matches the real Rust computation the Tauri backend uses.
function collectText(value: unknown, out: string[]): void {
  if (Array.isArray(value)) {
    for (const item of value) collectText(item, out)
    return
  }
  if (value && typeof value === 'object') {
    const obj = value as Record<string, unknown>
    if (typeof obj.text === 'string') out.push(obj.text)
    for (const key of ['content', 'children', 'rows', 'cells']) {
      if (key in obj) collectText(obj[key], out)
    }
  }
}

export function countWords(blocks: unknown): number {
  const out: string[] = []
  collectText(blocks, out)
  return out.join(' ').split(/\s+/).filter(Boolean).length
}
