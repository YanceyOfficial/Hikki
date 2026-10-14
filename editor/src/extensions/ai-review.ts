import { Extension, type Editor } from '@tiptap/core'
import type { Fragment } from '@tiptap/pm/model'
import {
  Plugin,
  PluginKey,
  TextSelection,
  type EditorState,
  type Transaction
} from '@tiptap/pm/state'
import { Decoration, DecorationSet } from '@tiptap/pm/view'

import { renderAIReview, type AIReviewProps } from '../components/ai-review'
import { FloatingLayer } from '../components/floating'
import type { AIStreamEvent } from '../core/protocol'
import {
  type AINote,
  type AIUnit,
  fragmentText,
  parseEditNotes,
  parseEditReply,
  parseInline,
  selectionUnits,
  textBetween
} from '../lib/ai-content'
import { changeCount, diffText, type DiffSegment } from '../lib/ai-diff'

/** A preset or the user's own instruction. Edits replace the selection after review; answers explain it. */
export type AIAction = { id: string; instruction?: string }

/** Prose answers (nothing replaced); `ask` is a follow-up question on an answer. */
const ANSWER_ACTIONS = new Set(['explain', 'summarize', 'ask'])

/**
 * How an edit is reviewed (Settings → AI): A `inline` — tracked changes in the page; B `diff` — before/after lines in
 * the bar; C `bubble` — a card listing each change with why, the page untouched until Replace.
 */
export type AIReviewStyle = 'inline' | 'diff' | 'bubble'

export type AIRequestMessage = {
  id: string
  action: string
  instruction?: string
  answer: boolean
  /** Ask for a short reason per change (review style C). */
  explain?: boolean
  units: { key: string; html: string }[]
  context: { title: string; before: string; after: string; previous?: string }
}

/** What AI review needs from the host (the bridge). */
export type AIHost = {
  request: (message: AIRequestMessage) => void
  cancel: (id: string) => void
  title: () => string
  /** The review style for edits (default `inline`). */
  style?: () => AIReviewStyle
}

/** One AI request over the selection, from asking to accepting or closing. */
export type AISession = {
  id: string
  action: AIAction
  answer: boolean
  style: AIReviewStyle
  units: AIUnit[]
  status: 'thinking' | 'review' | 'answer' | 'error'
  /** The text received so far (the edit's JSON, or the answer's Markdown). */
  reply: string
  /** For edits: each unit's replacement, and its diff against the selection. */
  edits: Map<string, { fragment: Fragment; diff: DiffSegment[] }>
  /** Style C: the model's reasons, one per change. */
  notes: AINote[]
  searching: string | null
  citations: { url: string; title?: string | null }[]
  error: { code: string; provider?: string | null; message?: string | null } | null
}

export const AIReviewKey = new PluginKey<DecorationSet>('aiReview')

/** Context around the selection the model sees (characters on each side). */
const CONTEXT_CHARS = 1500

let counter = 0
const newID = () => `ai-${Date.now().toString(36)}-${(counter++).toString(36)}`

/**
 * AI on the selection, reviewed inline (style A): while the model works the selection shimmers; its edit comes back
 * as decorations — removed text struck through, added text inserted beside it — with a bar under the selection to
 * accept (one undo step), discard, retry or ask for a change. Nothing touches the document until accepted, and the
 * review closes if the page changes under it. Explain / summarize answer in a card instead.
 */
