import { Extension, type Editor } from '@tiptap/core'
import { DOMSerializer, type Fragment, type Node as PMNode, type Schema } from '@tiptap/pm/model'
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
import { answerBlocks, answerDOM } from '../core/answer-markdown'
import { isWebURL } from '../core/links'
import type { AIMediaRef, AIStreamEvent } from '../core/protocol'
import {
  type AddedType,
  type AIUnit,
  fragmentText,
  isHandoff,
  mediaRef,
  OBJECT_CHAR,
  parseEditAdded,
  parseEditNotes,
  parseEditReply,
  parseInline,
  selectionUnits,
  textBetween
} from '../lib/ai-content'
import { changeCount, diffText, type DiffSegment } from '../lib/ai-diff'
import { SelectionMenuKey } from './selection-menu'

/** A preset or the user's own instruction. Edits replace the selection after review; answers explain it. */
/** What to ask; `model` is one picked in the panel for this request (a retry or a follow-up keeps it). */
export type AIAction = { id: string; instruction?: string; model?: string }

/** Prose answers (nothing replaced); `ask` is a follow-up question on an answer. `describe` and `extractText` are
 * about a picture or a PDF (every request about one answers). */
const ANSWER_ACTIONS = new Set(['explain', 'summarize', 'ask', 'describe', 'extractText'])

/** Requests in the user's own words: the model may hand them to the chat instead (`mayHandOff`). */
const HANDOFF_ACTIONS = new Set(['custom', 'ask'])

/** The one action whose reply may add blocks after the selection (`"added"`): the user's own instruction for an
 * edit. A preset is an edit of the selected text alone, and an answer adds nothing (it goes to notes). */
const ADDING_ACTIONS = new Set(['custom'])

/**
 * How an edit is reviewed (Settings → AI): A `inline` — tracked changes in the page; B `diff` — before/after lines in
 * the bar. Either way, what the model says to the user (its `notes`) is a card under the bar.
 */
export type AIReviewStyle = 'inline' | 'diff'

export type AIRequestMessage = {
  id: string
  action: string
  instruction?: string
  answer: boolean
  units: { key: string; html: string }[]
  context: { title: string; before: string; after: string; previous?: string }
  /** The picture or PDF asked about (then `units` is empty). */
  media?: AIMediaRef
  model?: string
}

/** What AI review needs from the host (the bridge). */
export type AIHost = {
  request: (message: AIRequestMessage) => void
  cancel: (id: string) => void
  title: () => string
  /** The review style for edits (default `inline`). */
  style?: () => AIReviewStyle
  /**
   * The model judged the request more than an edit or a short answer: the app continues it in the chat, with the
   * user's words and the passage (its text). Without it, a request never hands off.
   */
  handoff?: (request: { instruction: string; selection: string }) => void
}

/** One AI request over the selection, from asking to accepting or closing. */
export type AISession = {
  id: string
  action: AIAction
  answer: boolean
  style: AIReviewStyle
  units: AIUnit[]
  /** A question about a picture or a PDF: the file, and its block as the one unit (no text, nothing to edit). */
  media?: AIMediaRef
  status: 'thinking' | 'review' | 'answer' | 'error'
  /** The status the bar was last brought into view for (once per status: streaming text doesn't move the page). */
  revealed?: AISession['status']
  /** The text received so far (the edit's JSON, or the answer's Markdown). */
  reply: string
  /** For edits: each unit's replacement, and its diff against the selection. */
  edits: Map<string, { fragment: Fragment; diff: DiffSegment[] }>
  /** For edits: the new blocks that go right after the selection (the user asked for new material), in order —
   * ghosts in the page until accepted. */
  added: AIAddedBlock[]
  /** For edits: what the model says to the user (Markdown each) — answers, verdicts, explanations — shown in a card,
   * never part of the edit. */
  notes: string[]
  /** The notes inserted into the page so far (by index), and where the next one goes (after the last). */
  inserted: number[]
  insertAt?: number
  /** The edit was accepted and its notes are still open (nothing left to accept or retry). */
  accepted?: boolean
  searching: string | null
  citations: { url: string; title?: string | null }[]
  error: { code: string; provider?: string | null; message?: string | null } | null
}

/** A block the model adds after the selection, parsed: its kind, its content for this schema and its text. */
export type AIAddedBlock = { type: AddedType; fragment: Fragment; text: string }

