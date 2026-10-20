/**
 * A drawing as a page stores it: Excalidraw's elements (the live ones — deleted elements are Excalidraw's own
 * bookkeeping) and the pictures placed in it, each a stored file referenced by URL rather than a data URL in the page.
 * Nothing here loads Excalidraw: the page reads and checks drawings without it; the editor itself (`./canvas`) loads
 * only when a drawing is opened.
 */

/** A picture in a drawing: where its file is stored and its type (Excalidraw's `BinaryFileData` without the data). */
export type DrawingFileRef = { src: string; mimeType: string }

/** An Excalidraw element as stored: a plain JSON object with at least an `id` and a `type`. */
export type StoredElement = { id: string; type: string; [key: string]: unknown }

export type DrawingData = {
  elements: StoredElement[]
  /** By Excalidraw's file id (an image element's `fileId`). */
  files: Record<string, DrawingFileRef>
}

/** The pictures a drawing may hold (Excalidraw's own list of image types, minus what WebKit can't show). */
const PICTURE_TYPES = new Set([
  'image/png',
  'image/jpeg',
  'image/gif',
  'image/webp',
  'image/svg+xml',
  'image/avif'
])

const isObject = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value)

/**
 * The elements of a stored drawing: objects with a string id and type, deleted ones dropped. Stored content can
 * carry anything (synced, imported, pasted), so whatever else is there is left out rather than handed to Excalidraw.
 */
export function storedElements(value: unknown): StoredElement[] {
  if (!Array.isArray(value)) return []
  return value.filter(
    (element): element is StoredElement =>
      isObject(element) &&
      typeof element.id === 'string' &&
      typeof element.type === 'string' &&
      element.isDeleted !== true
  )
}

/** The picture references of a stored drawing whose `src` passes `isSafeSrc` and whose type is a picture's. */
export function storedFiles(
  value: unknown,
  isSafeSrc: (src: string) => boolean
): Record<string, DrawingFileRef> {
  if (!isObject(value)) return {}
  const files: Record<string, DrawingFileRef> = {}
  for (const [id, ref] of Object.entries(value)) {
    if (!isObject(ref)) continue
    const { src, mimeType } = ref
    if (typeof src !== 'string' || typeof mimeType !== 'string') continue
    if (!PICTURE_TYPES.has(mimeType) || !isSafeSrc(src)) continue
    files[id] = { src, mimeType }
  }
  return files
}

/**
 * The words in a drawing, one text element a line in the order they were drawn (a label inside a shape included):
 * what search finds and word counts count. HikkiCore's `ContentText` reads a drawing the same way
 * (`design/fixtures/content-text.json`).
 */
export function drawingText(elements: readonly unknown[]): string {
  return storedElements(elements)
    .filter((element) => element.type === 'text')
    .map((element) => {
      const text = typeof element.originalText === 'string' ? element.originalText : element.text
      return typeof text === 'string' ? text.trim() : ''
    })
    .filter((text) => text.length > 0)
    .join('\n')
}

/** The ids of the pictures the elements show (image elements' `fileId`), each once. */
export function usedFileIds(elements: readonly unknown[]): string[] {
  const ids = new Set<string>()
  for (const element of storedElements(elements)) {
    if (element.type === 'image' && typeof element.fileId === 'string') ids.add(element.fileId)
  }
  return [...ids]
}

/**
 * A model's answer to "draw this" as Mermaid: the first fenced block when there is one (```mermaid or a bare fence),
 * else the whole answer. Models wrap code in fences however they are asked.
 */
export function mermaidFromAnswer(answer: string): string {
  const fenced = /```[ \t]*(?:mermaid)?[ \t]*\r?\n([\s\S]*?)```/iu.exec(answer)
  return (fenced ? fenced[1] : answer).trim()
}

/**
 * Where Excalidraw finds its fonts: `<base>fonts/<family>/<file>.woff2`. The editor bundles every one of them
 * (the hand-drawn CJK font included), so nothing is ever fetched from a CDN (`vite-plugin.ts` drops Excalidraw's
 * esm.sh fallback from the bundle).
 */
export function setDrawingAssetPath(base: string): void {
  ;(window as { EXCALIDRAW_ASSET_PATH?: string }).EXCALIDRAW_ASSET_PATH = base
}

/** Excalidraw's language for the app's ("zh-Hans" → "zh-CN"); English for anything it doesn't have. */
export function excalidrawLanguage(locale: string): string {
  const lower = locale.toLowerCase()
  if (lower.startsWith('zh')) return /-(hant|tw|hk|mo)\b/u.test(lower) ? 'zh-TW' : 'zh-CN'
  if (lower.startsWith('ja')) return 'ja-JP'
  return 'en'
}

/**
 * When Excalidraw lays itself out for a phone (its own breakpoints: a narrow window, or a short one on a touch screen)
 * — its toolbar then fills the top, so whatever the editor adds goes in a bar of its own.
 */
export const COMPACT_DRAWING_QUERY = '(max-width: 729px), (max-height: 499px) and (pointer: coarse)'