export function AIReview(host: AIHost) {
  return Extension.create<
    Record<string, never>,
    { session: AISession | null; layer: FloatingLayer | null }
  >({
    name: 'aiReview',

    addStorage() {
      return { session: null, layer: null }
    },

    addCommands() {
      return {
        aiRun:
          (action: AIAction) =>
          ({ editor }) =>
            start(editor, host, action),
        aiAccept:
          () =>
          ({ editor, tr, dispatch }) =>
            accept(editor, tr, dispatch),
        aiDiscard:
          () =>
          ({ editor }) => {
            close(editor, host)
            return true
          }
      }
    },

    addProseMirrorPlugins() {
      const editor = this.editor
      return [
        new Plugin<DecorationSet>({
          key: AIReviewKey,
          state: {
            init: () => DecorationSet.empty,
            apply: (tr, set, _old, state) => {
              if (tr.getMeta(AIReviewKey)) return decorations(state, storage(editor).session)
              // oxlint-disable-next-line unicorn/no-array-callback-reference -- DecorationSet.map, not an array
              return set.map(tr.mapping, tr.doc)
            }
          },
          props: {
            decorations: (state) => AIReviewKey.getState(state),
            // While a review is open, Enter accepts and Escape discards (typing would close it anyway).
            handleKeyDown: (_view, event) => {
              const session = storage(editor).session
              if (!session || event.isComposing) return false
              if (event.key === 'Escape') {
                close(editor, host)
                return true
              }
              if (event.key === 'Enter' && session.status === 'review' && session.edits.size > 0) {
                editor.commands.aiAccept()
                return true
              }
              return false
            }
          },
          // The page changed under the review (typing, a remote reload): its positions no longer hold — it closes.
          appendTransaction: (transactions) => {
            if (
              storage(editor).session &&
              transactions.some((tr) => tr.docChanged && !tr.getMeta(AIReviewKey))
            ) {
              queueMicrotask(() => close(editor, host))
            }
            return null
          }
        })
      ]
    },

    onDestroy() {
      const { session, layer } = this.storage
      if (session) host.cancel(session.id)
      layer?.destroy()
      this.storage.session = null
      this.storage.layer = null
    }
  })
}

declare module '@tiptap/core' {
  interface Commands<ReturnType> {
    aiReview: {
      /** Ask AI about the selection (an edit to review, or an answer). */
      aiRun: (action: AIAction) => ReturnType
      /** Apply the edit under review, as one undo step. */
      aiAccept: () => ReturnType
      /** Close the review without changing anything. */
      aiDiscard: () => ReturnType
    }
  }
}

function storage(editor: Editor): { session: AISession | null; layer: FloatingLayer | null } {
  return (
    editor.storage as unknown as Record<
      string,
      { session: AISession | null; layer: FloatingLayer | null }
    >
  ).aiReview
}

/** Plain text around the selection (for context only; the model edits the units). */
function surroundings(state: EditorState, from: number, to: number) {
  const doc = state.doc
  const before = doc.textBetween(Math.max(0, from - CONTEXT_CHARS), from, '\n', ' ')
  const after = doc.textBetween(to, Math.min(doc.content.size, to + CONTEXT_CHARS), '\n', ' ')
  return { before, after }
}

/**
 * Asks for `action` on the selection — or, for a retry or a follow-up, on the same text as `again` (with the reply
 * being refined as `previous`).
 */
function start(
  editor: Editor,
  host: AIHost,
  action: AIAction,
  again?: AISession,
  previous?: string
): boolean {
  const units = again?.units ?? selectionUnits(editor.state)
  if (units.length === 0) return false
  const old = storage(editor).session
  if (old) host.cancel(old.id)
  const answer = ANSWER_ACTIONS.has(action.id.split(':')[0])
  const session: AISession = {
    id: newID(),
    action,
    answer,
    style: host.style?.() ?? 'inline',
    units,
    status: 'thinking',
    reply: '',
    edits: new Map(),
    notes: [],
    searching: null,
    citations: [],
    error: null
  }
  storage(editor).session = session
  const from = units[0].from
  const to = units.at(-1)!.to
  host.request({
    id: session.id,
    action: action.id,
    ...(action.instruction ? { instruction: action.instruction } : {}),
    answer,
    ...(session.style === 'bubble' && !answer ? { explain: true } : {}),
    units: units.map(({ key, html }) => ({ key, html })),
    context: {
      title: host.title(),
      ...surroundings(editor.state, from, to),
      ...(previous ? { previous } : {})
    }
  })
  // The selection stays visible as the review's range; the formatting menu steps aside meanwhile.
  editor.view.dispatch(editor.state.tr.setMeta(AIReviewKey, true).setMeta('addToHistory', false))
  draw(editor, host)
  return true
}

