import type { JSONContent } from '@tiptap/core'

const textOf = (node: JSONContent): string =>
  node.type === 'text' ? (node.text ?? '') : (node.content ?? []).map(textOf).join('')

/**
 * Brings stored content up to the current schema (`title block+`) before it is loaded.
 * Older documents started with a level-1 heading as their title; that heading becomes the title node.
 */
export function normalizeDocument(content: JSONContent | null): JSONContent {
  const blocks = content?.type === 'doc' ? [...(content.content ?? [])] : []
  let title: JSONContent = { type: 'title' }

  const first = blocks[0]
  if (first?.type === 'title') {
    title = blocks.shift()!
  } else if (first?.type === 'heading' && first.attrs?.level === 1) {
    blocks.shift()
    const text = textOf(first).replace(/\n/g, ' ')
    title = text ? { type: 'title', content: [{ type: 'text', text }] } : { type: 'title' }
  }

  if (blocks.length === 0) blocks.push({ type: 'paragraph' })
  return { type: 'doc', content: [title, ...blocks] }
}
