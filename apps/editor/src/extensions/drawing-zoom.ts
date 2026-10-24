import { createRoot, type Root } from 'react-dom/client'

import { renderDrawingZoomControls } from '../components/drawing-zoom-controls'
import { TOUCH } from '../lib/device'
import {
  clampView,
  MAX_ZOOM,
  maxZoom,
  panBy,
  roundView,
  sameView,
  viewTransform,
  zoomAt,
  type DrawingView
} from '../lib/drawing-view'

/** A press that moves less than this (CSS pixels) is a click: it opens the drawing; further, it pans. */
const DRAG_THRESHOLD = 4
/** How far one press of a zoom button (or + / −) goes. */
const ZOOM_STEP = 1.5
/** A ⌘/Ctrl-wheel view is stored once the wheel has rested this long. */
const WHEEL_REST_MS = 400
const MIDDLE = { x: 0.5, y: 0.5 }

type Point = { x: number; y: number }

export type PreviewZoomHost = {
  /** Keeps the view in the block (one change, out of the page's undo, saved). */
  store: (view: DrawingView | null) => void
  /** Whether the view is the drawing's to keep: not on a locked page, nor where drawings are only looked at. */
  canStore: () => boolean
}

/**
 * A drawing's preview zoomed and panned in place in the page (`extensions/drawing.ts`; the view's arithmetic is
 * `lib/drawing-view.ts`): ⌘/Ctrl + wheel and a trackpad pinch (a Ctrl-wheel in Chromium, gesture events in WebKit)
 * zoom around the pointer, a mouse drag pans once zoomed, two fingers pinch and pan on a touch screen — a plain wheel
 * and a one-finger drag still scroll the page — and the controls over the block zoom in, out, and back to the whole
 * drawing. Each gesture ends in one stored view, where the host can store it; elsewhere the view is the reader's.
 */
export class PreviewZoom {
  /** What shows now, and what the block stores. */
  private view: DrawingView | null
  private stored: DrawingView | null
  /** The preview's box (it clips the zoomed picture), its picture, and the controls' React root. */
  private frame: HTMLElement | null = null
  private img: HTMLImageElement | null = null
  private controls: { element: HTMLElement; root: Root } | null = null
  /** A press on a zoomed preview: where it started and the view then; `moved` once it pans. */
  private press: { id: number; at: Point; view: DrawingView; moved: boolean } | null = null
  /** Two fingers on the preview: their middle and spread as they landed, and the view then. */
  private pinch: { at: Point; spread: number; view: DrawingView | null } | null = null
  /** A WebKit gesture (a trackpad pinch on the Mac): the view as it began and the point it zooms around. */
  private gesture: { at: Point; view: DrawingView | null } | null = null
  /** The click that ends a pan or a pinch opens nothing. */
  private swallowClick = false
  private hovered = false
  private wheelTimer: ReturnType<typeof setTimeout> | null = null

  constructor(
    private readonly block: HTMLElement,
    stored: DrawingView | null,
    private readonly host: PreviewZoomHost
  ) {
    this.stored = stored
    this.view = stored
    block.addEventListener('pointerenter', (event) => {
      if (event.pointerType !== 'touch') this.setHovered(true)
    })
    block.addEventListener('pointerleave', () => this.setHovered(false))
    block.addEventListener('focusin', () => this.showControls())
    block.addEventListener('focusout', () => this.showControls())
    // A zoomed preview pans where the block would otherwise be dragged.
    block.addEventListener('dragstart', (event) => {
      if (this.view) event.preventDefault()
    })
  }

  /** Takes a fresh render of the block's preview: its box, its picture, and the element the controls go in. */
  attach(frame: HTMLElement, img: HTMLImageElement, controls: HTMLElement): void {
    this.detach()
    this.frame = frame
    this.img = img
    controls.dataset.open = 'false'
    this.controls = { element: controls, root: createRoot(controls) }
    frame.addEventListener('wheel', this.wheel, { passive: false })
    frame.addEventListener('pointerdown', this.pointerdown)
    frame.addEventListener('pointermove', this.pointermove)
    frame.addEventListener('pointerup', this.pointerup)
    frame.addEventListener('pointercancel', this.pointerup)
    frame.addEventListener('touchstart', this.touchstart, { passive: true })
    frame.addEventListener('touchmove', this.touchmove, { passive: false })
    frame.addEventListener('touchend', this.touchend)
    frame.addEventListener('touchcancel', this.touchend)
    frame.addEventListener('gesturestart', this.gesturestart)
    frame.addEventListener('gesturechange', this.gesturechange)
    frame.addEventListener('gestureend', this.gestureend)
    // How far it may zoom depends on its pixels: a stored view past that is held to it once they are known.
    img.addEventListener('load', () => this.setView(this.view))
    this.apply()
  }

