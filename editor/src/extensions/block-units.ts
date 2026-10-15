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
