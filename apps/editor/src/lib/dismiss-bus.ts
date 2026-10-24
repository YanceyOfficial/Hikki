/**
 * The dismiss bus of the editor's popups (components/floating.tsx's `FloatingLayer` joins it with `onDismiss`): plain
 * TypeScript, so the bridge can dismiss every layer as a page loads without importing a component.
 */

/** What the bus needs of a layer: where it is (presses inside it don't dismiss it) and how to dismiss it. */
export type DismissibleLayer = {
  readonly element: HTMLElement
  dismiss(reason: DismissReason): void
}

/**
 * The open layers, newest last. One pair of document listeners serves them all: Escape and a press outside
 * every open layer dismiss the newest one (its own `onDismiss` decides what that means — close the menu, cancel
 * the panel). So every popup closes the same way, and a press on something else closes what was open before
 * it opens anything new.
 */
const openLayers: DismissibleLayer[] = []

/**
 * Why a layer is dismissed: Escape, a press outside it, or `all` — the page it belongs to is going away
 * (`dismissAllLayers`). Its `onDismiss` may answer `'keep'` to stay open (Escape closing a submenu first).
 */
export type DismissReason = 'escape' | 'press' | 'all'

function dismissOnPress(event: PointerEvent): void {
  const top = openLayers.at(-1)
  if (!top || openLayers.some((layer) => layer.element.contains(event.target as Node))) return
  top.dismiss('press')
}

function dismissOnEscape(event: KeyboardEvent): void {
  if (event.key !== 'Escape') return
  const top = openLayers.at(-1)
  if (!top) return
  event.preventDefault()
  event.stopPropagation()
  top.dismiss('escape')
}

/**
 * Dismisses every open layer, newest first: the page they point into is about to be replaced
 * (`loadDocument`), so a menu or panel must not outlive it and act on the next page.
 */
export function dismissAllLayers(): void {
  for (const layer of openLayers.toReversed()) layer.dismiss('all')
}

export function register(layer: DismissibleLayer): void {
  if (openLayers.length === 0) {
    document.addEventListener('pointerdown', dismissOnPress, true)
    document.addEventListener('keydown', dismissOnEscape, true)
  }
  openLayers.push(layer)
}

export function unregister(layer: DismissibleLayer): void {
  const index = openLayers.indexOf(layer)
  if (index >= 0) openLayers.splice(index, 1)
  if (openLayers.length === 0) {
    document.removeEventListener('pointerdown', dismissOnPress, true)
    document.removeEventListener('keydown', dismissOnEscape, true)
  }
}

/** The layers the bus is managing right now (tests). */
export const openFloatingLayers = (): readonly DismissibleLayer[] => openLayers
