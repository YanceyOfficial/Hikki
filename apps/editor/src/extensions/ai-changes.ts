import { Extension, type Editor } from '@tiptap/core'
import type { Node as PMNode } from '@tiptap/pm/model'
import {
  Plugin,
  PluginKey,
  TextSelection,
  type EditorState,
  type Transaction
} from '@tiptap/pm/state'
import { Transform } from '@tiptap/pm/transform'
import { Decoration, DecorationSet } from '@tiptap/pm/view'

import { renderAIChangeBar } from '../components/ai-change-bar'
import { FloatingLayer } from '../components/floating'
import type { AIChangeInput, AIChangeStatus } from '../core/protocol'
import { fragmentText, parseInline, textBetween } from '../lib/ai-content'
import { diffText } from '../lib/ai-diff'

/**
 * Changes Ask AI proposes to the page (the chat's cards), reviewed one at a time in place: the change being looked at
 * shows as tracked changes on its block — a rewrite's removals struck through and additions in green, an inserted
 * block in green where it would go, a block to delete struck through, a moved block ghosted at its new place — with a
 * bar under it: Skip (⌫), Edit, Approve (↵). Each verdict goes to the next pending change. Nothing touches the page
 * until approved; an approval is one undo step, Approve all one step for all of them. A change whose blocks are edited
 * meanwhile goes stale (only that one). The native side keeps the cards and their verdicts (`aiChange`).
 */
export type AIChangesHost = {
  report: (id: string, status: AIChangeStatus, before?: string, after?: string) => void
  focused: (id: string | null) => void
}

type Change = AIChangeInput & {
  /** The text of each block the change names, when it was proposed: an edit to any of them makes it stale. */
  basis: Map<string, string>
}

type Storage = {
  changes: Change[]
  focused: string | null
  /** ↵ / ⌫ act on the focused change until the reader moves the caret or types. */
  armed: boolean
  layer: FloatingLayer | null
}

export const AIChangesKey = new PluginKey<DecorationSet>('aiChanges')

/** Blocks a list item's text sits in: a change to its text moves or removes the whole item. */
const ITEM_TYPES = new Set(['listItem', 'taskItem'])
const LIST_TYPES = new Set(['bulletList', 'orderedList', 'taskList'])

export function AIChanges(host: AIChangesHost) {
  return Extension.create<Record<string, never>, Storage>({
    name: 'aiChanges',

    addStorage() {
      return { changes: [], focused: null, armed: false, layer: null }
    },

    addCommands() {
      // Each runs its own transactions (the command's own is left undispatched).
      return {
        aiSetChanges:
          (list: AIChangeInput[]) =>
          ({ editor, tr }) => {
            tr.setMeta('preventDispatch', true)
            setChanges(editor, host, list)
            return true
          },
        aiFocusChange:
          (id: string) =>
          ({ editor, tr }) => {
            tr.setMeta('preventDispatch', true)
            return focus(editor, host, id)
          },
        aiResolveChange:
          (id: string, verdict: Verdict) =>
          ({ editor, tr }) => {
            tr.setMeta('preventDispatch', true)
            return resolve(editor, host, id, verdict)
          },
        aiApproveAllChanges:
          () =>
          ({ editor, tr }) => {
            tr.setMeta('preventDispatch', true)
            return approveAll(editor, host)
          }
      }
    },

    addProseMirrorPlugins() {
      const editor = this.editor
      return [
        new Plugin<DecorationSet>({
          key: AIChangesKey,
          state: {
            init: () => DecorationSet.empty,
            apply: (tr, set, _old, state) => {
              if (tr.getMeta(AIChangesKey) || tr.docChanged)
                return decorations(state, storage(editor))
              return set
            }
          },
          props: {
            decorations: (state) => AIChangesKey.getState(state),
            handleKeyDown: (_view, event) => {
              const store = storage(editor)
              if (!store.focused || !store.armed || event.isComposing) return false
              if (event.metaKey || event.ctrlKey || event.altKey || event.shiftKey) return false
              if (event.key === 'Enter') return resolve(editor, host, store.focused, 'approve')
              if (event.key === 'Backspace') return resolve(editor, host, store.focused, 'skip')
              return false
            }
          },
          appendTransaction: (transactions) => {
            const store = storage(editor)
            if (store.changes.length === 0) return null
            const theirs = transactions.filter((tr) => !tr.getMeta(AIChangesKey))
            if (theirs.some((tr) => tr.selectionSet || tr.docChanged)) store.armed = false
            if (theirs.some((tr) => tr.docChanged)) queueMicrotask(() => checkStale(editor, host))
            return null
          }
        })
      ]
    },

    onDestroy() {
      this.storage.layer?.destroy()
      this.storage.layer = null
      this.storage.changes = []
      this.storage.focused = null
    }
  })
}

