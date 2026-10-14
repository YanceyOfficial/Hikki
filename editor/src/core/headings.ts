import type { Editor } from '@tiptap/core'

export type HeadingItem = { id: string | null; pos: number; level: number; text: string }

/** Headings in document order, for the outline (table of contents). */
export function collectHeadings(editor: Editor): HeadingItem[] {
  const items: HeadingItem[] = []
  editor.state.doc.descendants((node, pos) => {
    if (node.type.name === 'heading') {
      const text = node.textContent.trim()
      if (text)
        items.push({
          id: (node.attrs.id as string | undefined) ?? null,
          pos,
          level: node.attrs.level as number,
          text
        })
      return false
    }
    return true
  })
  return items
}
