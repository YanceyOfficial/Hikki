import { Extension, Mark, type Editor } from '@tiptap/core'
import type { Node as PMNode } from '@tiptap/pm/model'
import { Plugin, PluginKey, type EditorState, type Transaction } from '@tiptap/pm/state'
import { Decoration, DecorationSet } from '@tiptap/pm/view'

import { renderComments } from '../components/comments'
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

/** A thread on a passage: its words live natively (`comments/<page id>.json`); the passage carries a `comment` mark. */
export type ThreadItem = { id: string; quote: string; resolved: boolean; comments: CommentItem[] }

/** What comments need from the host (the bridge): writing to the native store, and who is writing. */
export type CommentsHost = {
  create: (threadId: string, quote: string, body: string) => void
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
}

export type CommentsState = {
  threads: Map<string, ThreadItem>
  /** The thread shown open (its reply field), or the draft's id while a new comment is being written. */
  active: string | null
  /** A comment being started on a selection: a highlight only, until it is sent. */
  draft: { id: string; from: number; to: number } | null
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

/** Where each thread's passage is in the document: its ranges, in order. */
export function commentRanges(doc: PMNode): Map<string, { from: number; to: number }[]> {
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
  return ranges
}

export const commentsState = (state: EditorState): CommentsState | undefined =>
  CommentsKey.getState(state)

const newID = () =>
  globalThis.crypto?.randomUUID?.() ??
  `c-${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`

declare module '@tiptap/core' {
  interface Commands<ReturnType> {
    comments: {
      /** A comment on the selection: a draft highlight and its composer (nothing is stored until it is sent). */
      commentStart: () => ReturnType
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
            const { from, to, empty } = state.selection
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
        commentSend:
          (body: string) =>
          ({ state, tr, dispatch }) => {
            const text = body.trim()
            const plugin = commentsState(state)
            if (!text || !plugin?.active) return false
            const { draft, active } = plugin
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
            // A press on a commented passage opens its thread.
            handleClick: (view, pos) => {
              const plugin = commentsState(view.state)
              if (!plugin) return false
              const $pos = view.state.doc.resolve(pos)
              const marks = [...($pos.nodeAfter?.marks ?? []), ...($pos.nodeBefore?.marks ?? [])]
              const id = marks.find(
                (m) =>
                  m.type.name === 'comment' &&
                  plugin.threads.get(m.attrs.id as string)?.resolved === false
              )?.attrs.id as string | undefined
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

function setMeta(tr: Transaction, meta: Meta): Transaction {
  const metas = (tr.getMeta(CommentsKey) as Meta[] | undefined) ?? []
  return tr.setMeta(CommentsKey, [...metas, meta]).setMeta('addToHistory', false)
}

/** The native store's threads for the page (`window.hikki.setComments`). */
export function setThreads(editor: Editor, threads: ThreadItem[]): void {
  if (editor.isDestroyed) return
  editor.view.dispatch(setMeta(editor.state.tr, { type: 'threads', threads }))
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
  if (plugin.draft)
    decos.push(
      Decoration.inline(plugin.draft.from, plugin.draft.to, {
        class: 'hk-comment hk-comment-active'
      })
    )
  return DecorationSet.create(state.doc, decos)
}
