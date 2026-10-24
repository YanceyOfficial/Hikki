import { Extension, Mark, type Editor } from '@tiptap/core'
import type { Node as PMNode } from '@tiptap/pm/model'
import {
  NodeSelection,
  Plugin,
  PluginKey,
  type EditorState,
  type Transaction
} from '@tiptap/pm/state'
import { Decoration, DecorationSet, type EditorView } from '@tiptap/pm/view'

import { renderComments } from '../components/comments'
import { blockKindLabel } from '../core/block-kinds'
import { SAVE_META } from '../core/meta'
import { tiptapShortcut } from '../core/shortcuts'
import type { PageIndexEntry } from './page-links'
import { SelectionMenuKey } from './selection-menu'

/** One comment of a thread (as the native store keeps it; `createdAt` in milliseconds). */
export type CommentItem = {
  id: string
  body: string
  author: string | null
  device: string | null
  createdAt: number
  /** The last edit, or null as written. */
  editedAt?: number | null
}

/**
 * A thread on a passage — its words live natively (`comments/<page id>.json`); the passage carries a `comment` mark —
 * or on a whole block without text of its own (an image, an embed, a file, a formula): `blockId` names it, and `quote`
 * is what the block was called when the thread started.
 */
export type ThreadItem = {
  id: string
  quote: string
  resolved: boolean
  comments: CommentItem[]
  blockId?: string | null
}

/** What comments need from the host (the bridge): writing to the native store, and who is writing. */
export type CommentsHost = {
  /** `blockId`: a thread on a whole block (no passage is marked). */
  create: (threadId: string, quote: string, body: string, blockId?: string) => void
  reply: (threadId: string, body: string) => void
  resolve: (threadId: string, resolved: boolean) => void
  remove: (threadId: string, commentId?: string) => void
  edit: (threadId: string, commentId: string, body: string) => void
  /** Pages for "@" in a comment, and opening one from a mention chip. */
  pages: () => PageIndexEntry[]
  openPage: (pageId: string) => void
  /** A link to the thread (`hikki://page/<page id>#<thread id>`), or null before a page is open. */
  link: (threadId: string) => string | null
  /** This device's name ("Mac", "iPhone"): other devices' comments say where they were written. */
  device: () => string | null
  /** The native side shows an open thread itself (a phone's sheet): the page draws none. */
  nativeThreads?: () => boolean
}

export type CommentsState = {
  threads: Map<string, ThreadItem>
  /** The thread shown open (its reply field), or the draft's id while a new comment is being written. */
  active: string | null
  /** A comment being started on a selection — or on a whole block (`blockId`, its label as `quote`): a highlight
   * only, until it is sent. */
  draft: CommentDraft | null
}

export type CommentDraft = {
  id: string
  from: number
  to: number
  blockId?: string
  quote?: string
}

type Meta =
  | { type: 'threads'; threads: ThreadItem[] }
  | { type: 'active'; id: string | null }
  | { type: 'draft'; draft: CommentsState['draft'] }

export const CommentsKey = new PluginKey<CommentsState>('comments')

/** The passage a thread is about: a mark with the thread's id (marks of different threads may overlap). */
export const CommentMark = Mark.create({
  name: 'comment',
  excludes: '',
  inclusive: false,
  addAttributes() {
    return {
      id: {
        default: null,
        parseHTML: (element) => element.dataset.comment ?? null,
        renderHTML: (attributes) =>
          attributes.id ? { 'data-comment': attributes.id as string } : {}
      }
    }
  },
  parseHTML() {
    return [{ tag: 'span[data-comment]' }]
  },
  renderHTML({ HTMLAttributes }) {
    return ['span', HTMLAttributes, 0]
  }
})

/** Documents are immutable: each one's comment ranges are found once (decorations, the layer and every caret move
 * ask again). */
const rangesByDoc = new WeakMap<
  PMNode,
  ReadonlyMap<string, readonly { from: number; to: number }[]>
>()

/** Where each thread's passage is in the document: its ranges, in order. */
export function commentRanges(
  doc: PMNode
): ReadonlyMap<string, readonly { from: number; to: number }[]> {
  const known = rangesByDoc.get(doc)
  if (known) return known
  const ranges = new Map<string, { from: number; to: number }[]>()
  doc.descendants((node, pos) => {
    if (!node.isText) return true
    for (const mark of node.marks) {
      if (mark.type.name !== 'comment' || typeof mark.attrs.id !== 'string') continue
      const list = ranges.get(mark.attrs.id) ?? []
      const last = list.at(-1)
      if (last && last.to === pos) last.to = pos + node.nodeSize
      else list.push({ from: pos, to: pos + node.nodeSize })
      ranges.set(mark.attrs.id, list)
    }
    return false
  })
  rangesByDoc.set(doc, ranges)
  return ranges
}

