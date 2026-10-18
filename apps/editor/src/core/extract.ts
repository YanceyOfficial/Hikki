import type { JSONContent } from '@tiptap/core'

const CJK = /[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}]/gu
// Letters+digits as one run; deliberately not \b, which treats "abc123" oddly across scripts.
const WORD = /[\p{L}\p{N}]+(?:['’][\p{L}\p{N}]+)*/gu

/** Inline nodes: text and the atoms that sit in a line (a page mention, a ruby, an inline formula). */
const INLINE = new Set(['text', 'hardBreak', 'mention', 'ruby', 'inlineMath'])

/** A node's text: a line break as "\n", a page mention as "@label", an inline formula as its LaTeX. */
export function textOf(node: JSONContent): string {
  if (node.type === 'text') return node.text ?? ''
  if (node.type === 'hardBreak') return '\n'
  if (node.type === 'mention') return `@${node.attrs?.label ?? ''}`
  if (node.type === 'inlineMath') return node.attrs?.latex ?? ''
  return (node.content ?? []).map(textOf).join('')
}

/** Top-level blocks flattened to one line of text each (nested lists/quotes included). */
export function blockTexts(doc: JSONContent): string[] {
  const out: string[] = []
  const walk = (node: JSONContent) => {
    const children = node.content ?? []
    const isTextblock = children.length > 0 && children.every((c) => INLINE.has(c.type ?? ''))
    if (isTextblock || node.type === 'codeBlock') {
      out.push(textOf(node))
      return
    }
    children.forEach(walk)
  }
  walk(doc)
  return out
}

export function plainText(doc: JSONContent): string {
  return blockTexts(doc).join('\n')
}

/** CJK characters count one each; other scripts count by word. */
export function wordCount(text: string): number {
  const cjk = text.match(CJK)?.length ?? 0
  const rest = text.replace(CJK, ' ').match(WORD)?.length ?? 0
  return cjk + rest
}