  /** The block shows no preview (an empty drawing, or before a re-render). */
  detach(): void {
    const root = this.controls?.root
    this.controls = null
    this.frame = null
    this.img = null
    this.press = null
    this.pinch = null
    this.gesture = null
    delete this.block.dataset.zoomed
    delete this.block.dataset.panning
    // Not synchronously: a node view can be redrawn while React is rendering.
    if (root) queueMicrotask(() => root.unmount())
  }

  /** The block's stored view changed (another device, Done's view on its new preview, this one's own store). */
  storedChanged(view: DrawingView | null): void {
    if (sameView(view, this.stored)) return
    this.stored = view
    // Unless the reader is zooming this one right now.
    if (!this.busy()) this.setView(view)
  }

  /** The click ending a pan or a pinch: it doesn't open the drawing. */
  takeClick(): boolean {
    const swallow = this.swallowClick
    this.swallowClick = false
    return swallow
  }

  inControls(target: EventTarget | null): boolean {
    return target instanceof Node && this.controls?.element.contains(target) === true
  }

  /** Events the preview handles itself, which ProseMirror leaves alone. */
  stopsEvent(event: Event): boolean {
    if (!this.frame) return false
    if (this.inControls(event.target)) return true
    const { type } = event
    if (type === 'wheel' || type.startsWith('touch') || type.startsWith('gesture')) return true
    // Unzoomed, a press still selects and drags the block.
    return (
      this.view !== null &&
      (type.startsWith('pointer') || type.startsWith('mouse') || type === 'dragstart')
    )
  }

  /** + / = zooms in, − out, 0 back to the whole drawing (the block focused). True when it was one of those. */
  keydown(event: KeyboardEvent): boolean {
    if (!this.img || event.metaKey || event.ctrlKey || event.altKey) return false
    const step = { '+': ZOOM_STEP, '=': ZOOM_STEP, '-': 1 / ZOOM_STEP, '0': 0 }[event.key]
    if (step === undefined) return false
    event.preventDefault()
    if (step === 0) this.setView(null)
    else this.zoomBy(step)
    this.commit()
    return true
  }

  destroy(): void {
    // A wheel's view not stored yet goes with the block (the page is changing under it).
    if (this.wheelTimer) clearTimeout(this.wheelTimer)
    this.wheelTimer = null
    this.detach()
  }

  private busy(): boolean {
    return (
      this.press !== null ||
      this.pinch !== null ||
      this.gesture !== null ||
      this.wheelTimer !== null
    )
  }

  private maxZoom(): number {
    return this.img ? maxZoom(this.img.naturalWidth, this.img.offsetWidth) : MAX_ZOOM
  }

  /** A point of the preview's box as fractions of its width and height. */
  private pointAt(clientX: number, clientY: number): Point {
    const box = this.frame?.getBoundingClientRect()
    const x = box ? (clientX - box.left) / box.width : Number.NaN
    const y = box ? (clientY - box.top) / box.height : Number.NaN
    return Number.isFinite(x) && Number.isFinite(y) ? { x, y } : MIDDLE
  }

  private setView(view: DrawingView | null) {
    this.view = clampView(view, this.maxZoom())
    this.apply()
  }

  private apply() {
    if (!this.img) return
    this.img.style.transform = viewTransform(this.view)
    this.block.dataset.zoomed = String(this.view !== null)
    this.showControls()
  }

  private zoomBy(factor: number, at: Point = MIDDLE) {
    this.setView(zoomAt(this.view, (this.view?.zoom ?? 1) * factor, at, this.maxZoom()))
  }

  /** Stores the view shown, where it is the drawing's to keep. */
  private commit() {
    if (this.wheelTimer) clearTimeout(this.wheelTimer)
    this.wheelTimer = null
    const view = roundView(this.view)
    if (sameView(view, this.stored) || !this.host.canStore()) return
    this.stored = view
    this.host.store(view)
  }

  private setHovered(on: boolean) {
    this.hovered = on
    this.showControls()
  }

  /** The controls show on hover or focus, and while zoomed on a touch screen (the way back to the whole drawing). */
  private showControls() {
    if (!this.controls) return
    const touch = window.matchMedia?.(TOUCH).matches ?? false
    const shown =
      this.hovered || this.block.matches(':focus-within') || (touch && this.view !== null)
    this.controls.element.dataset.open = String(shown)
    renderDrawingZoomControls(this.controls.root, {
      zoom: this.view?.zoom ?? 1,
      max: this.maxZoom(),
      onZoomIn: () => {
        this.zoomBy(ZOOM_STEP)
        this.commit()
      },
      onZoomOut: () => {
        this.zoomBy(1 / ZOOM_STEP)
        this.commit()
      },
      onFit: () => {
        this.setView(null)
        this.commit()
      }
    })
  }

