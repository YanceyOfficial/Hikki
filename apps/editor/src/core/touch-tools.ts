import type { Editor } from '@tiptap/core'
import type { Node as PMNode, ResolvedPos } from '@tiptap/pm/model'
import { TextSelection, type Transaction } from '@tiptap/pm/state'

import { BLOCK_UNIT_ACTIONS } from '../extensions/block-units'
import { deleteUnit, duplicateUnit, unitAtPos, unitTextRange } from '../extensions/block-units'
import { BLOCK_COLOR_TYPES, PALETTE, type PaletteColor } from '../extensions/colors'
import { blockQuote } from '../extensions/comments'
import { mediaKindOf, safeMediaSrc, storedFileNode } from '../extensions/media'
import { moveUnitTo } from '../extensions/move-block'
import { blockCounts, blockKindLabel, unitTypeId } from './block-kinds'
import {
  BLOCK_GROUPS,
  BLOCK_TYPES,
  isAvailable,
  TURN_INTO,
  type BlockGroup,
  type BlockType
} from './blocks'
import { t } from './i18n'

/**
 * What the phone's keyboard bar (native, `KeyboardToolbar`) does to the page: its panels' contents — the block
 * catalog for "+", Turn into / marks / colours for "Aa" — and its tools. The catalog stays the "/" menu's
 * (`BLOCK_TYPES`), handed over as plain values: ids, localized names and Phosphor icon names (the native icon set
 * uses the same names).
 */
export type TouchBlock = { id: string; label: string; icon: string | null }
export type TouchBlockGroup = { id: BlockGroup; label: string; blocks: TouchBlock[] }

const GROUP_LABEL: Record<BlockGroup, () => string> = {
  basic: () => t('slash.group.basic'),
  lists: () => t('slash.group.lists'),
  media: () => t('slash.group.media'),
  embeds: () => t('slash.group.embeds'),
  other: () => t('slash.group.other'),
  advanced: () => t('slash.group.advanced')
}

/** A Phosphor component's name as the icon set spells it (`TextHOneIcon` → `text-h-one`); null for a brand logo. */
export function phosphorName(icon: BlockType['icon']): string | null {
  const name = (icon as { displayName?: string }).displayName
  if (!name?.endsWith('Icon')) return null
  return name
    .slice(0, -'Icon'.length)
    .replaceAll(/(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])/gu, '-')
    .toLowerCase()
}

/** The "+" panel: the "/" menu's groups, the embed services folded into the one Embed block. */
export function touchBlockMenu(): TouchBlockGroup[] {
  return BLOCK_GROUPS.map((group) => ({
    id: group,
    label: GROUP_LABEL[group](),
    blocks: BLOCK_TYPES.filter(
      (b) => isAvailable(b) && b.group === group && (group !== 'embeds' || b.id === 'embed')
    ).map((b) => ({ id: b.id, label: b.label(), icon: phosphorName(b.icon) }))
  })).filter((g) => g.blocks.length > 0)
}

/** "Turn into" in the Aa panel: the blocks with text. */
export function touchTurnIntoMenu(): TouchBlock[] {
  return BLOCK_TYPES.filter((b) => b.turnInto && b.group !== 'embeds').map((b) => ({
    id: b.id,
    label: b.label(),
    icon: phosphorName(b.icon)
  }))
}

/** Container types a new block goes after as a whole (a block added in a list item goes below the list). */
const WHOLE = new Set(['listItem', 'taskItem', 'bulletList', 'orderedList', 'taskList'])

/**
 * "+": the block where the caret is becomes it when empty; otherwise it goes on a new line below — after the
 * caret's block, or after the whole list it is in.
 */
export function touchInsertBlock(editor: Editor, id: string): boolean {
  const block = BLOCK_TYPES.find((b) => b.id === id)
  if (!block || !editor.isEditable) return false
  const { $from } = editor.state.selection
  const empty = $from.parent.isTextblock && $from.parent.content.size === 0
  if (
    !empty ||
    $from.parent.type.name !== 'paragraph' ||
    WHOLE.has($from.node(-1)?.type.name ?? '')
  ) {
    let depth = $from.depth
    while (depth > 1 && WHOLE.has($from.node(depth - 1).type.name)) depth -= 1
    const end = $from.after(depth)
    const tr = editor.state.tr.insert(end, editor.schema.nodes.paragraph.create())
    tr.setSelection(TextSelection.create(tr.doc, end + 1))
    editor.view.dispatch(tr)
  }
  const done = block.apply(editor.chain().focus()).run()
  if (done) block.after?.(editor)
  return done
}

