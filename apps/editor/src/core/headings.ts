import type { Editor } from '@tiptap/core'

import { textOf } from './extract'

export type HeadingItem = { id: string | null; pos: number; level: number; text: string }

/** A heading as the outline shows it: no position (positions move with every keystroke above it; look them up
 * again with `collectHeadings` when one is needed). */
export type OutlineItem = { id: string | null; level: number; text: string }

export const outlineItems = (editor: Editor): OutlineItem[] =>
  collectHeadings(editor).map(({ id, level, text }) => ({ id, level, text }))

/** Whether two outlines read the same (typing in a paragraph leaves the outline as it was). */
export function sameOutline(a: readonly OutlineItem[], b: readonly OutlineItem[]): boolean {
  return (
    a.length === b.length &&
    a.every((h, i) => h.id === b[i].id && h.level === b[i].level && h.text === b[i].text)
  )
}

/** Headings in document order, for the outline (table of contents). */
export function collectHeadings(editor: Editor): HeadingItem[] {
  const items: HeadingItem[] = []
  editor.state.doc.descendants((node, pos) => {
    if (node.type.name === 'heading') {
      // A formula, a mention or ruby counts as the heading's words (a heading of only a formula has no text nodes).
      const text = textOf(node.toJSON()).trim()
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
