import type { Editor } from '@tiptap/core'
import type { Transaction } from '@tiptap/pm/state'

import {
  blockThreadRanges,
  commentRanges,
  commentsState,
  type ThreadItem
} from '../extensions/comments'
import { LAYOUT } from '../generated/layout'

/**
 * Where comments go in the page, measured: margin cards level with their passages in a wide window, count badges
 * by their blocks in a narrow one (components/comments.tsx draws them). Plain logic over the editor's view.
 */

/** Card width in the margin, and the room the margin needs beside the text to hold one. */
export const CARD = LAYOUT.commentCard
const GAP = LAYOUT.commentGap
/** The room the outline rail's hover strip keeps at the window's right edge (`editor/src/page/outline.tsx`). */
const RAIL = LAYOUT.outlineRail

/** A thread anchored in the page, measured against the text column (the layer's box). */
export type Anchor = {
  thread: ThreadItem
  /** Top and bottom of the passage, and its first line's left edge, in the column's coordinates. */
  top: number
  bottom: number
  left: number
  /**
   * Which top-level block holds it, by index (threads in one block share a badge) — not its position, which every
   * keystroke before it moves: a layout that is the same as the last one draws nothing.
   */
  block: number
  blockTop: number
}

export type Layout = {
  wide: boolean
  /** Where margin cards start (wide) or badges sit (narrow), from the column's left edge. */
  marginLeft: number
  anchors: Anchor[]
  active: string | null
  draft: { id: string; top: number; bottom: number; left: number; quote: string } | null
}

/** What of the comments plugin's state the layout depends on, besides positions. */
function commentsKey(editor: Editor): unknown[] {
  const plugin = editor.isDestroyed ? undefined : commentsState(editor.state)
  return [plugin?.threads, plugin?.active, plugin?.draft?.id]
}

export function layoutStore(editor: Editor, column: HTMLElement) {
  let layout: Layout | null = null
  let key = ''
  let frame = 0
  let seen = commentsKey(editor)
  const listeners = new Set<() => void>()
  const compute = (): Layout => {
    // Nothing to place (most pages): no layout is read at all.
    if (!hasPassages(editor)) return EMPTY_LAYOUT
    return measure(editor, column)
  }
  const update = () => {
    if (frame) cancelAnimationFrame(frame)
    frame = 0
    const next = compute()
    const nextKey = JSON.stringify(next, (k, v) =>
      k === 'thread' ? `${v.id}:${v.comments.length}:${v.resolved}` : v
    )
    if (nextKey === key) return
    key = nextKey
    layout = next
    for (const notify of listeners) notify()
  }
  const later = () => {
    frame ||= requestAnimationFrame(update)
  }
  const onTransaction = ({ transaction }: { transaction: Transaction }) => {
    const now = commentsKey(editor)
    if (now.some((value, i) => value !== seen[i])) {
      seen = now
      update()
    } else if (transaction.docChanged) later()
  }
  return {
    get: (): Layout => {
      if (!layout) update()
      return layout ?? EMPTY_LAYOUT
    },
    subscribe: (notify: () => void) => {
      listeners.add(notify)
      if (listeners.size === 1) {
        editor.on('transaction', onTransaction)
        window.addEventListener('resize', update)
        column.addEventListener('hk-relayout', update)
      }
      return () => {
        listeners.delete(notify)
        if (listeners.size > 0) return
        editor.off('transaction', onTransaction)
        window.removeEventListener('resize', update)
        column.removeEventListener('hk-relayout', update)
        if (frame) cancelAnimationFrame(frame)
        frame = 0
      }
    }
  }
}

/**
 * Where comments go beside text ending at `textRight` in a window `viewport` wide, never under the outline rail:
 * cards in the margin when one fits (`wide`), else a badge just right of the text, or just inside it when even that
 * has no room. `offset` is from the text's right edge.
 */
export function marginPlacement(
  viewport: number,
  textRight: number
): { wide: boolean; offset: number } {
  const room = viewport - textRight
  if (room >= CARD + GAP + RAIL) return { wide: true, offset: GAP }
  return { wide: false, offset: room >= 56 + RAIL ? 12 : -44 }
}

const EMPTY_LAYOUT: Layout = { wide: false, marginLeft: 0, anchors: [], active: null, draft: null }

