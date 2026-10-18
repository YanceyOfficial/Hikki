import type { Editor } from '@tiptap/core'
import type { Node as PMNode, ResolvedPos } from '@tiptap/pm/model'
import { NodeSelection, TextSelection, type EditorState, type Transaction } from '@tiptap/pm/state'

/**
 * Blocks as the user sees them (Notion): the unit the handle grabs, moves, duplicates and deletes. A
 * paragraph or heading on its own; a list item (with its nested items); a whole table, toggle, code block
 * or image. Units live directly in the page, a column, a callout, a quote or a toggle's content.
 */
export type BlockUnit = { pos: number; node: PMNode; depth: number }

const CONTAINERS = new Set(['doc', 'column', 'callout', 'blockquote', 'detailsContent'])
const ITEMS = new Set(['listItem', 'taskItem'])

/** The unit containing `$pos` (or the node right after it), innermost first; null outside the page. */
export function unitAt($pos: ResolvedPos): BlockUnit | null {
  for (let depth = $pos.depth; depth >= 1; depth--) {
    const node = $pos.node(depth)
    const parent = $pos.node(depth - 1)
    if (ITEMS.has(node.type.name) || (node.isBlock && CONTAINERS.has(parent.type.name))) {
      return { pos: $pos.before(depth), node, depth }
    }
  }
  // Between blocks at the top level (or on an atom): the node after the position.
  const after = $pos.nodeAfter
  if (after?.isBlock && CONTAINERS.has($pos.parent.type.name)) {
    return { pos: $pos.pos, node: after, depth: $pos.depth + 1 }
  }
  return null
}

/** The unit at a document position (inside its content or right before it). */
export function unitAtPos(state: EditorState, pos: number): BlockUnit | null {
  const clamped = Math.max(0, Math.min(pos, state.doc.content.size))
  const node = state.doc.nodeAt(clamped)
  // On an atom block (image, divider, formula): that block.
  if (node?.isBlock && node.isAtom) {
    const $pos = state.doc.resolve(clamped)
    if (CONTAINERS.has($pos.parent.type.name)) return { pos: clamped, node, depth: $pos.depth + 1 }
  }
  return unitAt(state.doc.resolve(clamped))
}

/**
 * Containers whose blocks share the container's handle (Notion): hovering anything inside a toggle, quote or
 * callout shows the + / ⋮⋮ of the whole container — the outermost one when they nest. Only the handle: drops
 * still land between the blocks inside, and caret commands (move up/down, duplicate) still act on the block
 * at the caret. Lists keep a handle per item, nested items too: each item is a block of its own (it drags out
 * of its list, indents and outdents), as in Notion.
 */
const HANDLE_OWNERS = new Set(['details', 'blockquote', 'callout'])

/** The unit the hover handle grabs at `pos`: the outermost toggle, quote or callout around it, else its unit. */
export function handleUnitAtPos(state: EditorState, pos: number): BlockUnit | null {
  const unit = unitAtPos(state, pos)
  if (!unit) return null
  const $pos = state.doc.resolve(unit.pos)
  for (let depth = 1; depth <= $pos.depth; depth++) {
    const node = $pos.node(depth)
    if (HANDLE_OWNERS.has(node.type.name)) return { pos: $pos.before(depth), node, depth }
  }
  return unit
}

/** Can a unit of this type go at `pos`? (List items only into lists; other blocks only into containers.) */
function fits(state: EditorState, pos: number, node: PMNode): boolean {
  const $pos = state.doc.resolve(pos)
  return $pos.parent.canReplaceWith($pos.index(), $pos.index(), node.type)
}

/**
 * Moves the unit at `from` to the gap at `to` (a position between blocks). Refuses a gap inside the unit
 * itself and gaps where the unit can't live (a list item outside a list goes in as a paragraph-like block:
 * it's unwrapped into its content). Returns null when nothing would change.
 */
export function moveUnit(state: EditorState, from: BlockUnit, to: number): Transaction | null {
  const end = from.pos + from.node.nodeSize
  if (to >= from.pos && to <= end) return null
  let content = [from.node]
  if (!fits(state, to, from.node)) {
    // A list item dropped outside a list: its blocks travel on their own.
    if (!ITEMS.has(from.node.type.name)) return null
    content = []
    from.node.forEach((child) => content.push(child))
    if (!content.every((child) => fits(state, to, child))) return null
  }
  const tr = state.tr.delete(from.pos, end)
  const at = tr.mapping.map(to, -1)
  tr.insert(at, content)
  selectMoved(tr, at, content[0])
  return tr.scrollIntoView()
}

function selectMoved(tr: Transaction, at: number, node: PMNode) {
  if (node.isAtom || !node.isBlock) tr.setSelection(NodeSelection.create(tr.doc, at))
  else tr.setSelection(TextSelection.near(tr.doc.resolve(at + 1)))
}

/** Copies the unit right below itself (new block ids are stamped by UniqueID). */
export function duplicateUnit(state: EditorState, unit: BlockUnit): Transaction {
  const end = unit.pos + unit.node.nodeSize
  const copy = unit.node.type.create(
    { ...unit.node.attrs, id: null },
    unit.node.content,
    unit.node.marks
  )
  const tr = state.tr.insert(end, copy)
  selectMoved(tr, end, copy)
  return tr.scrollIntoView()
}