export const AIReviewKey = new PluginKey<DecorationSet>('aiReview')

/** A change the review made itself (a note inserted below), or one another plugin appended to it (block ids stamped). */
const ours = (tr: Transaction): boolean =>
  !!tr.getMeta(AIReviewKey) ||
  !!(tr.getMeta('appendedTransaction') as Transaction | undefined)?.getMeta(AIReviewKey)

/** Context around the selection the model sees (characters on each side). */
const CONTEXT_CHARS = 1500

let counter = 0
const newID = () => `ai-${Date.now().toString(36)}-${(counter++).toString(36)}`

/**
 * AI on the selection, reviewed inline (style A): while the model works the selection shimmers; its edit comes back
 * as decorations — removed text struck through, added text inserted beside it — with a bar under the selection to
 * accept (one undo step), discard, retry or ask for a change. New blocks the user's own instruction asked for
 * (`added`) stand as green ghosts after the selection's block and go in with the edit on Accept. Nothing touches the
 * document until accepted, and the review closes if the page changes under it. Explain / summarize answer in a card instead. What the model says
 * beside an edit (`notes`) is a card of its own under the bar — each note copied or inserted below the selection,
 * never part of the edit, and still there once the edit is accepted. A request in the user's words the model judges
 * too big for the selection (`{"handoff": …}`) closes here and continues in the chat (`AIHost.handoff`).
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
        aiRunMedia:
          (pos: number, action: AIAction) =>
          ({ editor }) => {
            const node = editor.state.doc.nodeAt(pos)
            const media = node ? mediaRef(node) : null
            if (!node || !media) return false
            const unit: AIUnit = {
              key: (node.attrs.id as string | null) ?? 'media',
              from: pos,
              to: pos + node.nodeSize,
              html: '',
              text: ''
            }
            return start(editor, host, action, undefined, undefined, { units: [unit], media })
          },
        aiAccept:
          () =>
          ({ editor, tr, dispatch }) =>
            accept(editor, host, tr, dispatch),
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
            // While AI has the range, the browser's own selection paint (list markers and all) gives way to ours.
            attributes: (): Record<string, string> =>
              storage(editor).session ? { class: 'hk-ai-open' } : {},
            // While a review is open, Enter accepts and Escape discards (typing would close it anyway).
            handleKeyDown: (_view, event) => {
              const session = storage(editor).session
              if (!session || event.isComposing) return false
              if (event.key === 'Escape') {
                close(editor, host)
                return true
              }
              if (event.key === 'Enter' && session.status === 'review' && acceptable(session)) {
                editor.commands.aiAccept()
                return true
              }
              return false
            }
          },
          // The page changed under the review (typing, a remote reload): its positions no longer hold — it closes. Our
          // own changes (a note inserted below) don't (`ours`).
          appendTransaction: (transactions) => {
            if (storage(editor).session && transactions.some((tr) => tr.docChanged && !ours(tr))) {
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
      /** Ask AI about the picture or PDF block at `pos` (`describe`, `extractText`, `explain`, or a question). */
      aiRunMedia: (pos: number, action: AIAction) => ReturnType
      /** Apply the edit under review, as one undo step. */
      aiAccept: () => ReturnType
      /** Close the review without changing anything. */
      aiDiscard: () => ReturnType
      /** Ask the chat for pictures: for this line (`here`), of the selection, or changing the picture at a position. */
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
  previous?: string,
  about?: { units: AIUnit[]; media: AIMediaRef }
): boolean {
  const units = again?.units ?? about?.units ?? selectionUnits(editor.state)
  const media = again ? again.media : about?.media
  if (units.length === 0) return false
  const old = storage(editor).session
  if (old) host.cancel(old.id)
  const model = action.model ?? again?.action.model
  if (model) action = { ...action, model }
  // Nothing of a picture can be replaced: every request about one answers.
  const answer = !!media || ANSWER_ACTIONS.has(action.id.split(':')[0])
  const session: AISession = {
    id: newID(),
    action,
    answer,
    style: host.style?.() ?? 'inline',
    units,
    ...(media ? { media } : {}),
    status: 'thinking',
    reply: '',
    edits: new Map(),
    added: [],
    notes: [],
    inserted: [],
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
    // A picture's block has no text to send: the file goes instead.
    units: media ? [] : units.map(({ key, html }) => ({ key, html })),
    context: {
      title: host.title(),
      ...surroundings(editor.state, from, to),
      ...(previous ? { previous } : {})
    },
    ...(media ? { media } : {}),
    ...(model ? { model } : {})
  })
  // The review's range stays marked (our decoration, not the selection); the formatting menu steps aside meanwhile
  // (it re-checks only when the selection or the page changes, and asking changes neither).
  editor.view.dispatch(
    editor.state.tr
      .setMeta(AIReviewKey, true)
      .setMeta(SelectionMenuKey, 'hide')
      .setMeta('addToHistory', false)
  )
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
      if (session.answer && !heldBack(host, session)) session.status = 'answer'
      break
    case 'searching':
      session.searching = event.query ?? session.searching ?? ''
      break
    case 'citation':
      // Only web pages, once each (the URL comes from the model's search).
      if (isWebURL(event.url) && !session.citations.some((c) => c.url === event.url))
        session.citations.push({ url: event.url, title: event.title })
      break
    case 'done':
      session.searching = null
      if (mayHandOff(host, session) && isHandoff(session.reply)) {
        handOff(editor, host, session)
        return
      }
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
  // Text streams in many small pieces: one redraw per frame (an answer's Markdown is parsed whole each time).
  // Anything else redraws at once, taking a pending frame's place.
  const pending = pendingRedraws.get(session)
  if (event.type === 'text') {
    if (pending === undefined)
      pendingRedraws.set(
        session,
        requestAnimationFrame(() => {
          pendingRedraws.delete(session)
          if (!editor.isDestroyed && storage(editor).session === session) redraw(editor, host)
        })
      )
    return
  }
  if (pending !== undefined) {
    cancelAnimationFrame(pending)
    pendingRedraws.delete(session)
  }
  redraw(editor, host)
}

