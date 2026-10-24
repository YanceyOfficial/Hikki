import type { JSONContent } from '@tiptap/core'
import type { Mark, Schema } from '@tiptap/pm/model'

/**
 * Content shaping shared by import (convert.ts) and AI answers (answer-markdown.ts): plain JSON in, plain JSON out,
 * the schema passed in — nothing here builds or imports an editor.
 */

export const emptyDoc = (): JSONContent => ({ type: 'doc', content: [{ type: 'paragraph' }] })

/**
 * Marks a text may not carry together resolved the way the editor would (ProseMirror's `addToSet`: a mark that
 * excludes another replaces it — inline code inside bold stays code), so one such run doesn't send the whole file to
 * the text fallback. Unknown marks are left for the schema check to refuse.
 */
export function fitMarks(node: JSONContent, schema: Schema): JSONContent {
  let marks = node.marks
  if (marks && marks.length > 1 && marks.every((mark) => schema.marks[mark.type])) {
    let set: readonly Mark[] = []
    for (const mark of marks) set = schema.mark(mark.type, mark.attrs).addToSet(set)
    marks = set.map((mark) => mark.toJSON() as NonNullable<JSONContent['marks']>[number])
  }
  return {
    ...node,
    ...(marks ? { marks } : {}),
    ...(node.content ? { content: node.content.map((child) => fitMarks(child, schema)) } : {})
  }
}

/** Plain text: a paragraph per run of lines, blank lines between them; lines inside one keep their breaks. */
export function textDocument(text: string): JSONContent {
  const paragraphs = text
    .replaceAll(/\r\n?/gu, '\n')
    .split(/\n{2,}/u)
    .map((chunk) => chunk.replaceAll(/^\n+|\n+$/gu, ''))
    .filter((chunk) => chunk.trim() !== '')
  if (paragraphs.length === 0) return emptyDoc()
  return {
    type: 'doc',
    content: paragraphs.map((chunk) => ({
      type: 'paragraph',
      content: chunk
        .split('\n')
        .flatMap((line, index): JSONContent[] => [
          ...(index > 0 ? [{ type: 'hardBreak' }] : []),
          ...(line ? [{ type: 'text', text: line }] : [])
        ])
    }))
  }
}