/** Whether AI is working on, or showing a review of, the selection (the formatting menu steps aside meanwhile). */
export const aiReviewOpen = (editor: Editor): boolean =>
  !!(editor.storage as unknown as Record<string, { session?: unknown } | undefined>).aiReview
    ?.session

/** An event of the session's answer (`window.hikki.aiEvent`). */
export function handleAIEvent(editor: Editor, host: AIHost, event: AIStreamEvent): void {
  const session = storage(editor).session
  if (!session || event.id !== session.id) return
  switch (event.type) {
    case 'text':
      session.reply += event.delta
      if (session.answer) session.status = 'answer'
      break
    case 'searching':
      session.searching = event.query ?? session.searching ?? ''
      break
    case 'citation':
      // Only web pages, once each (the URL comes from the model's search).
      if (webURL(event.url) && !session.citations.some((c) => c.url === event.url))
        session.citations.push({ url: event.url, title: event.title })
      break
    case 'done':
      session.searching = null
      if (session.answer) {
        session.status = session.reply.trim() ? 'answer' : 'error'
        if (!session.reply.trim()) session.error = { code: 'invalidResponse' }
      } else {
        finishEdit(editor, session)
      }
      break
    case 'error':
      session.status = 'error'
      session.error = { code: event.code, provider: event.provider, message: event.message }
      break
  }
  editor.view.dispatch(editor.state.tr.setMeta(AIReviewKey, true).setMeta('addToHistory', false))
  draw(editor, host)
}

function webURL(url: unknown): boolean {
  if (typeof url !== 'string') return false
  try {
    const { protocol } = new URL(url)
    return protocol === 'https:' || protocol === 'http:'
  } catch {
    return false
  }
}

/** The edit's reply read, checked and parsed into each unit's replacement (or an error, never a crash). */
function finishEdit(editor: Editor, session: AISession): void {
  const replies = parseEditReply(
    session.reply,
    session.units.map((u) => u.key)
  )
  if (!replies) {
    session.status = 'error'
    session.error = { code: 'invalidResponse' }
    return
  }
  for (const unit of session.units) {
    const html = replies.get(unit.key)
    if (html === undefined) continue
    const fragment = parseInline(editor.schema, html)
    if (!fragment) continue
    const diff = diffText(unit.text, fragmentText(fragment))
    if (diff.some((segment) => segment.type !== 'same'))
      session.edits.set(unit.key, { fragment, diff })
  }
  if (session.style === 'bubble') session.notes = parseEditNotes(session.reply)
  session.status = 'review'
}

/** The review on the page: the shimmer while waiting, the edit's removals and additions once it is back. */
function decorations(state: EditorState, session: AISession | null): DecorationSet {
  if (!session) return DecorationSet.empty
  const decos: Decoration[] = []
  for (const unit of session.units) {
    // Styles B and C show the edit in the bar; the page keeps the selection marked.
    if (session.status === 'thinking' || session.answer || session.style !== 'inline') {
      decos.push(
        Decoration.inline(unit.from, unit.to, {
          class: session.status === 'thinking' ? 'hk-ai-thinking' : 'hk-ai-subject'
        })
      )
      continue
    }
    const edit = session.edits.get(unit.key)
    if (!edit) continue
    const { positions } = textBetween(state.doc, unit.from, unit.to)
    let index = 0
    for (const segment of edit.diff) {
      const length = [...segment.text].length
      if (segment.type === 'same') {
        index += length
      } else if (segment.type === 'del') {
        // From the first removed character to where the next one starts (or the end of the range).
        const from = positions[index] ?? unit.to
        const to = positions[index + length] ?? unit.to
        if (to > from) decos.push(Decoration.inline(from, to, { class: 'hk-ai-del' }))
        index += length
      } else {
        const at = positions[index] ?? unit.to
        decos.push(
          Decoration.widget(
            at,
            () => {
              const span = document.createElement('span')
              span.className = 'hk-ai-ins'
              span.textContent = segment.text
              return span
            },
            { side: -1, key: `${unit.key}:${index}:${segment.text}` }
          )
        )
      }
    }
  }
  return DecorationSet.create(state.doc, decos)
}

