import type { PagePayload } from '../src/protocol'

export const doc = (...paragraphs: string[]) => ({
  type: 'doc',
  content: paragraphs.map((text) =>
    text ? { type: 'paragraph', content: [{ type: 'text', text }] } : { type: 'paragraph' }
  )
})

export const page = (id: string, patch: Partial<PagePayload> = {}): PagePayload => ({
  id,
  title: '',
  icon: null,
  cover: null,
  content: doc('hi'),
  ...patch
})

/** Suggestion and React effects resolve asynchronously. */
export const settle = () => new Promise((resolve) => setTimeout(resolve, 0))

/** Tiptap JSON without UniqueID's block ids (random) or null (default) attributes, for structural comparisons. */
export const stripIds = (node: any): any => {
  if (Array.isArray(node)) return node.map(stripIds)
  if (!node || typeof node !== 'object') return node
  const { attrs, content, ...rest } = node
  const out: any = { ...rest }
  if (attrs) {
    const { id: _id, ...other } = attrs
    // Null attributes are defaults (block colours etc.); compare what's actually set.
    const set = Object.fromEntries(Object.entries(other).filter(([, v]) => v !== null))
    if (Object.keys(set).length) out.attrs = set
  }
  if (content) out.content = stripIds(content)
  return out
}
