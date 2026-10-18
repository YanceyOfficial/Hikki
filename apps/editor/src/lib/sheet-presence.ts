/**
 * Whether one of the page's bottom sheets is open (cover, icon, comment): the bridge tells the native side, whose
 * bars beside the page (an iPhone Duo's vertical bar) step aside meanwhile, so a sheet can have the whole width.
 * Counted, so one sheet closing as another opens never reads as "none open".
 */
let open = 0
const listeners = new Set<(open: boolean) => void>()

export function sheetPresence(listener: (open: boolean) => void): () => void {
  listeners.add(listener)
  return () => {
    listeners.delete(listener)
  }
}

/** A sheet opened; call the returned function when it closes (once). */
export function sheetOpened(): () => void {
  open += 1
  if (open === 1) for (const listener of listeners) listener(true)
  let closed = false
  return () => {
    if (closed) return
    closed = true
    open -= 1
    if (open === 0) for (const listener of listeners) listener(false)
  }
}
