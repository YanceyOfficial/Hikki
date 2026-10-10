import type { JSONContent } from '@tiptap/core'

const textOf = (node: JSONContent): string =>
  node.type === 'text' ? (node.text ?? '') : (node.content ?? []).map(textOf).join('')

/**
 * Brings stored body content up to the current schema before it is loaded. The title is a page
 * property now, so older documents that carried it inside the body lose that leading node:
 * - a `title` node (previous build),
 * - a leading level-1 heading whose text equals the page title (first build, title derived from it).
 * Returns the cleaned body and the title recovered from it (used only when the stored title is empty).
 */
export function normalizeBody(content: JSONContent | null, storedTitle: string): { body: JSONContent; title: string } {
  const blocks = content?.type === 'doc' ? [...(content.content ?? [])] : []
  let title = storedTitle
  const first = blocks[0]
  if (first?.type === 'title') {
    blocks.shift()
    title = storedTitle || textOf(first).trim()
  } else if (first?.type === 'heading' && first.attrs?.level === 1 && textOf(first).trim() === storedTitle.trim() && storedTitle.trim()) {
    blocks.shift()
  }
  if (blocks.length === 0) blocks.push({ type: 'paragraph' })
  return { body: { type: 'doc', content: blocks }, title }
}
