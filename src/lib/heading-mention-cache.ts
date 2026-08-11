import { atom, getDefaultStore } from 'jotai'
import type { TocItem } from 'react-fluid-toc'

import { backend } from '#lib/backend/index'
import { extractTocItems } from '#lib/toc'

type HeadingCacheEntry =
  | { status: 'loading'; updatedAt: string }
  | { status: 'loaded'; updatedAt: string; headings: TocItem[] }
  | { status: 'error'; updatedAt: string }

export const headingCacheAtom = atom<Record<string, HeadingCacheEntry>>({})

/**
 * `updatedAt` is the target document's own `DocumentMeta.updatedAt` -
 * already available to every caller via `docMetasAtom`, so passing it costs
 * nothing extra. A cached entry is only reused when it was fetched *at* the
 * document's current `updatedAt` - any save to that document (a heading
 * added, edited, or removed) changes `updatedAt`, which invalidates the
 * cache and forces a fresh fetch. Without this, a heading-targeted mention
 * would keep showing a deleted heading as "still there" forever within the
 * same app session, since nothing else would ever tell this cache to
 * refetch.
 */
export async function loadHeadings(
  docId: string,
  updatedAt: string
): Promise<TocItem[]> {
  const store = getDefaultStore()
  const existing = store.get(headingCacheAtom)[docId]
  if (existing?.status === 'loaded' && existing.updatedAt === updatedAt) {
    return existing.headings
  }

  store.set(headingCacheAtom, (prev) => ({
    ...prev,
    [docId]: { status: 'loading', updatedAt }
  }))
  try {
    const doc = await backend.loadDocument(docId)
    const headings = extractTocItems(doc.blocks)
    store.set(headingCacheAtom, (prev) => ({
      ...prev,
      [docId]: { status: 'loaded', updatedAt, headings }
    }))
    return headings
  } catch {
    store.set(headingCacheAtom, (prev) => ({
      ...prev,
      [docId]: { status: 'error', updatedAt }
    }))
    return []
  }
}
