import type { JSONContent } from '@tiptap/core'
import type { Schema } from '@tiptap/pm/model'

import { textOf } from './extract'

/**
 * What of content that doesn't fit the schema (a page from a newer Hikki, or damaged) can be shown, read-only:
 * every top-level block that fits stays as it is; one that doesn't (an unknown node type inside it, wrong
 * nesting) gives way to its child blocks where those fit, else to its text, a paragraph per line; unknown marks
 * are dropped from text. Only for display — the editor never saves it (the stored content stays intact).
 */
export function readableContent(content: JSONContent, schema: Schema): JSONContent {
  const blocks = (content.content ?? []).flatMap((block) => fitBlock(block, schema))
  const doc: JSONContent = {
    type: 'doc',
    content: blocks.length > 0 ? blocks : [{ type: 'paragraph' }]
  }
  return fits(doc, schema) ? doc : { type: 'doc', content: paragraphs(textOf(content)) }
}

function fitBlock(block: JSONContent, schema: Schema): JSONContent[] {
  const known = withKnownMarks(block, schema)
  if (known && fits({ type: 'doc', content: [known] }, schema)) return [known]
  const children = block.content ?? []
  // A container (columns, a toggle, a list): its blocks on their own, as far as they fit.
  if (
    children.length > 0 &&
    children.every((child) => child.type !== 'text' && isBlock(child, schema))
  )
    return children.flatMap((child) => fitBlock(child, schema))
  return paragraphs(textOf(block))
}

/** A known block type the schema places among blocks (unknown types count as blocks: their text is kept). */
function isBlock(node: JSONContent, schema: Schema): boolean {
  const type = node.type ? schema.nodes[node.type] : undefined
  return type ? type.isBlock : true
}

/** The node with unknown marks dropped, or null when it (or anything inside it) is of an unknown type. */
function withKnownMarks(node: JSONContent, schema: Schema): JSONContent | null {
  if (!node.type || !schema.nodes[node.type]) return null
  const out: JSONContent = { ...node }
  if (node.marks) out.marks = node.marks.filter((mark) => Boolean(schema.marks[mark.type]))
  if (node.content) {
    const content: JSONContent[] = []
    for (const child of node.content) {
      const fitted = withKnownMarks(child, schema)
      if (!fitted) return null
      content.push(fitted)
    }
    out.content = content
  }
  return out
}

function fits(doc: JSONContent, schema: Schema): boolean {
  try {
    schema.nodeFromJSON(doc).check()
    return true
  } catch {
    return false
  }
}

function paragraphs(text: string): JSONContent[] {
  return text
    .split('\n')
    .filter((line) => line.trim() !== '')
    .map((line) => ({ type: 'paragraph', content: [{ type: 'text', text: line }] }))
}