type Verdict = 'approve' | 'skip' | 'edit'

declare module '@tiptap/core' {
  interface Commands<ReturnType> {
    aiChanges: {
      /** The changes an Ask AI answer proposes (the pending ones are offered; others only remembered). */
      aiSetChanges: (list: AIChangeInput[]) => ReturnType
      /** Show a change in the page: its block in view, the bar under it. */
      aiFocusChange: (id: string) => ReturnType
      /** Approve (one undo step), skip, or approve and put the caret there to change it further. */
      aiResolveChange: (id: string, verdict: Verdict) => ReturnType
      /** Every pending change, as one undo step. */
      aiApproveAllChanges: () => ReturnType
    }
  }
}

function storage(editor: Editor): Storage {
  return (editor.storage as unknown as Record<string, Storage>).aiChanges
}

const pending = (store: Storage) => store.changes.filter((c) => c.status === 'pending')

/** Every block with an id in `doc`, with where it starts. */
function blocksById(doc: PMNode): Map<string, { node: PMNode; pos: number }> {
  const out = new Map<string, { node: PMNode; pos: number }>()
  doc.descendants((node, pos) => {
    const id = node.attrs.id as string | undefined
    if (id && !out.has(id)) out.set(id, { node, pos })
    return !node.isTextblock
  })
  return out
}

/** The text block a change names (a list item's id means its first paragraph). */
function textblock(doc: PMNode, id: string): { node: PMNode; pos: number } | null {
  const found = blocksById(doc).get(id)
  if (!found) return null
  if (found.node.isTextblock) return found
  const first = found.node.firstChild
  return first?.isTextblock ? { node: first, pos: found.pos + 1 } : null
}

/** What moves or goes when a block does: a list item's text takes its item along (and an item alone, its list). */
function unitRange(
  doc: PMNode,
  id: string,
  removing = false
): { from: number; to: number; node: PMNode } | null {
  const found = blocksById(doc).get(id)
  if (!found) return null
  const $pos = doc.resolve(found.pos)
  let depth = $pos.depth
  let node = found.node
  let from = found.pos
  if (
    node.isTextblock &&
    depth > 0 &&
    ITEM_TYPES.has($pos.parent.type.name) &&
    $pos.index() === 0
  ) {
    node = $pos.parent
    from = $pos.before(depth)
    depth -= 1
  }
  // Removing a list's only item removes the list.
  if (removing && ITEM_TYPES.has(node.type.name) && depth > 0) {
    const $item = doc.resolve(from)
    if (LIST_TYPES.has($item.parent.type.name) && $item.parent.childCount === 1) {
      node = $item.parent
      from = $item.before($item.depth)
    }
  }
  return { from, to: from + node.nodeSize, node }
}

function textOf(doc: PMNode, id: string | undefined): string | null {
  if (!id) return null
  const found = blocksById(doc).get(id)
  return found ? found.node.textContent : null
}

function basisOf(doc: PMNode, change: AIChangeInput): Map<string, string> | null {
  const basis = new Map<string, string>()
  for (const id of [change.block, change.after]) {
    if (!id) continue
    const text = textOf(doc, id)
    if (text === null) return null
    basis.set(id, text)
  }
  return basis
}

function setChanges(editor: Editor, host: AIChangesHost, list: AIChangeInput[]): void {
  const store = storage(editor)
  const doc = editor.state.doc
  store.changes = []
  for (const input of list) {
    const basis = basisOf(doc, input)
    const fits = basis && (input.kind !== 'rewrite' || canRewrite(doc, input.block))
    if (!fits && input.status === 'pending') {
      host.report(input.id, 'stale')
      continue
    }
    store.changes.push({ ...input, basis: basis ?? new Map() })
  }
  if (store.focused && !pending(store).some((c) => c.id === store.focused)) unfocus(editor, host)
  redraw(editor, host)
}

function canRewrite(doc: PMNode, id: string | undefined): boolean {
  const block = id ? textblock(doc, id) : null
  return !!block && !block.node.type.spec.code
}