/** Each block id's node range, per document (block threads find their block by it). */
const blocksByDoc = new WeakMap<PMNode, ReadonlyMap<string, { from: number; to: number }>>()

function blockRanges(doc: PMNode): ReadonlyMap<string, { from: number; to: number }> {
  const known = blocksByDoc.get(doc)
  if (known) return known
  const ranges = new Map<string, { from: number; to: number }>()
  doc.descendants((node, pos) => {
    const id = node.attrs.id as unknown
    if (node.isBlock && typeof id === 'string' && !ranges.has(id))
      ranges.set(id, { from: pos, to: pos + node.nodeSize })
    return node.isBlock && !node.isTextblock
  })
  blocksByDoc.set(doc, ranges)
  return ranges
}

/** Where each thread on a whole block is: its block's range (threads whose block is gone are left out). */
export function blockThreadRanges(
  doc: PMNode,
  threads: Iterable<ThreadItem>
): Map<string, { from: number; to: number }> {
  const found = new Map<string, { from: number; to: number }>()
  let blocks: ReadonlyMap<string, { from: number; to: number }> | null = null
  for (const thread of threads) {
    if (!thread.blockId) continue
    blocks ??= blockRanges(doc)
    const range = blocks.get(thread.blockId)
    if (range) found.set(thread.id, range)
  }
  return found
}

/** Where a thread is in the page — its passage's first range, or its block — or null. */
export function threadRange(state: EditorState, id: string): { from: number; to: number } | null {
  const passage = commentRanges(state.doc).get(id)?.[0]
  if (passage) return passage
  const thread = commentsState(state)?.threads.get(id)
  return thread ? (blockThreadRanges(state.doc, [thread]).get(id) ?? null) : null
}

/** The open thread on the block at (or around) `pos`, innermost first. */
function blockThreadAt(state: EditorState, pos: number): string | undefined {
  const plugin = commentsState(state)
  if (!plugin) return undefined
  const ids: string[] = []
  const atom = state.doc.nodeAt(pos)
  if (atom?.isBlock && typeof atom.attrs.id === 'string') ids.push(atom.attrs.id)
  const $pos = state.doc.resolve(pos)
  for (let depth = $pos.depth; depth >= 1; depth--) {
    const id = $pos.node(depth).attrs.id as unknown
    if (typeof id === 'string') ids.push(id)
  }
  for (const id of ids) {
    for (const thread of plugin.threads.values())
      if (thread.blockId === id && !thread.resolved) return thread.id
  }
  return undefined
}

/** A block's name for a thread on it: its kind and, for a file or a link, which one ("Image · photo.png"). */
export function blockQuote(node: PMNode, kind: string): string {
  const attrs = node.attrs as Record<string, unknown>
  const detail = [
    attrs.caption,
    attrs.name,
    attrs.title,
    attrs.alt,
    attrs.original,
    attrs.latex
  ].find((value): value is string => typeof value === 'string' && value.trim() !== '')
  return (detail ? `${kind} · ${detail.trim()}` : kind).slice(0, 500)
}

export const commentsState = (state: EditorState): CommentsState | undefined =>
  CommentsKey.getState(state)

const newID = () =>
  globalThis.crypto?.randomUUID?.() ??
  `c-${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`

declare module '@tiptap/core' {
  interface Commands<ReturnType> {
    comments: {
      /** A comment on the selection: a draft highlight and its composer (nothing is stored until it is sent). A
       * selected block without text (an image, an embed) gets a thread on the whole block. */
      commentStart: () => ReturnType
      /** A comment on the whole block at `pos` (it needs a block id), called `quote` in the thread. */
      commentStartBlock: (pos: number, quote: string) => ReturnType
      /** Sends the draft's first comment (marking the passage), or a reply to the open thread. */
      commentSend: (body: string) => ReturnType
      /** Opens a thread (null closes, and drops a draft). */
      commentOpen: (id: string | null) => ReturnType
      commentResolve: (id: string, resolved: boolean) => ReturnType
      /** Deletes a thread: its words natively, its mark here. */
      commentDelete: (id: string) => ReturnType
      /** Deletes one reply (the first comment is the thread: `commentDelete`). */
      commentDeleteReply: (threadId: string, commentId: string) => ReturnType
      /** Rewrites a comment. */
      commentEdit: (threadId: string, commentId: string, body: string) => ReturnType
    }
  }
}

