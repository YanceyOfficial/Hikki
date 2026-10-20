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
 * The kinds of element a drawing keeps: shapes, lines, words, pictures and frames. Left out are the ones that put a
 * web page in the drawing — `embeddable` (a third-party page in a frame) and `iframe` (HTML it runs, the "magic
 * frame" output) — and the magic frame itself: a drawing never loads or runs anything off the device.
 */
const DRAWABLE_TYPES = new Set([
  'rectangle',
  'diamond',
  'ellipse',
  'arrow',
  'line',
  'freedraw',
  'text',
  'image',
  'frame'
])

/** Whether Excalidraw may keep an element of this kind in a drawing (see `DRAWABLE_TYPES`). */
export const isDrawableType = (type: unknown): boolean =>
  typeof type === 'string' && DRAWABLE_TYPES.has(type)

/**
 * An element's link as a drawing keeps it: a web address (http or https, opened in the browser through the app) —
 * anything else (`javascript:`, `data:`, a relative path that would navigate the page) is dropped.
 */
export function safeDrawingLink(link: unknown): string | null {
  if (typeof link !== 'string') return null
  try {
    const url = new URL(link.trim())
    return url.protocol === 'https:' || url.protocol === 'http:' ? url.href : null
  } catch {
    return null
  }
}

/**
 * The elements of a stored drawing: objects with a string id and a kind a drawing keeps, deleted ones dropped.
 * Stored content can carry anything (synced, imported, pasted), so it is treated as hostile: links only to the web,
 * no `customData` (where Excalidraw keeps HTML a frame runs), nothing that loads a page.
 */
export function storedElements(value: unknown): StoredElement[] {
  if (!Array.isArray(value)) return []
  const elements: StoredElement[] = []
  for (const element of value) {
    if (!isObject(element) || typeof element.id !== 'string') continue
    if (!isDrawableType(element.type) || element.isDeleted === true) continue
    const { customData: _customData, ...rest } = element
    elements.push(
      ('link' in rest ? { ...rest, link: safeDrawingLink(rest.link) } : rest) as StoredElement
    )
  }
  return elements
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

const PICTURE_DATA_URL = /^data:image\/(?:png|jpeg|gif|webp|avif|svg\+xml);base64,[a-z0-9+/=]+$/iu

/**
 * Pictures arriving in a drawing (pasted, from a library) as Excalidraw holds them: only the ones whose data is a
 * picture's data URL. A file whose `dataURL` names an address would make Excalidraw load it from the network.
 */
export function inlineFiles<T extends { dataURL?: unknown; mimeType?: unknown }>(
  files: Record<string, T> | null | undefined
): Record<string, T> {
  const kept: Record<string, T> = {}
  for (const [id, file] of Object.entries(files ?? {})) {
    if (!isObject(file) || typeof file.dataURL !== 'string') continue
    if (typeof file.mimeType !== 'string' || !PICTURE_TYPES.has(file.mimeType)) continue
    if (PICTURE_DATA_URL.test(file.dataURL)) kept[id] = file
  }
  return kept
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
 * else the whole answer — made safe to draw (`safeMermaid`). Models wrap code in fences however they are asked.
 */
export function mermaidFromAnswer(answer: string): string {
  const fenced = /```[ \t]*(?:mermaid)?[ \t]*\r?\n([\s\S]*?)```/iu.exec(answer)
  return safeMermaid((fenced ? fenced[1] : answer).trim())
}

/** Whether pasted text reads as a Mermaid diagram (its first line names a diagram kind, as Excalidraw checks). */
export function looksLikeMermaid(text: string): boolean {
  return /^\s*(?:%%.*\n\s*)*(?:flowchart|graph|sequenceDiagram|classDiagram|stateDiagram|erDiagram|gantt|pie|journey|mindmap|timeline|gitGraph|quadrantChart|xychart|block|sankey|requirementDiagram|C4\w*)\b/u.test(
    text
  )
}

/**
 * Mermaid as a drawing renders it (a model's answer or pasted text — untrusted either way): Mermaid draws it in the
 * page to measure it, so nothing in it may load or run — no HTML tags but line breaks (an `<img>` in a label would be
 * fetched), no `click` / `href` lines, no `%%{init}%%` directives, no CSS `url(…)` in styles.
 */
export function safeMermaid(text: string): string {
  return text
    .replaceAll(/%%\{[\s\S]*?\}%%/gu, '')
    .split('\n')
    .filter((line) => !/^\s*(?:click|href)\b/iu.test(line))
    .join('\n')
    .replaceAll(/<(?!br\s*\/?>)\/?[a-z][^>]*>/giu, '')
    .replaceAll(/url\s*\(/giu, '')
    .trim()
}

type PastedData = { elements?: unknown; files?: unknown; text?: unknown }

/**
 * Pasted content, made what a stored drawing may hold before Excalidraw takes it (its `onPaste`, which may change it): elements as `storedElements`
 * keeps them, pictures only as data, Mermaid with nothing that loads (`safeMermaid`). Pictures named by address in
 * pasted HTML never get here — the bundle stops Excalidraw fetching them (`vite-plugin.ts`).
 */
export function checkPaste(data: object): boolean {
  const pasted = data as PastedData
  if (pasted.elements) pasted.elements = storedElements(pasted.elements)
  if (pasted.files)
    pasted.files = inlineFiles(
      pasted.files as Record<string, { dataURL?: unknown; mimeType?: unknown }>
    )
  if (typeof pasted.text === 'string' && looksLikeMermaid(pasted.text)) {
    pasted.text = safeMermaid(pasted.text)
  }
  return true
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