/** Pending changes whose blocks were edited (here or by a reload) go stale. */
function checkStale(editor: Editor, host: AIChangesHost): void {
  if (editor.isDestroyed) return
  const store = storage(editor)
  const blocks = blocksById(editor.state.doc)
  let changed = false
  for (const change of pending(store)) {
    const intact = [...change.basis].every(
      ([id, text]) => blocks.get(id)?.node.textContent === text
    )
    if (intact) continue
    change.status = 'stale'
    host.report(change.id, 'stale')
    changed = true
    if (store.focused === change.id) unfocus(editor, host)
  }
  if (changed) redraw(editor, host)
}

function focus(editor: Editor, host: AIChangesHost, id: string): boolean {
  const store = storage(editor)
  const change = pending(store).find((c) => c.id === id)
  if (!change) return false
  store.focused = id
  store.armed = true
  host.focused(id)
  const anchorId = change.block ?? change.after
  const target = anchorId ? blocksById(editor.state.doc).get(anchorId) : null
  // The caret to the block (the page takes the keyboard for ↵ / ⌫), the block into view.
  const at = target ? Math.min(target.pos + 1, editor.state.doc.content.size) : 0
  editor.view.dispatch(
    editor.state.tr
      .setSelection(TextSelection.near(editor.state.doc.resolve(at)))
      .setMeta(AIChangesKey, true)
      .setMeta('addToHistory', false)
  )
  editor.view.focus()
  const dom = target ? editor.view.nodeDOM(target.pos) : editor.view.dom.firstElementChild
  const reduce = window.matchMedia?.('(prefers-reduced-motion: reduce)').matches ?? false
  if (dom instanceof Element)
    dom.scrollIntoView({ block: 'center', behavior: reduce ? 'auto' : 'smooth' })
  draw(editor, host)
  return true
}

function unfocus(editor: Editor, host: AIChangesHost): void {
  const store = storage(editor)
  if (!store.focused) return
  store.focused = null
  store.armed = false
  store.layer?.destroy()
  store.layer = null
  host.focused(null)
}

type Applied = { before: string; after: string; caret: number }

/**
 * Applies a change in `tr` (blocks found by id in `tr.doc`), all or nothing: worked out on a copy, its steps added to
 * `tr` only when every one fits. Null when the change no longer fits the page.
 */
function apply(editor: Editor, tr: Transaction, change: Change): Applied | null {
  const work = new Transform(tr.doc)
  let result: Applied | null = null
  try {
    result = applyTo(editor, work, change)
  } catch {
    return null
  }
  if (!result) return null
  for (const step of work.steps) tr.step(step)
  return result
}

function applyTo(editor: Editor, tr: Transform, change: Change): Applied | null {
  const schema = editor.schema
  switch (change.kind) {
    case 'rewrite': {
      const block = change.block ? textblock(tr.doc, change.block) : null
      const fragment = change.html === undefined ? null : parseInline(schema, change.html)
      if (!block || !fragment || block.node.type.spec.code) return null
      const before = block.node.textContent
      tr.replaceWith(block.pos + 1, block.pos + block.node.nodeSize - 1, fragment)
      return { before, after: fragmentText(fragment), caret: block.pos + 1 + fragment.size }
    }
    case 'insert': {
      const fragment = parseInline(schema, change.html ?? '')
      if (!fragment) return null
      const unit = change.after ? unitRange(tr.doc, change.after) : null
      if (change.after && !unit) return null
      const node = newBlock(editor, change.type, fragment, unit?.node)
      if (!node) return null
      const at = unit ? unit.to : 0
      tr.insert(at, node)
      return { before: '', after: fragmentText(fragment), caret: at + node.nodeSize - 1 }
    }
    case 'move': {
      const unit = change.block ? unitRange(tr.doc, change.block) : null
      if (!unit) return null
      if (change.after && !unitRange(tr.doc, change.after)) return null
      tr.delete(unit.from, unit.to)
      const target = change.after ? unitRange(tr.doc, change.after) : null
      if (change.after && !target) return null
      const at = target ? target.to : 0
      tr.insert(at, unit.node)
      const text = unit.node.textContent
      return { before: text, after: text, caret: at + unit.node.nodeSize - 1 }
    }
    case 'delete': {
      const unit = change.block ? unitRange(tr.doc, change.block, true) : null
      if (!unit) return null
      const before = unit.node.textContent
      tr.delete(unit.from, unit.to)
      return { before, after: '', caret: Math.min(unit.from, tr.doc.content.size) }
    }
  }
  return null
}

