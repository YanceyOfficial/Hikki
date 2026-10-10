import type { PagePayload } from '../src/protocol'

export const doc = (...paragraphs: string[]) => ({
  type: 'doc',
  content: paragraphs.map((text) => (text ? { type: 'paragraph', content: [{ type: 'text', text }] } : { type: 'paragraph' })),
})

export const page = (id: string, patch: Partial<PagePayload> = {}): PagePayload => ({
  id, title: '', icon: null, cover: null, content: doc('hi'), ...patch,
})

/** Suggestion and React effects resolve asynchronously. */
export const settle = () => new Promise((resolve) => setTimeout(resolve, 0))