/** A file the phone's native sheet stored (Photos, the camera, Files, a scan), to go in at the caret. */
export type TouchMedia = { src: string; name: string; size: number }

/**
 * The phone's photo / file sheet: the stored files go in as blocks (by their kind) where "+" puts a block — in place
 * of an empty line, else after the caret's block or the whole list it is in — with the caret after them.
 */
export function touchInsertMedia(editor: Editor, items: TouchMedia[]): boolean {
  if (!editor.isEditable) return false
  const nodes = items.flatMap((item) => {
    const kind = mediaKindOf({ type: '', name: item.name })
    const src = safeMediaSrc(item.src, kind)
    return src ? [storedFileNode(editor.schema, kind, src, item)] : []
  })
  if (nodes.length === 0) return false
  editor.view.dispatch(
    insertBlocksAt(editor.state.tr, nodes, editor.state.selection.$from).scrollIntoView()
  )
  return true
}

/**
 * Blocks put in where "+" puts one, from `$from` — in place of an empty line, else after its block or the whole list
 * it is in — with the caret on the line after them (a new one unless a text line follows).
 */
export function insertBlocksAt(tr: Transaction, nodes: PMNode[], $from: ResolvedPos): Transaction {
  const size = nodes.reduce((sum, node) => sum + node.nodeSize, 0)
  let start: number
  if (
    $from.parent.type.name === 'paragraph' &&
    $from.parent.content.size === 0 &&
    !WHOLE.has($from.node(-1)?.type.name ?? '')
  ) {
    start = $from.before()
    tr.replaceWith(start, $from.after(), nodes)
  } else {
    let depth = $from.depth
    while (depth > 1 && WHOLE.has($from.node(depth - 1).type.name)) depth -= 1
    start = $from.after(depth)
    tr.insert(start, nodes)
  }
  const after = start + size
  if (!tr.doc.nodeAt(after)?.isTextblock)
    tr.insert(after, nodes[0].type.schema.nodes.paragraph.create())
  return tr.setSelection(TextSelection.create(tr.doc, after + 1))
}

export function touchTurnInto(editor: Editor, id: string): boolean {
  const block = BLOCK_TYPES.find((b) => b.id === id)
  if (!block?.turnInto || !editor.isEditable) return false
  const done = block.turnInto(editor.chain().focus()).run()
  if (done) block.after?.(editor)
  return done
}

/** What the bar and the Aa panel show as on: the caret's block, the marks and colours, what applies. */
export type TouchState = {
  block: string
  marks: string[]
  textColor: PaletteColor | null
  bgColor: PaletteColor | null
  selection: boolean
  canIndent: boolean
  canOutdent: boolean
  canUndo: boolean
}

const MARKS = ['bold', 'italic', 'underline', 'strike', 'code', 'link'] as const

export function touchState(editor: Editor): TouchState {
  const style = editor.getAttributes('textStyle')
  const item = editor.isActive('taskItem') ? 'taskItem' : 'listItem'
  return {
    block: BLOCK_TYPES.find((b) => b.turnInto && b.isActive?.(editor))?.id ?? 'paragraph',
    marks: MARKS.filter((mark) => editor.isActive(mark)),
    textColor: (style.textColor as PaletteColor | undefined) ?? null,
    bgColor: (style.bgColor as PaletteColor | undefined) ?? null,
    selection: !editor.state.selection.empty,
    canIndent: editor.can().sinkListItem(item),
    canOutdent: editor.can().liftListItem(item),
    canUndo: editor.can().undo()
  }
}

/** The bar's tools that act at once (the panels and the AI / link fields are the bridge's). */
export type TouchTool =
  | 'bold'
  | 'italic'
  | 'underline'
  | 'strike'
  | 'code'
  | 'indent'
  | 'outdent'
  | 'undo'
  | 'redo'
  | 'mention'
  | 'todo'
  | 'comment'
  | 'delete'
  | 'duplicate'
  | 'moveUp'
  | 'moveDown'