/** The block an insert adds: the next item after a list item, else a paragraph or heading. */
function newBlock(
  editor: Editor,
  type: string | undefined,
  content: ReturnType<typeof parseInline>,
  after: PMNode | undefined
): PMNode | null {
  const { nodes } = editor.schema
  const paragraph = nodes.paragraph.create(null, content)
  if (after && ITEM_TYPES.has(after.type.name)) return after.type.createAndFill(null, paragraph)
  const level = /^heading([1-3])$/u.exec(type ?? '')?.[1]
  if (level && nodes.heading) return nodes.heading.create({ level: Number(level) }, content)
  return paragraph
}

function resolve(editor: Editor, host: AIChangesHost, id: string, verdict: Verdict): boolean {
  const store = storage(editor)
  const change = pending(store).find((c) => c.id === id)
  if (!change || !editor.isEditable) return false
  const order = pending(store)
  const next = order[order.indexOf(change) + 1] ?? order.find((c) => c !== change)
  if (verdict === 'skip') {
    change.status = 'skipped'
    host.report(
      id,
      'skipped',
      textOf(editor.state.doc, change.block) ?? '',
      proposedText(editor, change)
    )
  } else {
    const tr = editor.state.tr
    const result = apply(editor, tr, change)
    if (result) {
      change.status = verdict === 'edit' ? 'edited' : 'approved'
      if (verdict === 'edit') placeCaret(tr, result.caret)
      tr.setMeta(AIChangesKey, true)
      editor.view.dispatch(tr)
      rebase(editor)
      host.report(id, change.status, result.before, result.after)
    } else {
      change.status = 'stale'
      host.report(id, 'stale')
    }
  }
  if (verdict === 'edit' && change.status === 'edited') {
    unfocus(editor, host)
    editor.view.focus()
  } else if (next && next.status === 'pending') {
    focus(editor, host, next.id)
  } else {
    unfocus(editor, host)
  }
  redraw(editor, host)
  return true
}

/** After Edit: the caret at the end of the changed (or new) block. */
function placeCaret(tr: Transaction, caret: number): void {
  const $at = tr.doc.resolve(Math.max(0, Math.min(caret, tr.doc.content.size)))
  tr.setSelection(TextSelection.near($at, -1))
}

/** What a skipped change would have made the block say (for the reviewed stack). */
function proposedText(editor: Editor, change: Change): string {
  if (change.kind === 'delete') return ''
  if (change.kind === 'move') return textOf(editor.state.doc, change.block) ?? ''
  const fragment = parseInline(editor.schema, change.html ?? '')
  return fragment ? fragmentText(fragment) : ''
}

/** The other pending changes take the page as it is after an approval (their own blocks didn't change by it). */
function rebase(editor: Editor): void {
  const doc = editor.state.doc
  for (const change of pending(storage(editor))) {
    const basis = basisOf(doc, change)
    if (basis) change.basis = basis
  }
}

function approveAll(editor: Editor, host: AIChangesHost): boolean {
  const store = storage(editor)
  const todo = pending(store)
  if (todo.length === 0 || !editor.isEditable) return false
  const tr = editor.state.tr
  const reports: [Change, Applied | null][] = todo.map((change) => [
    change,
    apply(editor, tr, change)
  ])
  tr.setMeta(AIChangesKey, true)
  editor.view.dispatch(tr)
  for (const [change, result] of reports) {
    change.status = result ? 'approved' : 'stale'
    host.report(change.id, change.status, result?.before, result?.after)
  }
  unfocus(editor, host)
  redraw(editor, host)
  return true
}

function redraw(editor: Editor, host: AIChangesHost): void {
  if (editor.isDestroyed) return
  editor.view.dispatch(editor.state.tr.setMeta(AIChangesKey, true).setMeta('addToHistory', false))
  draw(editor, host)
}