export function deleteUnit(state: EditorState, unit: BlockUnit): Transaction {
  const tr = state.tr.delete(unit.pos, unit.pos + unit.node.nodeSize)
  const near = Math.min(unit.pos, tr.doc.content.size)
  tr.setSelection(TextSelection.near(tr.doc.resolve(near), -1))
  // The page always keeps a line to type on.
  if (tr.doc.childCount === 0) tr.insert(0, state.schema.nodes.paragraph.create())
  return tr.scrollIntoView()
}

/** The first text position inside a unit (where its first line starts), or null for blocks without text. */
export function firstTextPos(unit: BlockUnit): number | null {
  let found: number | null = null
  unit.node.descendants((node, offset) => {
    if (found !== null) return false
    if (node.isTextblock) {
      found = unit.pos + 1 + offset + 1
      return false
    }
    return true
  })
  if (found === null && unit.node.isTextblock) return unit.pos + 1
  return found
}

/**
 * From the start of the unit's first text to the end of its last (code left out): the range AI works on when the
 * block menu's Ask AI runs on a whole block. Null when the unit has no such text.
 */
export function unitTextRange(unit: BlockUnit): { from: number; to: number } | null {
  let from: number | null = null
  let to: number | null = null
  const take = (node: PMNode, start: number) => {
    if (node.type.spec.code || node.content.size === 0) return
    from ??= start
    to = start + node.content.size
  }
  if (unit.node.isTextblock) take(unit.node, unit.pos + 1)
  else
    unit.node.descendants((node, offset) => {
      if (!node.isTextblock) return true
      take(node, unit.pos + 1 + offset + 1)
      return false
    })
  return from === null || to === null ? null : { from, to }
}

/** Something a menu or panel acts on later, followed through the edits made meanwhile. */
export type Followed<T> = {
  /** Where it is now; null once it is gone. */
  readonly current: T | null
  stop(): void
}

/**
 * Follows the node at `pos` (a block unit, a formula) while a menu or panel is open on it, so an action
 * runs on that node where it is *now* — a remote reload or an edit may have moved it. Found again by its
 * block id when it has one (a reload replaces the whole page, which no mapping survives), else mapped like
 * `block-highlight` does. `onGone` runs once when the node no longer exists or the editor goes away.
 */
export function followNode(editor: Editor, pos: number, onGone: () => void): Followed<BlockUnit> {
  const start = editor.state.doc.nodeAt(pos)
  const id = (start?.attrs.id as string | null | undefined) ?? null
  let current: BlockUnit | null = start
    ? { pos, node: start, depth: editor.state.doc.resolve(pos).depth + 1 }
    : null
  const gone = () => {
    if (!current) return
    current = null
    stop()
    onGone()
  }
  const onTransaction = ({ transaction: tr }: { transaction: Transaction }) => {
    if (!current || !tr.docChanged) return
    const { doc } = tr
    let at: number | null = null
    if (id) {
      doc.descendants((node, offset) => {
        if (at !== null) return false
        if (node.attrs.id === id && node.type === current?.node.type) at = offset
        return at === null
      })
    } else {
      const from = tr.mapping.map(current.pos, 1)
      const to = tr.mapping.map(current.pos + current.node.nodeSize, -1)
      const node = from < to ? doc.nodeAt(from) : null
      if (node && node.type === current.node.type && from + node.nodeSize === to) at = from
    }
    const node = at === null ? null : doc.nodeAt(at)
    if (at === null || !node) return gone()
    current = { pos: at, node, depth: doc.resolve(at).depth + 1 }
  }
  const stop = () => {
    editor.off('transaction', onTransaction)
    editor.off('destroy', gone)
  }
  if (!current) onGone()
  else {
    editor.on('transaction', onTransaction)
    editor.on('destroy', gone)
  }
  return {
    get current() {
      return current
    },
    stop
  }
}

/**
 * Follows a caret position (where a panel will insert) through later edits; gone when the text around it
 * was replaced (a remote reload) or the editor goes away.
 */
export function followPosition(editor: Editor, pos: number, onGone: () => void): Followed<number> {
  let current: number | null = pos
  const gone = () => {
    if (current === null) return
    current = null
    stop()
    onGone()
  }
  const onTransaction = ({ transaction: tr }: { transaction: Transaction }) => {
    if (current === null || !tr.docChanged) return
    const mapped = tr.mapping.mapResult(current, -1)
    // Both sides deleted: the text around it was replaced. (One side alone is also a node being restamped —
    // UniqueID setting an id replaces the block's opening token.)
    if (mapped.deletedAcross) gone()
    else current = mapped.pos
  }
  const stop = () => {
    editor.off('transaction', onTransaction)
    editor.off('destroy', gone)
  }
  editor.on('transaction', onTransaction)
  editor.on('destroy', gone)
  return {
    get current() {
      return current
    },
    stop
  }
}
