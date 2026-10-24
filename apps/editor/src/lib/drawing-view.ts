import type { DrawingFrame } from '@hikki/excalidraw'

/**
 * The part of a drawing's preview the page shows (`view` on a drawing block): the point at the middle of the block,
 * as a fraction of the preview's width and height (0–1), and how far in — 1 is the whole drawing, fitted to the
 * column as it always was. No view (null) is that whole drawing.
 */
export type DrawingView = { x: number; y: number; zoom: number }

/** The furthest in a stored view goes; how far a preview zooms in the page also depends on its pixels (`maxZoom`). */
export const MAX_ZOOM = 8
/** The least the zoom buttons allow before a preview runs out of pixels (`maxZoom`). */
const MIN_MAX_ZOOM = 4
/** A zoom this close to the whole drawing is the whole drawing. */
const FITTED = 1.01

const clamp = (value: number, min: number, max: number) => Math.min(max, Math.max(min, value))

/**
 * How far into a preview `natural` pixels wide, fitted `fit` CSS pixels wide in the page, a reader may zoom: until one
 * of its pixels covers a CSS pixel (a whiteboard's preview holds many more than the column shows), at least 4× and
 * at most `MAX_ZOOM`.
 */
export function maxZoom(natural: number, fit: number): number {
  if (!(natural > 0 && fit > 0)) return MIN_MAX_ZOOM
  return clamp(natural / fit, MIN_MAX_ZOOM, MAX_ZOOM)
}

/**
 * A view kept inside the preview: zoomed between the whole drawing and `max`, its middle where the preview still
 * covers the block (no empty margin past an edge). The whole drawing is null.
 */
export function clampView(view: DrawingView | null, max = MAX_ZOOM): DrawingView | null {
  if (!view) return null
  const zoom = clamp(view.zoom, 1, max)
  if (zoom < FITTED) return null
  const half = 0.5 / zoom
  return { x: clamp(view.x, half, 1 - half), y: clamp(view.y, half, 1 - half), zoom }
}

/** A view as stored (synced, imported, pasted — it can hold anything): numbers in range, or null. */
export function storedView(value: unknown): DrawingView | null {
  if (typeof value !== 'object' || value === null) return null
  const { x, y, zoom } = value as Record<string, unknown>
  if (![x, y, zoom].every((n) => typeof n === 'number' && Number.isFinite(n))) return null
  return clampView({ x: x as number, y: y as number, zoom: zoom as number })
}

/** Four places: far below a pixel of any preview. */
const round = (n: number) => Math.round(n * 10_000) / 10_000

/** Rounded to what a stored view keeps. */
export function roundView(view: DrawingView | null): DrawingView | null {
  if (!view) return null
  return { x: round(view.x), y: round(view.y), zoom: round(view.zoom) }
}

/**
 * `view` zoomed to `zoom`, keeping the point under `at` (a place in the block, as fractions of its width and height)
 * where it is: zooming follows the pointer, a pinch its fingers.
 */
export function zoomAt(
  view: DrawingView | null,
  zoom: number,
  at: { x: number; y: number },
  max = MAX_ZOOM
): DrawingView | null {
  const from = view ?? { x: 0.5, y: 0.5, zoom: 1 }
  const next = clamp(zoom, 1, max)
  // The preview's point under `at` now, then the middle that puts it there at the new zoom.
  const u = from.x + (at.x - 0.5) / from.zoom
  const v = from.y + (at.y - 0.5) / from.zoom
  return clampView({ x: u - (at.x - 0.5) / next, y: v - (at.y - 0.5) / next, zoom: next }, max)
}

/** `view` moved by `dx`, `dy` (fractions of the block's width and height): the drawing follows the pointer. */
export function panBy(view: DrawingView | null, dx: number, dy: number): DrawingView | null {
  if (!view) return null
  return clampView({ x: view.x - dx / view.zoom, y: view.y - dy / view.zoom, zoom: view.zoom })
}

/**
 * Where the preview sits in its block to show `view`: a CSS transform with its origin at the top left, in fractions
 * of the preview's own box, so it holds at any column width.
 */
export function viewTransform(view: DrawingView | null): string {
  if (!view) return ''
  const tx = 100 * (0.5 - view.x * view.zoom)
  const ty = 100 * (0.5 - view.y * view.zoom)
  return `translate(${tx}%, ${ty}%) scale(${view.zoom})`
}

/** The same view (both whole, or the same spot at the same zoom). */
export function sameView(a: DrawingView | null, b: DrawingView | null): boolean {
  if (!a || !b) return a === b
  return a.x === b.x && a.y === b.y && a.zoom === b.zoom
}

/**
 * A view chosen on a preview showing `from` (a part of the drawing's plane), for a new preview showing `to` — the
 * drawing grew or shrank: the same spot of the drawing at the same size, kept inside the new preview.
 */
export function remapView(
  view: DrawingView | null,
  from: DrawingFrame | null,
  to: DrawingFrame
): DrawingView | null {
  if (!view || !from || !(from.width > 0 && from.height > 0 && to.width > 0 && to.height > 0))
    return view
  const x = (from.x + view.x * from.width - to.x) / to.width
  const y = (from.y + view.y * from.height - to.y) / to.height
  // The same width of the plane across the block: a larger drawing needs more zoom to show it.
  return roundView(clampView({ x, y, zoom: (view.zoom * to.width) / from.width }))
}
