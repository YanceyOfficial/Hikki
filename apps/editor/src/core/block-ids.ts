import type { JSONContent } from '@tiptap/core'

/**
 * Blocks that carry a stable `id` attribute: the anchor for version diffs, block links and, later,
 * comments and collaboration. Inline nodes and list wrappers don't need one.
 */
export const BLOCK_ID_TYPES = [
  'paragraph',
  'heading',
  'blockquote',
  'codeBlock',
  'horizontalRule',
  'listItem',
  'taskItem',
  'bulletList',
  'orderedList',
  'taskList',
  'details',
  'callout',
  'blockMath',
  'table',
  'columns',
  'image',
  'video',
  'audio',
  'fileAttachment',
  'embed',
  'drawing'
]

const ID_TYPES = new Set(BLOCK_ID_TYPES)

const newID = () =>
  globalThis.crypto?.randomUUID?.() ??
  `b-${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`

/**
 * The content with an id on every block that should carry one and has none, in one walk. Tiptap's UniqueID stamps
 * them too, but its pass over a document that lacks them is quadratic (2000 blocks: seconds), so imports and pages
 * from before block ids get theirs here, before the editor sees them. Ids already there are kept.
 */
export function withBlockIds(content: JSONContent): JSONContent {
  return stamp(content)
}

function stamp(node: JSONContent): JSONContent {
  const children = node.content?.map(stamp)
  const needsId = node.type !== undefined && ID_TYPES.has(node.type) && !node.attrs?.id
  if (!needsId && children === undefined) return node
  const out: JSONContent = { ...node }
  if (children) out.content = children
  if (needsId) out.attrs = { ...node.attrs, id: newID() }
  return out
}