  private wheel = (event: WheelEvent) => {
    // A plain wheel scrolls the page; ⌘/Ctrl (a trackpad pinch is a Ctrl-wheel) zooms. WebKit's gesture events
    // carry the Mac's pinch on their own.
    if (!(event.ctrlKey || event.metaKey) || this.gesture) return
    event.preventDefault()
    const lines = event.deltaMode === 1 ? 16 : 1
    const delta = Math.max(-50, Math.min(50, event.deltaY * lines))
    this.zoomBy(Math.exp(-delta * 0.01), this.pointAt(event.clientX, event.clientY))
    if (this.wheelTimer) clearTimeout(this.wheelTimer)
    this.wheelTimer = setTimeout(() => this.commit(), WHEEL_REST_MS)
  }

  private pointerdown = (event: PointerEvent) => {
    // Touch pans with two fingers (one scrolls the page); a mouse or pen drags a zoomed preview.
    this.swallowClick = false
    if (!this.view || event.pointerType === 'touch' || event.button !== 0) return
    this.press = {
      id: event.pointerId,
      at: { x: event.clientX, y: event.clientY },
      view: this.view,
      moved: false
    }
  }

  private pointermove = (event: PointerEvent) => {
    const press = this.press
    if (!press || event.pointerId !== press.id || !this.frame) return
    const dx = event.clientX - press.at.x
    const dy = event.clientY - press.at.y
    if (!press.moved) {
      if (Math.hypot(dx, dy) < DRAG_THRESHOLD) return
      press.moved = true
      this.frame.setPointerCapture?.(event.pointerId)
      this.block.dataset.panning = 'true'
    }
    const box = this.frame.getBoundingClientRect()
    if (box.width === 0 || box.height === 0) return
    this.setView(panBy(press.view, dx / box.width, dy / box.height))
  }

  private pointerup = (event: PointerEvent) => {
    const press = this.press
    if (!press || event.pointerId !== press.id) return
    this.press = null
    delete this.block.dataset.panning
    if (!press.moved) return
    this.swallowClick = true
    this.commit()
  }

  private fingers(event: TouchEvent): { at: Point; spread: number } {
    const [a, b] = [event.touches[0], event.touches[1]]
    return {
      at: this.pointAt((a.clientX + b.clientX) / 2, (a.clientY + b.clientY) / 2),
      spread: Math.hypot(a.clientX - b.clientX, a.clientY - b.clientY)
    }
  }

  private touchstart = (event: TouchEvent) => {
    if (event.touches.length !== 2) return
    const { at, spread } = this.fingers(event)
    if (spread > 0) this.pinch = { at, spread, view: this.view }
  }

  private touchmove = (event: TouchEvent) => {
    const pinch = this.pinch
    if (!pinch || event.touches.length < 2) return
    if (event.cancelable) event.preventDefault()
    const { at, spread } = this.fingers(event)
    const zoom = (pinch.view?.zoom ?? 1) * (spread / pinch.spread)
    // The preview's point under the fingers as they landed stays under them: zoomed by the spread, moved with them.
    const zoomed = zoomAt(pinch.view, zoom, pinch.at, this.maxZoom())
    this.setView(panBy(zoomed, at.x - pinch.at.x, at.y - pinch.at.y))
  }

  private touchend = (event: TouchEvent) => {
    if (!this.pinch || event.touches.length >= 2) return
    this.pinch = null
    this.swallowClick = true
    this.commit()
  }

  private gesturestart = (event: Event) => {
    event.preventDefault()
    // On iOS the touches carry the pinch (`touchmove`); a Mac trackpad has only these.
    if (this.pinch) return
    const { clientX, clientY } = event as Event & { clientX?: number; clientY?: number }
    this.gesture = {
      at: clientX === undefined ? MIDDLE : this.pointAt(clientX, clientY ?? 0),
      view: this.view
    }
  }

  private gesturechange = (event: Event) => {
    event.preventDefault()
    const gesture = this.gesture
    const { scale } = event as Event & { scale?: number }
    if (!gesture || typeof scale !== 'number' || !(scale > 0)) return
    const zoom = (gesture.view?.zoom ?? 1) * scale
    this.setView(zoomAt(gesture.view, zoom, gesture.at, this.maxZoom()))
  }

  private gestureend = (event: Event) => {
    event.preventDefault()
    if (!this.gesture) return
    this.gesture = null
    this.commit()
  }
}