/** The pending changes on the page: each one's block marked, the focused one drawn as tracked changes. */
function decorations(state: EditorState, store: Storage): DecorationSet {
  const changes = pending(store)
  if (changes.length === 0) return DecorationSet.empty
  const blocks = blocksById(state.doc)
  const decos: Decoration[] = []
  for (const change of changes) {
    const focused = change.id === store.focused
    const target = change.block ? blocks.get(change.block) : undefined
    if (target)
      decos.push(
        Decoration.node(target.pos, target.pos + target.node.nodeSize, {
          class: focused ? `hk-ai-change is-focused is-${change.kind}` : 'hk-ai-change'
        })
      )
    if (!focused) continue
    if (change.kind === 'rewrite' && change.block) {
      const block = textblock(state.doc, change.block)
      const fragment = parseInline(state.schema, change.html ?? '')
      if (block && fragment) decos.push(...rewriteMarks(state, block, fragmentText(fragment)))
    }
    if (change.kind === 'delete' && target) {
      const block = textblock(state.doc, change.block!)
      if (block && block.node.content.size > 0)
        decos.push(
          Decoration.inline(block.pos + 1, block.pos + block.node.nodeSize - 1, {
            class: 'hk-ai-del'
          })
        )
    }
    if (change.kind === 'insert' || change.kind === 'move') {
      const unit = change.after ? unitRange(state.doc, change.after) : null
      const at = unit ? unit.to : 0
      const text =
        change.kind === 'move'
          ? (target?.node.textContent ?? '')
          : fragmentText(
              parseInline(state.schema, change.html ?? '') ??
                state.schema.nodes.paragraph.create().content
            )
      decos.push(
        Decoration.widget(at, () => ghost(text, change), {
          side: 1,
          key: `${change.id}:${at}:${text}`
        })
      )
    }
  }
  return DecorationSet.create(state.doc, decos)
}

/** A rewrite's removals struck through and its additions beside them (as the selection's review draws them). */
function rewriteMarks(
  state: EditorState,
  block: { node: PMNode; pos: number },
  next: string
): Decoration[] {
  const from = block.pos + 1
  const to = block.pos + block.node.nodeSize - 1
  const { text, positions } = textBetween(state.doc, from, to)
  const decos: Decoration[] = []
  let index = 0
  for (const segment of diffText(text, next)) {
    const length = [...segment.text].length
    if (segment.type === 'same') {
      index += length
    } else if (segment.type === 'del') {
      const start = positions[index] ?? to
      const end = positions[index + length] ?? to
      if (end > start) decos.push(Decoration.inline(start, end, { class: 'hk-ai-del' }))
      index += length
    } else {
      const at = positions[index] ?? to
      decos.push(
        Decoration.widget(
          at,
          () => {
            const span = document.createElement('span')
            span.className = 'hk-ai-ins'
            span.textContent = segment.text
            return span
          },
          { side: -1, key: `ins:${index}:${segment.text}` }
        )
      )
    }
  }
  return decos
}

/** Where an inserted or moved block would go: its text, in green, between the blocks. */
function ghost(text: string, change: Change): HTMLElement {
  const div = document.createElement('div')
  const heading =
    change.kind === 'insert' ? /^heading([1-3])$/u.exec(change.type ?? '')?.[1] : undefined
  div.className = `hk-ai-ghost is-${change.kind}`
  if (heading) div.dataset.level = heading
  div.contentEditable = 'false'
  div.textContent = text
  return div
}

/** The bar under the focused change. */
function draw(editor: Editor, host: AIChangesHost): void {
  const store = storage(editor)
  const change = store.focused ? pending(store).find((c) => c.id === store.focused) : undefined
  if (!change) {
    store.layer?.destroy()
    store.layer = null
    return
  }
  store.layer ??= new FloatingLayer('hk-ai-change-bar', { onDismiss: () => unfocus(editor, host) })
  const all = store.changes.filter((c) => c.status !== 'stale')
  renderAIChangeBar(
    store.layer,
    {
      kind: change.kind,
      title: change.title,
      why: change.why ?? null,
      position: all.indexOf(change) + 1,
      total: all.length,
      onApprove: () => resolve(editor, host, change.id, 'approve'),
      onSkip: () => resolve(editor, host, change.id, 'skip'),
      onEdit: () => resolve(editor, host, change.id, 'edit')
    },
    () => anchorRect(editor, change)
  )
}

/** Under the change: its block, or the ghost of an inserted / moved one. */
function anchorRect(editor: Editor, change: Change): DOMRect | null {
  const root = editor.view.dom
  const ghostEl = root.querySelector('.hk-ai-ghost')
  const el =
    change.kind === 'insert' || change.kind === 'move'
      ? ghostEl
      : root.querySelector('.hk-ai-change.is-focused')
  if (!(el instanceof HTMLElement)) return null
  const rect = el.getBoundingClientRect()
  return new DOMRect(rect.left, rect.bottom, Math.min(rect.width, 1), 1)
}