/** A session's redraw waiting for the next frame (text streaming in). */
const pendingRedraws = new WeakMap<AISession, number>()

function redraw(editor: Editor, host: AIHost): void {
  editor.view.dispatch(editor.state.tr.setMeta(AIReviewKey, true).setMeta('addToHistory', false))
  draw(editor, host)
}

/** Whether the model may hand this request to the chat: the user's own words about text, and a host that can. */
function mayHandOff(host: AIHost, session: AISession): boolean {
  return (
    !!host.handoff &&
    !session.media &&
    HANDOFF_ACTIONS.has(session.action.id) &&
    !!session.action.instruction?.trim()
  )
}

/** An answer that may be a handoff and so far reads like JSON: it isn't drawn as Markdown until it's known. */
function heldBack(host: AIHost, session: AISession): boolean {
  return mayHandOff(host, session) && session.reply.trimStart().startsWith('{')
}

/** The request goes to the chat: this review closes, the user's words and the passage's text go along. */
function handOff(editor: Editor, host: AIHost, session: AISession): void {
  const selection = session.units
    .map((unit) => unit.text.replaceAll(OBJECT_CHAR, ''))
    .join('\n')
    .trim()
  // The answer is complete (nothing to cancel).
  session.status = 'review'
  close(editor, host)
  host.handoff?.({ instruction: session.action.instruction?.trim() ?? '', selection })
}

/**
 * The edit's reply read, checked and parsed into each unit's replacement and the notes for the user (or an error,
 * never a crash). Notes alone — a check that found nothing to change — are a review too.
 */
function finishEdit(editor: Editor, session: AISession): void {
  const replies = parseEditReply(
    session.reply,
    session.units.map((u) => u.key)
  )
  session.notes = parseEditNotes(session.reply)
  // Only the user's own instruction may add blocks; whatever a preset's reply adds is ignored.
  if (ADDING_ACTIONS.has(session.action.id.split(':')[0])) {
    for (const block of parseEditAdded(session.reply)) {
      const fragment = parseInline(editor.schema, block.html)
      if (!fragment || fragment.size === 0) continue
      session.added.push({ type: block.type, fragment, text: fragmentText(fragment) })
    }
  }
  if (!replies && session.notes.length === 0 && session.added.length === 0) {
    session.status = 'error'
    session.error = { code: 'invalidResponse' }
    return
  }
  for (const unit of session.units) {
    const html = replies?.get(unit.key)
    if (html === undefined) continue
    const fragment = parseInline(editor.schema, html)
    if (!fragment) continue
    const diff = diffText(unit.text, fragmentText(fragment))
    if (diff.some((segment) => segment.type !== 'same'))
      session.edits.set(unit.key, { fragment, diff })
  }
  session.status = 'review'
}

