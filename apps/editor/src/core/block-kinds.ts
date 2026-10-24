import type { Editor } from '@tiptap/core'
import type { Node as PMNode, ResolvedPos } from '@tiptap/pm/model'

import type { BlockUnit } from '../extensions/block-units'
import { BLOCK_TYPES } from './blocks'
import { wordCount } from './extract'
import { t } from './i18n'

/** Catalog ids (`blocks.ts`) of node types that are one kind whatever their attributes. */
const NODE_KINDS: Record<string, string> = {
  paragraph: 'paragraph',
  blockquote: 'blockquote',
  codeBlock: 'codeBlock',
  details: 'toggle',
  callout: 'callout',
  taskItem: 'taskList',
  image: 'image',
  video: 'video',
  audio: 'audio',
  fileAttachment: 'file',
  drawing: 'drawing',
  horizontalRule: 'divider',
  table: 'table',
  blockMath: 'blockMath',
  tableOfContents: 'tableOfContents'
}

/** Embeds of services the "/" menu has no item of their own for (a pasted link becomes them). */
const OTHER_SERVICES: Record<string, () => string> = {
  youtube: () => t('blockMenu.kind.youtube'),
  vimeo: () => t('blockMenu.kind.vimeo'),
  codepen: () => t('blockMenu.kind.codepen')
}

/**
 * The catalog id of a block's kind (`heading2`, `orderedList`, `gist`…), read from the node alone; `$pos` (where the
 * node starts) tells a numbered list item from a bulleted one. Null for kinds the catalog doesn't name.
 */
export function blockKindId(node: PMNode, $pos?: ResolvedPos): string | null {
  const name = node.type.name
  if (name === 'heading') return `heading${node.attrs.level as number}`
  if (name === 'listItem')
    return $pos?.parent.type.name === 'orderedList' ? 'orderedList' : 'bulletList'
  if (name === 'columns') return `columns${Math.min(4, Math.max(2, node.childCount))}`
  if (name === 'embed') {
    const provider = node.attrs.provider as string
    if (provider === 'generic') return node.attrs.html === null ? 'embed' : 'html'
    return provider
  }
  return NODE_KINDS[name] ?? null
}

/** What the block is called (the block menu's section, a thread on the block): "Text", "Heading 2", "GitHub Gist". */
export function blockKindLabel(node: PMNode, $pos?: ResolvedPos): string {
  const id = blockKindId(node, $pos)
  const other = id ? OTHER_SERVICES[id] : undefined
  if (other) return other()
  const type = id ? BLOCK_TYPES.find((b) => b.id === id) : undefined
  return type ? type.label() : t('blockMenu.kind.block')
}

/** The block's words and characters, as the page's counts reckon them (CJK characters a word each); null without
 * text. */
export function blockCounts(node: PMNode): { words: number; characters: number } | null {
  const text = node.textBetween(0, node.content.size, ' ', ' ')
  if (!text.trim()) return null
  return { words: wordCount(text), characters: text.length }
}

/** The catalog id of the unit's kind (read from the document, no selection needed). */
export function unitTypeId(editor: Editor, unit: BlockUnit): string | null {
  const { node } = unit
  switch (node.type.name) {
    case 'paragraph':
      return 'paragraph'
    case 'heading':
      return `heading${node.attrs.level as number}`
    case 'listItem':
      return editor.state.doc.resolve(unit.pos).parent.type.name === 'orderedList'
        ? 'orderedList'
        : 'bulletList'
    case 'taskItem':
      return 'taskList'
    case 'blockquote':
      return 'blockquote'
    case 'codeBlock':
      return 'codeBlock'
    case 'details':
      return 'toggle'
    case 'callout':
      return 'callout'
    default:
      return null
  }
}
