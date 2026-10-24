/**
 * Image addresses that have loaded in this run of the page. Switching tabs rebuilds the whole page, and a cover or a
 * body image the reader has just seen would otherwise go through its skeleton and fade in again every time — a flash
 * on each switch. One seen before is drawn as loaded at once (it comes from WebKit's cache).
 */
const loaded = new Set<string>()

/** Past this many, the oldest are forgotten (they only fade in again). */
const LIMIT = 2000

export function markImageLoaded(src: string): void {
  if (!src) return
  loaded.delete(src)
  loaded.add(src)
  if (loaded.size > LIMIT) {
    const oldest = loaded.values().next().value
    if (oldest !== undefined) loaded.delete(oldest)
  }
}

export function imageLoadedBefore(src: string): boolean {
  return src !== '' && loaded.has(src)
}
