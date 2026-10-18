import type { Editor } from '@tiptap/core'
import { TextSelection } from '@tiptap/pm/state'

import { PALETTE, type PaletteColor } from '../extensions/colors'
import { BLOCK_GROUPS, BLOCK_TYPES, type BlockGroup, type BlockType } from './blocks'
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
      (b) => b.group === group && (group !== 'embeds' || b.id === 'embed')
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
      // A space first when the "@" would stick to a word (the suggestion starts only after a space).
      return chain
        .insertContent(
          /\S$/u.test(editor.state.selection.$from.nodeBefore?.text ?? '') ? ' @' : '@'
        )
        .run()
    case 'todo':
      return chain.toggleTaskList().run()
    case 'comment':
      return editor.commands.commentStart()
  }
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