export function touchRun(editor: Editor, tool: TouchTool): boolean {
  if (!editor.isEditable && tool !== 'comment') return false
  const chain = editor.chain().focus()
  const item = editor.isActive('taskItem') ? 'taskItem' : 'listItem'
  switch (tool) {
    case 'bold':
      return chain.toggleBold().run()
    case 'italic':
      return chain.toggleItalic().run()
    case 'underline':
      return chain.toggleUnderline().run()
    case 'strike':
      return chain.toggleStrike().run()
    case 'code':
      return chain.toggleCode().run()
    case 'indent':
      return chain.sinkListItem(item).run()
    case 'outdent':
      return chain.liftListItem(item).run()
    case 'undo':
      return chain.undo().run()
    case 'redo':
      return chain.redo().run()
    case 'mention':
      return chain.insertContent(trigger(editor, '@')).run()
    case 'todo':
      return chain.toggleTaskList().run()
    case 'comment':
      return editor.commands.commentStart()
    case 'delete': {
      const unit = unitAtPos(editor.state, editor.state.selection.from)
      if (!unit) return false
      editor.view.dispatch(deleteUnit(editor.state, unit))
      return true
    }
    case 'duplicate':
      return BLOCK_UNIT_ACTIONS.duplicateBlock?.(editor) ?? false
    case 'moveUp':
      return BLOCK_UNIT_ACTIONS.moveBlockUp?.(editor) ?? false
    case 'moveDown':
      return BLOCK_UNIT_ACTIONS.moveBlockDown?.(editor) ?? false
  }
}

/** A suggestion's trigger character, a space first when it would stick to a word (suggestions start after one). */
function trigger(editor: Editor, char: string): string {
  return /\S$/u.test(editor.state.selection.$from.nodeBefore?.text ?? '') ? ` ${char}` : char
}

/**
 * The ⋯ sheet (Notion's block actions) for the block at the caret: what it is, what applies to it — Turn into (its
 * catalog id), its colours, a comment, AI — and its words and characters.
 */
export type TouchBlockInfo = {
  kind: string
  turnInto: string | null
  textColor: PaletteColor | null
  backgroundColor: PaletteColor | null
  colorable: boolean
  comment: boolean
  ai: boolean
  words: number | null
  characters: number | null
  /** Move to another page is offered (the page isn't read-only; the app lists the pages). */
  movable: boolean
}

export function touchBlockInfo(editor: Editor): TouchBlockInfo | null {
  const unit = unitAtPos(editor.state, editor.state.selection.from)
  if (!unit) return null
  const type = unitTypeId(editor, unit)
  const counts = blockCounts(unit.node)
  const hasText = unitTextRange(unit) !== null
  const editable = editor.isEditable
  return {
    kind: blockKindLabel(unit.node, editor.state.doc.resolve(unit.pos)),
    turnInto: editable && TURN_INTO.some((b) => b.id === type) ? type : null,
    textColor: (unit.node.attrs.blockColor as PaletteColor | null | undefined) ?? null,
    backgroundColor: (unit.node.attrs.blockBackground as PaletteColor | null | undefined) ?? null,
    colorable: editable && BLOCK_COLOR_TYPES.includes(unit.node.type.name),
    comment: editable && (hasText || typeof unit.node.attrs.id === 'string'),
    ai: editable && hasText,
    words: counts?.words ?? null,
    characters: counts?.characters ?? null,
    movable: editable
  }
}

/** The ⋯ sheet's Move to: the caret's block to the end of page `target` (`moveUnitTo`). */
export function touchMoveBlock(editor: Editor, target: string): Promise<boolean> {
  const unit = unitAtPos(editor.state, editor.state.selection.from)
  return unit ? moveUnitTo(editor, unit, target) : Promise.resolve(false)
}

/** The ⋯ sheet's actions on the caret's block (Turn into is `touchTurnInto`, AI the bar's own field). */
export type TouchBlockAction = 'insertBelow' | 'duplicate' | 'delete' | 'comment' | 'selectText'

export function touchBlockAction(editor: Editor, action: TouchBlockAction): boolean {
  const unit = unitAtPos(editor.state, editor.state.selection.from)
  if (!unit || (!editor.isEditable && action !== 'comment')) return false
  switch (action) {
    case 'insertBelow': {
      const end = unit.pos + unit.node.nodeSize
      const tr = editor.state.tr.insert(end, editor.schema.nodes.paragraph.create())
      tr.setSelection(TextSelection.create(tr.doc, end + 1))
      editor.view.dispatch(tr.scrollIntoView())
      return true
    }
    case 'duplicate':
      editor.view.dispatch(duplicateUnit(editor.state, unit))
      return true
    case 'delete':
      editor.view.dispatch(deleteUnit(editor.state, unit))
      return true
    case 'comment': {
      // On its text (a passage), or — a block without text — on the whole block.
      const range = unitTextRange(unit)
      if (!range) {
        const kind = blockKindLabel(unit.node, editor.state.doc.resolve(unit.pos))
        return editor.commands.commentStartBlock(unit.pos, blockQuote(unit.node, kind))
      }
      editor.view.dispatch(
        editor.state.tr.setSelection(TextSelection.create(editor.state.doc, range.from, range.to))
      )
      return editor.commands.commentStart()
    }
    case 'selectText': {
      // What Ask AI then acts on: the block's text.
      const range = unitTextRange(unit)
      if (!range) return false
      editor.view.dispatch(
        editor.state.tr.setSelection(TextSelection.create(editor.state.doc, range.from, range.to))
      )
      return true
    }
  }
}