/** Comments on passages (Notion's): the mark, the threads' state and highlights, and the layer that draws them. */
export function Comments(host: CommentsHost) {
  return Extension.create<Record<string, never>, { threads: ThreadItem[] }>({
    name: 'comments',

    addExtensions() {
      return [CommentMark]
    },

    addCommands() {
      return {
        commentStart:
          () =>
          ({ state, dispatch }) => {
            const { selection } = state
            // A selected block without text (an image, an embed): a thread on the whole block.
            if (
              selection instanceof NodeSelection &&
              selection.node.isBlock &&
              selection.node.textContent === ''
            )
              return startBlockDraft(
                state,
                dispatch,
                selection.from,
                blockQuote(selection.node, blockKindLabel(selection.node, selection.$from))
              )
            const { from, to, empty } = selection
            if (empty || state.doc.textBetween(from, to, ' ').trim() === '') return false
            if (state.selection.$from.parent.type.spec.code) return false
            if (dispatch) {
              const draft = { id: newID(), from, to }
              // The formatting menu steps aside (it re-checks only on selection or page changes).
              dispatch(
                setMeta(state.tr, { type: 'draft', draft }).setMeta(SelectionMenuKey, 'hide')
              )
            }
            return true
          },
        commentStartBlock:
          (pos: number, quote: string) =>
          ({ state, dispatch }) =>
            startBlockDraft(state, dispatch, pos, quote),
        commentSend:
          (body: string) =>
          ({ state, tr, dispatch }) => {
            const text = body.trim()
            const plugin = commentsState(state)
            if (!text || !plugin?.active) return false
            const { draft, active } = plugin
            if (draft && draft.id === active && draft.blockId) {
              if (dispatch) {
                setMeta(tr, { type: 'draft', draft: null })
                setMeta(tr, { type: 'active', id: draft.id })
                host.create(draft.id, draft.quote ?? '', text, draft.blockId)
              }
              return true
            }
            if (draft && draft.id === active) {
              const quote = state.doc.textBetween(draft.from, draft.to, ' ').slice(0, 500)
              if (dispatch) {
                tr.addMark(
                  draft.from,
                  draft.to,
                  state.schema.marks.comment.create({ id: draft.id })
                )
                setMeta(tr, { type: 'draft', draft: null })
                setMeta(tr, { type: 'active', id: draft.id })
                tr.setMeta(SAVE_META, true)
                host.create(draft.id, quote, text)
              }
              return true
            }
            if (dispatch) host.reply(active, text)
            return true
          },
        commentOpen:
          (id: string | null) =>
          ({ state, dispatch }) => {
            if (dispatch) {
              const tr = setMeta(state.tr, { type: 'active', id })
              if (id === null) setMeta(tr, { type: 'draft', draft: null })
              dispatch(tr)
            }
            return true
          },
        commentResolve:
          (id: string, resolved: boolean) =>
          ({ state, dispatch }) => {
            if (dispatch) {
              host.resolve(id, resolved)
              if (resolved && commentsState(state)?.active === id)
                dispatch(setMeta(state.tr, { type: 'active', id: null }))
            }
            return true
          },
        commentDelete:
          (id: string) =>
          ({ state, tr, dispatch }) => {
            if (dispatch) {
              for (const range of commentRanges(state.doc).get(id) ?? [])
                tr.removeMark(range.from, range.to, state.schema.marks.comment.create({ id }))
              setMeta(tr, { type: 'active', id: null })
              tr.setMeta(SAVE_META, true)
              host.remove(id)
            }
            return true
          },
        commentDeleteReply:
          (threadId: string, commentId: string) =>
          ({ dispatch }) => {
            if (dispatch) host.remove(threadId, commentId)
            return true
          },
        commentEdit:
          (threadId: string, commentId: string, body: string) =>
          ({ dispatch }) => {
            if (!body.trim()) return false
            if (dispatch) host.edit(threadId, commentId, body.trim())
            return true
          }
      }
    },

    addKeyboardShortcuts() {
      return {
        [tiptapShortcut('comment')]: () => this.editor.commands.commentStart(),
        Escape: () => {
          const plugin = commentsState(this.editor.state)
          if (!plugin?.active && !plugin?.draft) return false
          return this.editor.commands.commentOpen(null)
        }
      }
    },

    addProseMirrorPlugins() {
      const editor = this.editor
      // A finger on a commented passage: where it went down, when, and the thread there.
      let tap: { x: number; y: number; at: number; id: string } | null = null
      return [
        new Plugin<CommentsState>({
          key: CommentsKey,
          state: {
            init: () => ({ threads: new Map(), active: null, draft: null }),
            apply: (tr, value) => {
              let next = value
              const metas = (tr.getMeta(CommentsKey) as Meta[] | undefined) ?? []
              for (const meta of metas) {
                if (meta.type === 'threads')
                  next = { ...next, threads: new Map(meta.threads.map((t) => [t.id, t])) }
                else if (meta.type === 'active') next = { ...next, active: meta.id }
                else next = { ...next, draft: meta.draft, active: meta.draft?.id ?? next.active }
              }
              if (next.draft && tr.docChanged) {
                const from = tr.mapping.map(next.draft.from, 1)
                const to = tr.mapping.map(next.draft.to, -1)
                next = { ...next, draft: to > from ? { ...next.draft, from, to } : null }
              }
              return next
            }
          },
          props: {
            decorations: (state) => decorations(state),
            // A tap on a commented passage opens its thread and nothing else: the touch's click is cancelled, so the
            // caret doesn't move and the keyboard doesn't come up (a click still places the caret on a Mac). A drag,
            // a long press (selecting) or a second finger is left alone.
            handleDOMEvents: {
              touchstart: (view, event) => {
                const touch = event.touches[0]
                const id = event.touches.length === 1 ? threadAt(view, event.target) : undefined
                tap =
                  touch && id ? { x: touch.clientX, y: touch.clientY, at: Date.now(), id } : null
                return false
              },
              touchmove: (_view, event) => {
                const touch = event.touches[0]
                if (
                  tap &&
                  (!touch || Math.hypot(touch.clientX - tap.x, touch.clientY - tap.y) > 10)
                )
                  tap = null
                return false
              },
              touchcancel: () => {
                tap = null
                return false
              },
              touchend: (view, event) => {
                const started = tap
                tap = null
                if (!started || Date.now() - started.at > TAP_MS || event.touches.length > 0)
                  return false
                event.preventDefault()
                if (view.hasFocus()) (view.dom as HTMLElement).blur()
                if (commentsState(view.state)?.active !== started.id)
                  view.dispatch(setMeta(view.state.tr, { type: 'active', id: started.id }))
                return true
              }
            },
            // A press on a commented passage opens its thread.
            handleClick: (view, pos) => {
              const plugin = commentsState(view.state)
              if (!plugin) return false
              const $pos = view.state.doc.resolve(pos)
              const marks = [...($pos.nodeAfter?.marks ?? []), ...($pos.nodeBefore?.marks ?? [])]
              const id =
                (marks.find(
                  (m) =>
                    m.type.name === 'comment' &&
                    plugin.threads.get(m.attrs.id as string)?.resolved === false
                )?.attrs.id as string | undefined) ?? blockThreadAt(view.state, pos)
              if (id && id !== plugin.active)
                view.dispatch(setMeta(view.state.tr, { type: 'active', id }))
              // Elsewhere in the page: the open thread closes (a comment not yet sent is dropped).
              else if (!id && (plugin.active || plugin.draft)) {
                const tr = setMeta(view.state.tr, { type: 'active', id: null })
                view.dispatch(setMeta(tr, { type: 'draft', draft: null }))
              }
              return false
            }
          },
          view: () => {
            const dispose = renderComments(editor, host)
            return { destroy: dispose }
          }
        })
      ]
    }
  })
}