/** Whether there is an edit to accept: a changed block, or blocks to add. */
const acceptable = (session: AISession): boolean =>
  session.edits.size > 0 || session.added.length > 0

/** How many separate changes the review holds: the diffs' changes, and each added block as one. */
const changeTotal = (session: AISession): number =>
  [...session.edits.values()].reduce((sum, edit) => sum + changeCount(edit.diff), 0) +
  session.added.length

/**
 * The added blocks as nodes of the schema: a paragraph, a heading, a quote around a paragraph, and a run of list
 * items as one list (bullet or numbered), so they go in as the page would hold them.
 */
export function addedNodes(schema: Schema, added: AIAddedBlock[]): PMNode[] {
  const { nodes } = schema
  const out: PMNode[] = []
  let list: { type: 'bullet' | 'numbered'; items: PMNode[] } | null = null
  const flush = () => {
    if (!list) return
    const listType = list.type === 'bullet' ? nodes.bulletList : nodes.orderedList
    const node = listType?.createAndFill(null, list.items)
    if (node) out.push(node)
    else out.push(...list.items.map((item) => item.firstChild ?? item))
    list = null
  }
  for (const block of added) {
    const paragraph = nodes.paragraph.create(null, block.fragment)
    const level = /^heading([1-3])$/u.exec(block.type)?.[1]
    if (block.type === 'bullet' || block.type === 'numbered') {
      const item = nodes.listItem?.createAndFill(null, paragraph)
      if (item) {
        if (list && list.type !== block.type) flush()
        list ??= { type: block.type, items: [] }
        list.items.push(item)
        continue
      }
    }
    flush()
    const quote = block.type === 'quote' ? nodes.blockquote?.createAndFill(null, paragraph) : null
    if (level && nodes.heading)
      out.push(nodes.heading.create({ level: Number(level) }, block.fragment))
    else if (quote) out.push(quote)
    else out.push(paragraph)
  }
  flush()
  return out
}

/**
 * The ghost of a block to add, drawn between the page's blocks in green (the look of the chat's proposed inserts,
 * `.hk-ai-ghost`): its inline content as the page would draw it — marks, links and line breaks kept — a heading at its
 * size, a list item with its marker, a quote with its rule.
 */
function ghostBlock(schema: Schema, block: AIAddedBlock, ordinal: number): HTMLElement {
  const div = document.createElement('div')
  div.className = 'hk-ai-ghost is-added'
  div.contentEditable = 'false'
  div.dataset.kind = block.type
  const level = /^heading([1-3])$/u.exec(block.type)?.[1]
  if (level) div.dataset.level = level
  if (block.type === 'bullet') div.dataset.marker = '•'
  if (block.type === 'numbered') div.dataset.marker = `${ordinal}.`
  div.append(DOMSerializer.fromSchema(schema).serializeFragment(block.fragment))
  return div
}

