import type { JSONContent } from '@tiptap/core'

import { textOf } from './extract'

/**
 * Brings stored body content up to the current schema before it is loaded. The title is a page
 * property now, so older documents that carried it inside the body lose that leading node:
 * - a `title` node (previous build),
 * - a leading level-1 heading whose text equals the page title (first build, title derived from it) — only one
 *   without a block id: block ids came after the first build, so an H1 with one is the user's own.
 * Returns the cleaned body and the title recovered from it (used only when the stored title is empty).
 */
export function normalizeBody(
  content: JSONContent | null,
  storedTitle: string
): { body: JSONContent; title: string } {
  const blocks = content?.type === 'doc' ? [...(content.content ?? [])] : []
  let title = storedTitle
  const first = blocks[0]
  if (first?.type === 'title') {
    blocks.shift()
    title = storedTitle || textOf(first).trim()
  } else if (
    first?.type === 'heading' &&
    first.attrs?.level === 1 &&
    !first.attrs?.id &&
    textOf(first).trim() === storedTitle.trim() &&
    storedTitle.trim()
  ) {
    blocks.shift()
  }
  if (blocks.length === 0) blocks.push({ type: 'paragraph' })
  return { body: { type: 'doc', content: blocks }, title }
}
