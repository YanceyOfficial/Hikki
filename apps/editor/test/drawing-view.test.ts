import { describe, expect, it } from 'vitest'

import {
  clampView,
  MAX_ZOOM,
  maxZoom,
  panBy,
  remapView,
  storedView,
  viewTransform,
  zoomAt,
  type DrawingView
} from '../src/lib/drawing-view'

/** Where a point of the block (fractions) lands on the preview (fractions) under `view`. */
const previewPointAt = (view: DrawingView | null, at: { x: number; y: number }) => {
  const v = view ?? { x: 0.5, y: 0.5, zoom: 1 }
  return { x: v.x + (at.x - 0.5) / v.zoom, y: v.y + (at.y - 0.5) / v.zoom }
}

describe("a drawing's view in the page", () => {
  it('zooms around the pointer: the spot under it stays under it', () => {
    const at = { x: 0.3, y: 0.7 }
    const before = previewPointAt(null, at)
    const zoomed = zoomAt(null, 2, at)
    expect(zoomed?.zoom).toBe(2)
    const after = previewPointAt(zoomed, at)
    expect(after.x).toBeCloseTo(before.x)
    expect(after.y).toBeCloseTo(before.y)
    // Again from there, further in.
    const further = zoomAt(zoomed, 3, at)
    expect(previewPointAt(further, at).x).toBeCloseTo(before.x)
  })

  it('is the whole drawing at no zoom, and never past the edges or the furthest zoom', () => {
    expect(zoomAt(null, 1, { x: 0.2, y: 0.2 })).toBeNull()
    expect(zoomAt({ x: 0.5, y: 0.5, zoom: 2 }, 0.5, { x: 0.5, y: 0.5 })).toBeNull()
    expect(clampView({ x: 0.5, y: 0.5, zoom: 1.005 })).toBeNull()
    expect(clampView({ x: 0, y: 1, zoom: 2 })).toEqual({ x: 0.25, y: 0.75, zoom: 2 })
    expect(zoomAt(null, 100, { x: 0.5, y: 0.5 })?.zoom).toBe(MAX_ZOOM)
    expect(zoomAt(null, 100, { x: 0.5, y: 0.5 }, 4)?.zoom).toBe(4)
  })

  it('pans with the pointer, kept inside the preview', () => {
    const view = { x: 0.5, y: 0.5, zoom: 4 }
    // The drawing follows the pointer: dragged right, the spot shown moves left.
    expect(panBy(view, 0.2, 0)).toEqual({ x: 0.45, y: 0.5, zoom: 4 })
    expect(panBy(view, 10, -10)).toEqual({ x: 0.125, y: 0.875, zoom: 4 })
    expect(panBy(null, 0.2, 0)).toBeNull()
  })

  it('places the preview with a transform in its own fractions, so it holds at any width', () => {
    expect(viewTransform(null)).toBe('')
    expect(viewTransform({ x: 0.5, y: 0.5, zoom: 2 })).toBe('translate(-50%, -50%) scale(2)')
    expect(viewTransform({ x: 0.25, y: 0.25, zoom: 2 })).toBe('translate(0%, 0%) scale(2)')
  })

  it('zooms as far as the preview has pixels for, between 4× and 8×', () => {
    // A whiteboard: 5210 pixels shown 708 wide.
    expect(maxZoom(5210, 708)).toBeCloseTo(7.36, 2)
    expect(maxZoom(20_000, 700)).toBe(MAX_ZOOM)
    // A small drawing, shown at half its pixels.
    expect(maxZoom(400, 200)).toBe(4)
    expect(maxZoom(0, 0)).toBe(4)
  })

  it('reads a stored view warily: numbers in range, or none', () => {
    expect(storedView({ x: 0.4, y: 0.6, zoom: 2 })).toEqual({ x: 0.4, y: 0.6, zoom: 2 })
    expect(storedView({ x: 0.4, y: 0.6, zoom: 1e9 })?.zoom).toBe(MAX_ZOOM)
    expect(storedView({ x: -5, y: 0.6, zoom: 2 })?.x).toBe(0.25)
    for (const value of [
      null,
      'x',
      [],
      { x: '0.4', y: 0.6, zoom: 2 },
      { x: 0.4, y: Number.NaN, zoom: 2 },
      { x: 0.4, y: 0.6, zoom: Infinity },
      { x: 0.4, y: 0.6 },
      { x: 0.4, y: 0.6, zoom: 1 }
    ])
      expect(storedView(value)).toBeNull()
  })

  it('follows the drawing into a new preview: the same spot of it at the same size', () => {
    const view = { x: 0.5, y: 0.5, zoom: 2 }
    const before = { x: 0, y: 0, width: 100, height: 100 }
    // Unchanged.
    expect(remapView(view, before, before)).toEqual(view)
    // Grown to the left by its own width: the spot is now right of the middle, and twice as far in.
    expect(remapView(view, before, { x: -100, y: 0, width: 200, height: 100 })).toEqual({
      x: 0.75,
      y: 0.5,
      zoom: 4
    })
    // Shrunk to the spot shown: the whole drawing.
    expect(remapView(view, before, { x: 25, y: 25, width: 50, height: 50 })).toBeNull()
    // Nothing to go by (an empty drawing before): the view as it was.
    expect(remapView(view, null, before)).toEqual(view)
    expect(remapView(null, before, before)).toBeNull()
  })
})