/** Longer than this, a touch is a long press (text selection), not a tap. */
const TAP_MS = 500

/** The open thread whose passage holds `target` (the innermost, where passages overlap). */
function threadAt(view: EditorView, target: EventTarget | null): string | undefined {
  const plugin = commentsState(view.state)
  if (!plugin) return undefined
  let node =
    target instanceof HTMLElement ? target : target instanceof Node ? target.parentElement : null
  for (; node && node !== view.dom; node = node.parentElement) {
    const id = node.dataset.comment
    if (id && plugin.threads.get(id)?.resolved === false) return id
  }
  return undefined
}

/** A draft comment on the whole block at `pos` (it needs a block id). */
function startBlockDraft(
  state: EditorState,
  dispatch: ((tr: Transaction) => void) | undefined,
  pos: number,
  quote: string
): boolean {
  const node = state.doc.nodeAt(pos)
  const blockId = node?.attrs.id as unknown
  if (!node?.isBlock || typeof blockId !== 'string') return false
  if (dispatch) {
    const draft = { id: newID(), from: pos, to: pos + node.nodeSize, blockId, quote }
    dispatch(setMeta(state.tr, { type: 'draft', draft }).setMeta(SelectionMenuKey, 'hide'))
  }
  return true
}

function setMeta(tr: Transaction, meta: Meta): Transaction {
  const metas = (tr.getMeta(CommentsKey) as Meta[] | undefined) ?? []
  return tr.setMeta(CommentsKey, [...metas, meta]).setMeta('addToHistory', false)
}