/** The ⋯ sheet's Color: the block's own text or background colour (null clears it). */
export function touchBlockColor(
  editor: Editor,
  kind: 'text' | 'background',
  color: string | null
): boolean {
  const unit = unitAtPos(editor.state, editor.state.selection.from)
  if (!unit || !editor.isEditable || !BLOCK_COLOR_TYPES.includes(unit.node.type.name)) return false
  const value = (PALETTE as readonly string[]).includes(color ?? '') ? color : null
  const attrs = kind === 'text' ? { blockColor: value } : { blockBackground: value }
  editor.view.dispatch(
    editor.state.tr.setNodeMarkup(unit.pos, undefined, { ...unit.node.attrs, ...attrs })
  )
  return true
}

/** A colour from the Aa panel; null clears it. */
export function touchSetColor(
  editor: Editor,
  kind: 'text' | 'background',
  color: string | null
): boolean {
  const value = (PALETTE as readonly string[]).includes(color ?? '')
    ? (color as PaletteColor)
    : null
  const chain = editor.chain().focus()
  return (kind === 'text' ? chain.setTextColor(value) : chain.setBackgroundColor(value)).run()
}

/** With the caret only, the word around it (or else its block's text) becomes the selection — what AI and a link act on. */
export function selectAroundCaret(editor: Editor): boolean {
  const { selection, doc } = editor.state
  if (!selection.empty) return true
  const { $from } = selection
  if (!$from.parent.isTextblock || $from.parent.content.size === 0) return false
  const text = $from.parent.textContent
  const offset = $from.parentOffset
  const start = $from.start()
  let from = offset
  let to = offset
  while (from > 0 && /[\p{L}\p{N}_-]/u.test(text[from - 1])) from -= 1
  while (to < text.length && /[\p{L}\p{N}_-]/u.test(text[to])) to += 1
  if (from === to) {
    from = 0
    to = text.length
  }
  editor.view.dispatch(
    editor.state.tr.setSelection(TextSelection.create(doc, start + from, start + to))
  )
  return true
}

/**
 * The phone's AI field acts on the selection — or, with none, on the caret's whole block (its text, as a comment
 * takes it), now selected. False with nothing to act on (an empty block, code).
 */
export function selectBlockAtCaret(editor: Editor): boolean {
  const { state } = editor
  if (!state.selection.empty) return true
  const unit = unitAtPos(state, state.selection.from)
  if (!unit || unit.node.type.spec.code) return false
  const range = unitTextRange(unit)
  if (!range || range.from === range.to) return false
  editor.view.dispatch(state.tr.setSelection(TextSelection.create(state.doc, range.from, range.to)))
  return true
}

/** Where the phone's native comment field puts its thread: the selection, or the caret's whole block. */
export type TouchCommentScope = 'selection' | 'block'

const commentScope = (editor: Editor, scope: TouchCommentScope): TouchCommentScope =>
  scope === 'selection' && !editor.state.selection.empty ? 'selection' : 'block'

/**
 * What the native comment field quotes: the selected words or — no selection, or `block` — the caret's block (its
 * text; a block without text by its name). Null where no thread can start (code, nothing at the caret).
 */
export function touchCommentQuote(editor: Editor, scope: TouchCommentScope): string | null {
  const { state } = editor
  if (commentScope(editor, scope) === 'selection') {
    const { from, to, $from } = state.selection
    if ($from.parent.type.spec.code) return null
    const text = state.doc.textBetween(from, to, ' ').trim()
    return text ? text.slice(0, 200) : null
  }
  const unit = unitAtPos(state, state.selection.from)
  if (!unit || unit.node.type.spec.code) return null
  const range = unitTextRange(unit)
  if (!range) return blockQuote(unit.node, blockKindLabel(unit.node, state.doc.resolve(unit.pos)))
  return state.doc.textBetween(range.from, range.to, ' ').trim().slice(0, 200) || null
}

/**
 * The native comment field's Send: the thread starts where `touchCommentQuote` looked and takes its first comment in
 * the same step, so the page's own comment sheet never opens (focusing a field in it scrolled the page away).
 */
export function touchComment(editor: Editor, scope: TouchCommentScope, body: string): boolean {
  if (!body.trim()) return false
  const started =
    commentScope(editor, scope) === 'selection'
      ? editor.commands.commentStart()
      : touchBlockAction(editor, 'comment')
  if (!started) return false
  const sent = editor.commands.commentSend(body)
  editor.commands.commentOpen(null)
  return sent
}
