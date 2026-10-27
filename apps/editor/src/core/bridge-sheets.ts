import { PALETTE, type PaletteColor } from '../extensions/colors'
import {
  findReplace,
  findSet,
  findStep,
  setNativeFindReporter,
  type FindOptions
} from '../extensions/find'
import { bffURL } from '../lib/bff'
import { setDateSheetOpener, type DateSheetChange } from '../lib/date-sheet'
import { localMoment } from '../lib/dates'
import {
  setIconSheetOpener,
  type IconSheetHandlers,
  type IconSheetRequest
} from '../lib/icon-sheet'
import {
  setMathSheetOpener,
  type MathSheetHandlers,
  type MathSheetRequest
} from '../lib/math-sheet'
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
  /** The formula whose native sheet is open (`mathSheet`) and what its typing and answer do. */
  private mathSheet: { id: string; handlers: MathSheetHandlers } | null = null

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

  // MARK: Find (a native bar)

  /** `window.hikki.setNativeFind`: the native side draws the find bar itself and gets the search's state
   * (`findState`) as it changes; the page's own panel stays shut. */
  setNativeFind(on: boolean): void {
    setNativeFindReporter(
      on
        ? (state) => {
            const { docId } = this.context.page.get()
            if (docId) void this.context.send({ type: 'findState', docId, ...state })
          }
        : null
    )
  }

  /** `window.hikki.findSet`: the bar's term, replacement and options. */
  findSet(options: FindOptions): boolean {
    const editor = this.context.editor()
    if (!editor) return false
    findSet(editor, options)
    return true
  }

  /** `window.hikki.findStep`: the next (1) or previous (-1) match. */
  findStep(direction: number): boolean {
    const editor = this.context.editor()
    if (!editor) return false
    findStep(editor, direction < 0 ? -1 : 1)
    return true
  }

  /** `window.hikki.findReplace`: the current match replaced, or all of them (an edit; refused on a locked page). */
  findReplace(all: boolean): boolean {
    const editor = this.context.editor()
    if (!editor || this.context.frozen()) return false
    findReplace(editor, all)
    return true
  }

  // MARK: Formulas (a native sheet)

  /** `window.hikki.setNativeMath`: the native side edits formulas in a sheet of its own. */
  setNativeMath(on: boolean): void {
    setMathSheetOpener(on ? (request, handlers) => this.requestMathSheet(request, handlers) : null)
    if (!on) this.mathSheet = null
  }

  private requestMathSheet(request: MathSheetRequest, handlers: MathSheetHandlers): boolean {
    const { docId } = this.context.page.get()
    if (!docId || this.context.frozen()) return true
    const id = crypto.randomUUID()
    this.mathSheet = { id, handlers }
    void this.context.send({
      type: 'mathSheet',
      docId,
      id,
      latex: request.latex,
      kind: request.kind
    })
    return true
  }

  /** `window.hikki.previewMath`: the formula as typed in the sheet, shown in the page meanwhile. */
  previewMath(id: string, latex: string): boolean {
    if (this.mathSheet?.id !== id || this.context.frozen()) return false
    this.mathSheet.handlers.onPreview(latex)
    return true
  }

  /** `window.hikki.applyMath`: the sheet's end for the opening `id` names — the formula's text (empty: removed), or
   * null for Cancel. Returns whether it was taken (still that opening, the page not locked). */
  applyMath(id: string, latex: string | null): boolean {
    if (this.mathSheet?.id !== id || this.context.frozen()) return false
    const { handlers } = this.mathSheet
    this.mathSheet = null
    if (latex === null) handlers.onCancel()
    else handlers.onDone(latex)
    return true
  }
}
