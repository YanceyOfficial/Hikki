import type { TocItem } from 'react-fluid-toc'

interface InlineContentNode {
  type?: unknown
  text?: unknown
  content?: unknown
}

interface BlockNode {
  id?: unknown
  type?: unknown
  props?: unknown
  content?: unknown
  children?: unknown
}

function extractText(content: unknown): string {
  if (!Array.isArray(content)) return ''
  return content
    .map((node) => {
      if (!node || typeof node !== 'object') return ''
      const { text, content: nested } = node as InlineContentNode
      if (typeof text === 'string') return text
      // Link inline content nests its own StyledText[] under `content`.
      if (Array.isArray(nested)) return extractText(nested)
      return ''
    })
    .join('')
}

/** Pure so it's independently unit-testable from the `FluidToc` rendering. */
export function extractTocItems(blocks: unknown[]): TocItem[] {
  const items: TocItem[] = []

  const walk = (list: unknown[]) => {
    for (const block of list) {
      if (!block || typeof block !== 'object') continue
      const { id, type, props, content, children } = block as BlockNode

      if (type === 'heading' && typeof id === 'string') {
        const level = (props as { level?: unknown } | undefined)?.level
        const text = extractText(content).trim()
        if (text.length > 0) {
          items.push({
            id,
            text,
            depth: typeof level === 'number' ? level : 1
          })
        }
      }

      if (Array.isArray(children) && children.length > 0) {
        walk(children)
      }
    }
  }

  walk(blocks)
  return items
}
