import type { Editor } from '@tiptap/core'

import { openTogglesAround } from '../extensions/toggle'
import type { BridgeContext } from './bridge-types'
import { activeHeadingIndex, collectHeadings, outlineItems, sameOutline } from './headings'

/** Where a heading counts as reached: this far below the toolbar (the top of the reading area). */
const ACTIVE_LINE = 96

/**
 * The page's place: where it is scrolled (`scroll`, so a tab comes back to it), its outline in the page state, and
 * the heading the reader is in (`activeHeading`, a scroll-spy — or the heading an outline jumped to, until the reader
 * scrolls by themselves).
 */
export class OutlineSpy {
  private scrollTimer: ReturnType<typeof setTimeout> | null = null
  /** A heading jumped to from an outline: marked until the reader scrolls (wheel, touch, keys) by themselves. */
  private pinnedHeading: number | null = null
  /** The last id sent as `activeHeading` (the native inspector follows it). */
  private lastActiveHeading: string | null | undefined = undefined
  private activeHeadingFrame = 0

  constructor(private readonly context: BridgeContext) {
    // The heading the reader is in follows the scroll (once a frame at most).
    let queued = false
    window.addEventListener(
      'scroll',
      () => {
        if (queued) return
        queued = true
        requestAnimationFrame(() => {
          queued = false
          this.updateActiveHeading()
          this.reportScroll()
        })
      },
      { passive: true }
    )
    // The reader scrolls by themselves: the scroll-spy takes over from a jump.
    const release = () => {
      this.pinnedHeading = null
    }
    for (const type of ['wheel', 'touchmove', 'keydown'] as const) {
      window.addEventListener(type, release, { passive: true, capture: true })
    }
  }

  /** Where the page is scrolled, at most every 250 ms (the last position always goes out). */
  private reportScroll(): void {
    if (this.scrollTimer) return
    this.scrollTimer = setTimeout(() => this.sendScroll(), 250)
  }

  /** Before another page replaces this one: where it was scrolled, if that hasn't gone out yet. */
  flushScroll(): void {
    if (this.scrollTimer) this.sendScroll()
  }

  /** Sends where the open page is scrolled now (also before another page replaces it: its last place counts). */
  private sendScroll(): void {
    if (this.scrollTimer) clearTimeout(this.scrollTimer)
    this.scrollTimer = null
    const { docId } = this.context.page.get()
    if (!docId) return
    const top = Math.round((document.scrollingElement ?? document.documentElement).scrollTop)
    void this.context.send({ type: 'scroll', docId, top })
  }

  /**
   * A tab shown again: back to where it was. At once — the native side calls it in the same turn as `loadDocument`, so
   * no frame of the page at its top is painted first (that jump was a flash on every tab switch) — and once more after
   * two frames, when what laid out late (node views, pictures) left it short of the place.
   */
  restoreScroll(top: number): void {
    const target = Math.max(0, top)
    const scroll = () => window.scrollTo({ top: target, left: 0, behavior: 'instant' })
    scroll()
    requestAnimationFrame(() =>
      requestAnimationFrame(() => {
        const scroller = document.scrollingElement ?? document.documentElement
        if (Math.abs(scroller.scrollTop - target) > 1) scroll()
      })
    )
  }

  /** A page just loaded: nothing marked or sent for it yet; its heading measured once it has laid out. */
  pageLoaded(): void {
    this.lastActiveHeading = undefined
    this.pinnedHeading = null
    requestAnimationFrame(() => this.updateActiveHeading())
  }

  /**
   * Which heading the reader is in: the last one whose top has passed a line a little below the toolbar, or the last
   * once scrolled to the end. Kept in the page state (the rail) and sent to the native inspector when it changes.
   */
  private updateActiveHeading(): void {
    const editor = this.context.editor()
    const { page } = this.context
    const { docId } = page.get()
    if (!editor || !docId) return
    const headings = collectHeadings(editor)
    const tops = headings.map((h) => {
      const dom = editor.view.nodeDOM(h.pos)
      return dom instanceof HTMLElement ? dom.getBoundingClientRect().top : Number.POSITIVE_INFINITY
    })
    const inset =
      Number.parseFloat(
        getComputedStyle(document.documentElement).getPropertyValue('--hk-inset-top')
      ) || 0
    const scroller = document.scrollingElement ?? document.documentElement
    const atBottom =
      scroller.scrollTop > 0 && scroller.scrollTop + window.innerHeight >= scroller.scrollHeight - 2
    const index =
      this.pinnedHeading !== null && this.pinnedHeading < headings.length
        ? this.pinnedHeading
        : activeHeadingIndex(tops, inset + ACTIVE_LINE, atBottom)
    if (index !== page.get().activeHeading) page.set({ activeHeading: index })
    const id = index >= 0 ? (headings[index]?.id ?? null) : null
    if (id === this.lastActiveHeading) return
    this.lastActiveHeading = id
    void this.context.send({ type: 'activeHeading', docId, id })
  }

  /** The page's hover rail: to the heading at this place in the outline (where it is now, looked up again). */
  scrollToHeading(index: number): void {
    const editor = this.context.editor()
    const heading = editor ? collectHeadings(editor)[index] : undefined
    if (!editor || !heading) return
    openTogglesAround(editor, heading.pos)
    const dom = editor.view.nodeDOM(heading.pos)
    if (dom instanceof HTMLElement) dom.scrollIntoView({ behavior: 'smooth', block: 'start' })
    editor.commands.setTextSelection(heading.pos + 1)
    // The heading jumped to is the one marked (a short page can't scroll it up to the line), until the reader scrolls.
    this.pinnedHeading = index
    this.updateActiveHeading()
  }

  /** The inspector's outline: to a heading by its block id, as the rail does (`scrollToHeading`). */
  jumpToHeading(id: string): boolean {
    const editor = this.context.editor()
    if (!editor) return false
    const index = collectHeadings(editor).findIndex((h) => h.id === id)
    if (index < 0) return false
    this.scrollToHeading(index)
    return true
  }

  /** The outline goes to the page state only when it reads differently (its readers re-render on a change). */
  refreshOutline(editor: Editor): void {
    const headings = outlineItems(editor)
    if (!sameOutline(headings, this.context.page.get().headings))
      this.context.page.set({ headings })
  }

  /** After an edit: the heading the reader is in, measured once a frame after the browser's own layout. */
  scheduleActiveHeading(): void {
    if (this.activeHeadingFrame) return
    this.activeHeadingFrame = requestAnimationFrame(() => {
      this.activeHeadingFrame = 0
      this.updateActiveHeading()
    })
  }

  /** The native inspector shows the outline itself: the page's hover rail steps aside meanwhile. */
  setOutlineRail(visible: boolean): void {
    this.context.page.set({ railHidden: !visible })
  }
}
