import type { JSONContent } from '@tiptap/core'

const MAX_TITLE_LENGTH = 120
const CJK = /[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}]/gu
// Letters+digits as one run; deliberately not \b, which treats "abc123" oddly across scripts.
const WORD = /[\p{L}\p{N}]+(?:['’][\p{L}\p{N}]+)*/gu

function textOf(node: JSONContent): string {
  if (node.type === 'text') return node.text ?? ''
  if (node.type === 'hardBreak') return '\n'
  return (node.content ?? []).map(textOf).join('')
}

/** Top-level blocks flattened to one line of text each (nested lists/quotes included). */
export function blockTexts(doc: JSONContent): string[] {
  const out: string[] = []
  const walk = (node: JSONContent) => {
    const children = node.content ?? []
    const isTextblock = children.length > 0 && children.every((c) => c.type === 'text' || c.type === 'hardBreak')
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

export function deriveTitle(doc: JSONContent): string {
  const first = blockTexts(doc).map((t) => t.trim()).find((t) => t.length > 0) ?? ''
  return first.length > MAX_TITLE_LENGTH ? first.slice(0, MAX_TITLE_LENGTH) : first
}

/** CJK characters count one each; other scripts count by word. */
export function wordCount(text: string): number {
  const cjk = text.match(CJK)?.length ?? 0
  const rest = text.replace(CJK, ' ').match(WORD)?.length ?? 0
  return cjk + rest
}
