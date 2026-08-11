import { getDefaultStore } from 'jotai'

import { backend } from '#lib/backend/index'
import { headingCacheAtom, loadHeadings } from '#lib/heading-mention-cache'
import type { Doc } from '#lib/types'

const doc = (over: Partial<Doc> = {}): Doc => ({
  id: 'a',
  parentId: null,
  title: 'Alpha',
  icon: null,
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  deletedAt: null,
  schemaVersion: 1,
  cover: null,
  blocks: [],
  threads: {},
  ...over
})

beforeEach(() => {
  getDefaultStore().set(headingCacheAtom, {})
})

test('fetches and extracts headings from the document, caching the result', async () => {
  const heading = {
    id: 'h1',
    type: 'heading',
    props: { level: 1 },
    content: [{ type: 'text', text: 'Intro', styles: {} }],
    children: []
  }
  const spy = vi
    .spyOn(backend, 'loadDocument')
    .mockResolvedValue(doc({ blocks: [heading] }))

  const headings = await loadHeadings('a', '2026-01-01T00:00:00Z')
  expect(headings).toEqual([{ id: 'h1', text: 'Intro', depth: 1 }])
  expect(spy).toHaveBeenCalledTimes(1)

  // Second call with the *same* updatedAt reuses the cache - no second fetch.
  await loadHeadings('a', '2026-01-01T00:00:00Z')
  expect(spy).toHaveBeenCalledTimes(1)

  spy.mockRestore()
})

test('refetches when the document has since been saved (a new updatedAt)', async () => {
  const spy = vi
    .spyOn(backend, 'loadDocument')
    .mockResolvedValueOnce(
      doc({ blocks: [], updatedAt: '2026-01-01T00:00:00Z' })
    )
    .mockResolvedValueOnce(
      doc({ blocks: [], updatedAt: '2026-01-02T00:00:00Z' })
    )

  await loadHeadings('a', '2026-01-01T00:00:00Z')
  await loadHeadings('a', '2026-01-02T00:00:00Z')
  expect(spy).toHaveBeenCalledTimes(2)

  spy.mockRestore()
})

test('returns an empty list and does not throw when the fetch fails', async () => {
  const spy = vi
    .spyOn(backend, 'loadDocument')
    .mockRejectedValue(new Error('not found'))

  const headings = await loadHeadings('missing', '2026-01-01T00:00:00Z')
  expect(headings).toEqual([])

  spy.mockRestore()
})