/** The native store's threads for the page (`window.hikki.setComments`). An open thread whose passage isn't marked in
 * the page (a mark lost before marks were saved, 2026-10-15) is marked again where its quote is — when the quote
 * occurs exactly once, inside one block — without counting as an edit: opening a page never saves it. */
export function setThreads(editor: Editor, threads: ThreadItem[]): void {
  if (editor.isDestroyed) return
  const tr = setMeta(editor.state.tr, { type: 'threads', threads })
  if (editor.isEditable) {
    const marked = commentRanges(editor.state.doc)
    for (const thread of threads) {
      if (thread.resolved || thread.blockId || marked.has(thread.id) || !thread.quote.trim())
        continue
      const range = findQuote(editor.state.doc, thread.quote)
      if (!range) continue
      // Not an edit (viewing never saves): the mark is saved with the page's next real change.
      tr.addMark(range.from, range.to, editor.schema.marks.comment.create({ id: thread.id }))
    }
  }
  editor.view.dispatch(tr)
}

/** Where `quote` is in the page, when it occurs exactly once and within one block (inline atoms count as one
 * character, as in the quote). */
export function findQuote(doc: PMNode, quote: string): { from: number; to: number } | null {
  const found: { from: number; to: number }[] = []
  doc.descendants((node, pos) => {
    if (found.length > 1) return false
    if (!node.isTextblock) return true
    let text = ''
    const at: number[] = []
    node.forEach((child, offset) => {
      const start = pos + 1 + offset
      if (child.isText) {
        for (let i = 0; i < child.text!.length; i++) at.push(start + i)
        text += child.text
      } else {
        at.push(start)
        text += '\uFFFC'
      }
    })
    let index = text.indexOf(quote)
    while (index >= 0 && found.length < 2) {
      found.push({ from: at[index], to: at[index + quote.length - 1] + 1 })
      index = text.indexOf(quote, index + 1)
    }
    return false
  })
  return found.length === 1 ? found[0] : null
}

/** Highlights: open threads' passages (the shown one darker) and a draft's selection. */
function decorations(state: EditorState): DecorationSet {
  const plugin = commentsState(state)
  if (!plugin) return DecorationSet.empty
  const decos: Decoration[] = []
  for (const [id, ranges] of commentRanges(state.doc)) {
    const thread = plugin.threads.get(id)
    if (!thread || thread.resolved) continue
    const cls = id === plugin.active ? 'hk-comment hk-comment-active' : 'hk-comment'
    for (const range of ranges) decos.push(Decoration.inline(range.from, range.to, { class: cls }))
  }
  for (const [id, range] of blockThreadRanges(state.doc, plugin.threads.values())) {
    if (plugin.threads.get(id)?.resolved) continue
    const cls =
      id === plugin.active ? 'hk-comment-block hk-comment-block-active' : 'hk-comment-block'
    decos.push(Decoration.node(range.from, range.to, { class: cls }))
  }
  if (plugin.draft?.blockId) {
    const node = state.doc.nodeAt(plugin.draft.from)
    if (node && plugin.draft.from + node.nodeSize === plugin.draft.to)
      decos.push(
        Decoration.node(plugin.draft.from, plugin.draft.to, {
          class: 'hk-comment-block hk-comment-block-active'
        })
      )
  } else if (plugin.draft)
    decos.push(
      Decoration.inline(plugin.draft.from, plugin.draft.to, {
        class: 'hk-comment hk-comment-active'
      })
    )
  return DecorationSet.create(state.doc, decos)
}