/** The review on the page: the shimmer while waiting, the edit's removals and additions once it is back. */
function decorations(state: EditorState, session: AISession | null): DecorationSet {
  if (!session) return DecorationSet.empty
  const decos: Decoration[] = []
  if (session.media) {
    const unit = session.units[0]
    const node = state.doc.nodeAt(unit.from)
    if (node && unit.from + node.nodeSize === unit.to)
      decos.push(Decoration.node(unit.from, unit.to, { class: 'hk-ai-media' }))
    return DecorationSet.create(state.doc, decos)
  }
  for (const unit of session.units) {
    // Style B shows the edit in the bar; the page keeps the selection marked.
    if (session.status === 'thinking' || session.answer || session.style !== 'inline') {
      decos.push(
        Decoration.inline(unit.from, unit.to, {
          class: session.status === 'thinking' ? 'hk-ai-thinking' : 'hk-ai-subject'
        })
      )
      continue
    }
    decos.push(Decoration.inline(unit.from, unit.to, { class: 'hk-ai-subject' }))
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
  // The blocks to add, as ghosts right after the selection's last block (style B lists them in the bar).
  if (session.status === 'review' && session.style === 'inline' && session.added.length > 0) {
    const at = afterSelection(state, session)
    let ordinal = 0
    session.added.forEach((block, index) => {
      ordinal = block.type === 'numbered' ? ordinal + 1 : 0
      const number = ordinal
      decos.push(
        Decoration.widget(at, () => ghostBlock(state.schema, block, number), {
          // Before anything inserted there meanwhile (a note), as Accept puts the blocks.
          side: -1,
          key: `added:${index}:${block.type}:${block.text}`
        })
      )
    })
  }
  return DecorationSet.create(state.doc, decos)
}

/** Where blocks the edit adds go: right after the top-level block the selection ends in. */
function afterSelection(state: EditorState, session: AISession): number {
  const end = Math.min(session.units.at(-1)!.to, state.doc.content.size)
  const $end = state.doc.resolve(end)
  return $end.depth > 0 ? $end.after(1) : end
}

/**
 * Applies the edit in the command's transaction: one step to undo, the review gone with it — but for its notes, which
 * stay open over the accepted text (they are never part of the edit).
 */
function accept(
  editor: Editor,
  host: AIHost,
  tr: Transaction,
  dispatch?: (tr: Transaction) => void
): boolean {
  const session = storage(editor).session
  if (!session || session.status !== 'review' || !acceptable(session)) return false
  if (!dispatch) return true
  const addAt = session.added.length > 0 ? afterSelection(editor.state, session) : null
  // From the last unit back, so earlier positions stay valid.
  for (const unit of session.units.toReversed()) {
    const edit = session.edits.get(unit.key)
    if (edit) tr.replaceWith(unit.from, unit.to, edit.fragment)
  }
  // The added blocks after the selection, in the same step (one undo takes the edit and them together).
  let addedEnd: number | undefined
  if (addAt !== null) {
    const nodes = addedNodes(editor.schema, session.added)
    const at = tr.mapping.map(addAt, -1)
    tr.insert(at, nodes)
    addedEnd = at + nodes.reduce((sum, node) => sum + node.nodeSize, 0)
  }
  const end = tr.mapping.map(session.units.at(-1)!.to)
  tr.setSelection(TextSelection.create(tr.doc, Math.min(end, tr.doc.content.size)))
  // The meta redraws the decorations from the (now empty) session and keeps the change from closing a review.
  tr.setMeta(AIReviewKey, true)
  if (session.notes.length > 0) {
    session.units = session.units.map((unit) => ({
      ...unit,
      from: tr.mapping.map(unit.from, -1),
      to: tr.mapping.map(unit.to, 1)
    }))
    if (session.insertAt !== undefined) session.insertAt = tr.mapping.map(session.insertAt)
    // A note inserted from here on goes below the added blocks, not between them and the selection.
    else if (addedEnd !== undefined) session.insertAt = addedEnd
    session.edits = new Map()
    session.added = []
    session.accepted = true
    // Redrawn once the transaction is in (the bar measures the page).
    queueMicrotask(() => {
      if (!editor.isDestroyed && storage(editor).session === session) draw(editor, host)
    })
    return true
  }
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

/** Where "Insert below" puts blocks: right after the block a picture's answer is about (in its column or callout);
 * else after the top-level block the selection ends in. */
function belowSelection(editor: Editor, session: AISession): number {
  const end = session.units.at(-1)!.to
  return session.media ? end : editor.state.doc.resolve(end).after(1)
}

/** Inserts an answer as paragraphs after the selection (the answer card's "Insert below"). */
function insertBelow(editor: Editor, host: AIHost, text: string): void {
  const session = storage(editor).session
  if (!session) return
  const after = belowSelection(editor, session)
  // The answer's Markdown as real blocks (lists, headings, emphasis), media and non-web links left out.
  const blocks = text.trim() ? answerBlocks(editor, text) : []
  close(editor, host)
  if (blocks.length > 0) editor.chain().focus().insertContentAt(after, blocks).run()
}

/**
 * A note of the edit's card into the page as blocks, below the selection (after the notes inserted before it). The
 * review stays open: the blocks land past every unit, so the edit under review still holds (the insertion is marked
 * ours, so it doesn't close the review; undoing it does, as any other change).
 */
function insertNote(editor: Editor, host: AIHost, index: number): void {
  const session = storage(editor).session
  const note = session?.notes[index]
  if (!session || !note || session.inserted.includes(index)) return
  const blocks = answerBlocks(editor, note)
  if (blocks.length === 0) return
  const at = session.insertAt ?? belowSelection(editor, session)
  let next = at
  editor
    .chain()
    .focus()
    .command(({ tr }) => {
      tr.setMeta(AIReviewKey, true)
      return true
    })
    .insertContentAt(at, blocks)
    // Right after what went in (whatever is appended at the page's end, an empty last paragraph, comes later).
    .command(({ tr }) => {
      next = tr.mapping.map(at)
      return true
    })
    .run()
  session.insertAt = next
  session.inserted = [...session.inserted, index]
  draw(editor, host)
}

/** One drawing function per editor, so the card redraws an answer only when its text changes. */
const renderers = new WeakMap<Editor, (text: string) => DocumentFragment>()
function markdownRenderer(editor: Editor): (text: string) => DocumentFragment {
  let render = renderers.get(editor)
  if (!render) {
    render = (text) => answerDOM(editor, text)
    renderers.set(editor, render)
  }
  return render
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
      // An answer held back while it may still be a handoff (`heldBack`) isn't drawn yet.
      reply: session.answer && session.status === 'thinking' ? '' : session.reply,
      searching: session.searching,
      citations: session.citations,
      error: session.error,
      changes: changeTotal(session),
      style: session.style,
      lines: [
        ...session.units.map((unit) => ({
          key: unit.key,
          diff: session.edits.get(unit.key)?.diff ?? [{ type: 'same' as const, text: unit.text }]
        })),
        // The blocks to add, each a + line after the selection's.
        ...session.added.map((block, index) => ({
          key: `added:${index}`,
          diff: [{ type: 'add' as const, text: block.text }],
          added: true
        }))
      ],
      notes: session.notes,
      inserted: session.inserted,
      accepted: !!session.accepted
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
    onInsertNote: (index) => insertNote(editor, host, index),
    renderMarkdown: markdownRenderer(editor),
    onCopy: (text) => void navigator.clipboard?.writeText(text ?? session.reply).catch(() => {})
  }
  // The bar hangs under a picture's block, or under the last ghost of the blocks to add (not over them).
  const mediaBottom = () => {
    const dom = session.media ? editor.view.nodeDOM(session.units[0].from) : null
    if (dom instanceof HTMLElement) return dom.getBoundingClientRect()
    const ghost =
      session.added.length > 0
        ? [...editor.view.dom.querySelectorAll<HTMLElement>('.hk-ai-ghost.is-added')].at(-1)
        : undefined
    return ghost?.getBoundingClientRect() ?? null
  }
  renderAIReview(store.layer, props, () => {
    try {
      const box = mediaBottom()
      if (box) return new DOMRect(box.left, box.bottom, 1, 1)
      const coords = editor.view.coordsAtPos(Math.min(end, editor.state.doc.content.size))
      return new DOMRect(coords.left, coords.bottom, 1, 1)
    } catch {
      return null
    }
  })
  if (session.revealed !== session.status) {
    session.revealed = session.status
    const element = store.layer.element
    // After the layer has been drawn (next frames), so its height is known; measured from the selection's end, where
    // the bar belongs (with no room below, it would have flipped over the selection).
    requestAnimationFrame(() =>
      requestAnimationFrame(() => {
        try {
          const below =
            mediaBottom()?.bottom ??
            editor.view.coordsAtPos(Math.min(end, editor.state.doc.content.size)).bottom
          revealBelow(element, below)
        } catch {
          // The page changed meanwhile.
        }
      })
    )
  }
}

/** Space kept under the bar when the page scrolls to show it. */
const REVEAL_MARGIN = 24

/**
 * Scrolls the page up just enough that the bar fits under the selection's end (`anchorBottom`, in the window): a long
 * selection otherwise leaves it below the window.
 */
export function revealBelow(element: HTMLElement, anchorBottom: number): void {
  if (!element.isConnected) return
  const height = element.getBoundingClientRect().height
  const overflow = anchorBottom + height - (window.innerHeight - REVEAL_MARGIN)
  if (overflow <= 0) return
  const reduce = window.matchMedia?.('(prefers-reduced-motion: reduce)').matches ?? false
  window.scrollBy({ top: overflow, behavior: reduce ? 'auto' : 'smooth' })
}
