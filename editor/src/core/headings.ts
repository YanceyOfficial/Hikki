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
    // Headings don't nest in other text blocks; only containers (toggles, callouts, columns…) are looked into.
    return !node.isTextblock
  })
  return items
}

/**
 * The heading the reader is in (a scroll-spy): the last one whose top has passed `line` (pixels from the top of the
 * viewport), or the last heading once the page is scrolled to its end — a short final section never reaches the line.
 * -1 above the first heading.
 */
export function activeHeadingIndex(tops: number[], line: number, atBottom: boolean): number {
  if (tops.length === 0) return -1
  if (atBottom) return tops.length - 1
  let active = -1
  for (const [index, top] of tops.entries()) {
    if (top <= line) active = index
    else break
  }
  return active
}
