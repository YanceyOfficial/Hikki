import { PALETTE, type PaletteColor } from '../extensions/colors'
import { bffURL } from '../lib/bff'
import { setDateSheetOpener, type DateSheetChange } from '../lib/date-sheet'
import { localMoment } from '../lib/dates'
import {
  setIconSheetOpener,
  type IconSheetHandlers,
  type IconSheetRequest
} from '../lib/icon-sheet'
import type { BridgeContext } from './bridge-types'

/**
 * The page's sheets — cover, icon pickers, date chips — where the native side draws them (touch screens): the page
 * asks for one (`coverSheet`, `iconSheet`, `dateSheet`) and takes its answer (`applyCover` lives on the bridge,
 * `applyIcon`, `applyIconColor`, `applyDate` here), each answer checked against the opening it belongs to.
 */
export class SheetsBridge {
  /** Listeners for `editCover` (the page header opens its cover sheet). */
  private readonly coverRequests = new Set<() => void>()
  /** The phone draws the cover's sheet natively (`setNativeCover`): the page asks for it instead of opening its own. */
  private nativeCover = false
  /** The sheet opened last (`iconSheet`) and what its picks do; a newer one replaces it. */
  private iconSheet: { id: string; handlers: IconSheetHandlers } | null = null
  /** The date chip whose native sheet is open (`dateSheet`) and what its answer does; a newer one replaces it. */
  private dateSheet: { id: string; onChange: (change: DateSheetChange) => void } | null = null

  constructor(private readonly context: BridgeContext) {}

  onCoverRequest(listener: () => void): () => void {
    this.coverRequests.add(listener)
    return () => {
      this.coverRequests.delete(listener)
    }
  }

  /** `window.hikki.editCover`: the page ⋯ menu's Cover… — the cover's sheet opens (false on a locked page). */
  editCover(): boolean {
    if (!this.context.editor() || this.context.frozen() || this.context.page.get().readOnly)
      return false
    for (const listener of this.coverRequests) listener()
    return this.coverRequests.size > 0
  }

  /** `window.hikki.setNativeCover`: the native side shows the cover's sheet itself. */
  setNativeCover(on: boolean): void {
    this.nativeCover = on
  }

  /** The cover's sheet, where the native side draws it: asks for it (`coverSheet`) and returns true; false means the
   * page header opens its own. */
  requestCoverSheet(mode: 'actions' | 'picker'): boolean {
    if (!this.nativeCover) return false
    const { docId, cover } = this.context.page.get()
    if (docId && !this.context.frozen())
      void this.context.send({ type: 'coverSheet', docId, cover, mode, bff: bffURL() })
    return true
  }

  /** `window.hikki.setNativeIcons`: the native side shows the page's and callouts' icon pickers itself. */
  setNativeIcons(on: boolean): void {
    setIconSheetOpener(on ? (request, handlers) => this.requestIconSheet(request, handlers) : null)
    if (!on) this.iconSheet = null
  }

  private requestIconSheet(request: IconSheetRequest, handlers: IconSheetHandlers): boolean {
    const { docId } = this.context.page.get()
    if (!docId || this.context.frozen()) return true
    const id = crypto.randomUUID()
    this.iconSheet = { id, handlers }
    void this.context.send({
      type: 'iconSheet',
      docId,
      id,
      kind: request.kind,
      icon: request.icon,
      color: request.kind === 'callout' ? request.color : null
    })
    return true
  }

  /** `window.hikki.applyIcon`: the native sheet's emoji (null: Remove) for the opening `id` names. Returns whether it
   * was taken (still that opening, the page not locked). */
  applyIcon(id: string, icon: string | null): boolean {
    if (this.iconSheet?.id !== id || this.context.frozen()) return false
    this.iconSheet.handlers.onIcon(icon)
    return true
  }

  /** `window.hikki.applyIconColor`: a callout's background colour from the native sheet (null: the default). */
  applyIconColor(id: string, color: string | null): boolean {
    const onColor = this.iconSheet?.id === id ? this.iconSheet.handlers.onColor : undefined
    if (!onColor || this.context.frozen()) return false
    if (color !== null && !(PALETTE as readonly string[]).includes(color)) return false
    onColor(color as PaletteColor | null)
    return true
  }

  /** `window.hikki.setNativeDates`: the native side edits date chips in a sheet of its own. */
  setNativeDates(on: boolean): void {
    setDateSheetOpener(
      on
        ? (attrs, onChange) => {
            const { docId } = this.context.page.get()
            if (!docId || this.context.frozen()) return true
            const id = crypto.randomUUID()
            this.dateSheet = { id, onChange }
            void this.context.send({
              type: 'dateSheet',
              docId,
              id,
              date: attrs.date,
              time: attrs.time,
              remind: attrs.remind,
              done: attrs.done
            })
            return true
          }
        : null
    )
    if (!on) this.dateSheet = null
  }

  /** `window.hikki.applyDate`: the native sheet's answer for the opening `id` names — the chip's new day, time,
   * reminder and done, or null to remove it. Returns whether it was taken (still that opening, a well-formed date,
   * the page not locked). */
  applyDate(id: string, change: DateSheetChange): boolean {
    if (this.dateSheet?.id !== id || this.context.frozen()) return false
    if (change !== null && !localMoment(change.date, change.time)) return false
    const { onChange } = this.dateSheet
    this.dateSheet = null
    onChange(change)
    return true
  }
}