/** Whether the page shows anything of comments: a draft, or an open thread's marked passage. */
function hasPassages(editor: Editor): boolean {
  if (editor.isDestroyed) return false
  const plugin = commentsState(editor.state)
  if (!plugin) return false
  if (plugin.draft) return true
  for (const id of commentRanges(editor.state.doc).keys()) {
    if (plugin.threads.get(id)?.resolved === false) return true
  }
  for (const id of blockThreadRanges(editor.state.doc, plugin.threads.values()).keys()) {
    if (plugin.threads.get(id)?.resolved === false) return true
  }
  return false
}

/** A block's box in the window (null when it isn't drawn). */
function blockRect(editor: Editor, pos: number): DOMRect | null {
  try {
    const dom = editor.view.nodeDOM(pos)
    return dom instanceof HTMLElement ? dom.getBoundingClientRect() : null
  } catch {
    return null
  }
}

/** The top-level block holding `pos`. */
function topBlock(editor: Editor, pos: number): number {
  const $pos = editor.state.doc.resolve(pos)
  return $pos.depth > 0 ? $pos.before(1) : pos
}

function measure(editor: Editor, column: HTMLElement): Layout {
  const plugin = commentsState(editor.state)
  if (editor.isDestroyed || !plugin) return EMPTY_LAYOUT
  const view = editor.view
  const columnRect = column.getBoundingClientRect()
  const text = view.dom.getBoundingClientRect()
  const { wide, offset } = marginPlacement(window.innerWidth, text.right)
  const at = (pos: number) => {
    try {
      return view.coordsAtPos(Math.min(pos, editor.state.doc.content.size))
    } catch {
      return null
    }
  }
  const anchors: Anchor[] = []
  for (const [id, ranges] of commentRanges(editor.state.doc)) {
    const thread = plugin.threads.get(id)
    const first = ranges[0]
    if (!thread || thread.resolved || !first) continue
    const start = at(first.from)
    const end = at(ranges.at(-1)!.to)
    const $pos = editor.state.doc.resolve(first.from)
    const block = $pos.depth > 0 ? $pos.before(1) : 0
    const blockStart = at(block + 1)
    if (!start || !end || !blockStart) continue
    anchors.push({
      thread,
      top: start.top - columnRect.top,
      bottom: end.bottom - columnRect.top,
      left: start.left - columnRect.left,
      block: $pos.index(0),
      blockTop: blockStart.top - columnRect.top
    })
  }
  // Threads on whole blocks (an image, an embed): level with the block's top.
  for (const [id, range] of blockThreadRanges(editor.state.doc, plugin.threads.values())) {
    const thread = plugin.threads.get(id)
    if (!thread || thread.resolved) continue
    const rect = blockRect(editor, range.from)
    const block = topBlock(editor, range.from)
    const outer = block === range.from ? rect : blockRect(editor, block)
    if (!rect || !outer) continue
    anchors.push({
      thread,
      top: rect.top - columnRect.top,
      bottom: rect.bottom - columnRect.top,
      left: rect.left - columnRect.left,
      block: editor.state.doc.resolve(range.from).index(0),
      blockTop: outer.top - columnRect.top
    })
  }
  anchors.sort((a, b) => a.top - b.top)
  let draft: Layout['draft'] = null
  const blockDraft = plugin.draft?.blockId ? plugin.draft : null
  const rect = blockDraft ? blockRect(editor, blockDraft.from) : null
  if (blockDraft && rect) {
    draft = {
      id: blockDraft.id,
      top: rect.top - columnRect.top,
      bottom: rect.bottom - columnRect.top,
      left: rect.left - columnRect.left,
      quote: blockDraft.quote ?? ''
    }
  } else if (plugin.draft && !blockDraft) {
    const start = at(plugin.draft.from)
    const end = at(plugin.draft.to)
    if (start && end)
      draft = {
        id: plugin.draft.id,
        top: start.top - columnRect.top,
        bottom: end.bottom - columnRect.top,
        left: start.left - columnRect.left,
        quote: editor.state.doc.textBetween(plugin.draft.from, plugin.draft.to, ' ').slice(0, 200)
      }
  }
  return {
    wide,
    // Narrow with no margin at all (a phone's slim one): the badge sits just inside the text's right edge.
    marginLeft: text.right - columnRect.left + offset,
    anchors,
    active: plugin.active,
    draft
  }
}
