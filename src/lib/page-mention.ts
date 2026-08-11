import type { DocumentMeta } from '#lib/types'

export interface PageMentionDisplay {
  title: string
  icon: string | null
  isBroken: boolean
}

export function resolvePageMentionDisplay(
  docId: string,
  metas: DocumentMeta[]
): PageMentionDisplay {
  const meta = metas.find((m) => m.id === docId)
  const isBroken = !meta || meta.deletedAt !== null
  return {
    title: meta ? meta.title || 'Untitled' : 'Missing page',
    icon: meta?.icon ?? null,
    isBroken
  }
}

export function resolveHeadingMentionText(
  headingId: string,
  headingText: string,
  currentHeadingIds: string[]
): string | null {
  if (!headingId) return null
  if (!currentHeadingIds.includes(headingId)) return null
  return headingText
}

export function searchPageMentionCandidates(
  query: string,
  metas: DocumentMeta[]
): DocumentMeta[] {
  const alive = metas.filter((m) => m.deletedAt === null)
  const q = query.trim().toLowerCase()
  if (q.length === 0) return alive
  return alive.filter((m) => m.title.toLowerCase().includes(q))
}