/** Applies the edit in the command's transaction: one step to undo, the review gone with it. */
function accept(editor: Editor, tr: Transaction, dispatch?: (tr: Transaction) => void): boolean {
  const session = storage(editor).session
  if (!session || session.status !== 'review' || session.edits.size === 0) return false
  if (!dispatch) return true
  // From the last unit back, so earlier positions stay valid.
  for (const unit of session.units.toReversed()) {
    const edit = session.edits.get(unit.key)
    if (edit) tr.replaceWith(unit.from, unit.to, edit.fragment)
  }
  const end = tr.mapping.map(session.units.at(-1)!.to)
  tr.setSelection(TextSelection.create(tr.doc, Math.min(end, tr.doc.content.size)))
  // The meta redraws the decorations from the (now empty) session and keeps the change from closing a review.
  tr.setMeta(AIReviewKey, true)
  storage(editor).session = null
  storage(editor).layer?.destroy()
  storage(editor).layer = null
  return true
}

function close(editor: Editor, host: AIHost): void {
  const { session, layer } = storage(editor)
  if (session && (session.status === 'thinking' || session.status === 'answer'))
    host.cancel(session.id)
  storage(editor).session = null
  layer?.destroy()
  storage(editor).layer = null
  if (!editor.isDestroyed)
    editor.view.dispatch(editor.state.tr.setMeta(AIReviewKey, true).setMeta('addToHistory', false))
}

/** Inserts an answer as paragraphs after the selection (the answer card's "Insert below"). */
function insertBelow(editor: Editor, host: AIHost, text: string): void {
  const session = storage(editor).session
  if (!session) return
  const $end = editor.state.doc.resolve(session.units.at(-1)!.to)
  const after = $end.after(1)
  const paragraphs = text
    .split(/\n{2,}/u)
    .map((p) => p.trim())
    .filter(Boolean)
    .map((p) => ({ type: 'paragraph', content: [{ type: 'text', text: p }] }))
  close(editor, host)
  if (paragraphs.length > 0) editor.chain().focus().insertContentAt(after, paragraphs).run()
}

/** The bar or card under the selection, redrawn on every change of the session. */
function draw(editor: Editor, host: AIHost): void {
  const store = storage(editor)
  const session = store.session
  if (!session) return
  store.layer ??= new FloatingLayer('hk-ai-review', { onDismiss: () => close(editor, host) })
  const end = session.units.at(-1)!.to
  const props: AIReviewProps = {
    session: {
      status: session.status,
      answer: session.answer,
      reply: session.reply,
      searching: session.searching,
      citations: session.citations,
      error: session.error,
      changes: [...session.edits.values()].reduce((sum, edit) => sum + changeCount(edit.diff), 0),
      style: session.style,
      lines: session.units.map((unit) => ({
        key: unit.key,
        diff: session.edits.get(unit.key)?.diff ?? [{ type: 'same', text: unit.text }]
      })),
      notes: session.notes
    },
    onAccept: () => void editor.chain().focus().aiAccept().run(),
    onDiscard: () => close(editor, host),
    onRetry: () => start(editor, host, session.action, session),
    onFollowUp: (instruction) =>
      start(
        editor,
        host,
        { id: session.answer ? 'ask' : 'custom', instruction },
        session,
        session.reply
      ),
    onInsertBelow: () => insertBelow(editor, host, session.reply),
    onCopy: (text) => void navigator.clipboard?.writeText(text ?? session.reply).catch(() => {})
  }
  renderAIReview(store.layer, props, () => {
    try {
      const coords = editor.view.coordsAtPos(Math.min(end, editor.state.doc.content.size))
      return new DOMRect(coords.left, coords.bottom, 1, 1)
    } catch {
      return null
    }
  })
}
