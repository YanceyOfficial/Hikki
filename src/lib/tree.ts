import type { DocumentMeta } from '#lib/types'

export interface TreeNode {
  meta: DocumentMeta
  children: TreeNode[]
}

export function buildTree(metas: DocumentMeta[]): TreeNode[] {
  const allIds = new Set(metas.map((m) => m.id))
  const alive = metas.filter((m) => m.deletedAt === null)
  const aliveIds = new Set(alive.map((m) => m.id))
  const byParent = new Map<string | null, DocumentMeta[]>()
  for (const m of alive) {
    if (
      m.parentId !== null &&
      allIds.has(m.parentId) &&
      !aliveIds.has(m.parentId)
    ) {
      // Parent was deleted, skip this document
      continue
    }
    const key =
      m.parentId !== null && aliveIds.has(m.parentId) ? m.parentId : null
    const list = byParent.get(key) ?? []
    list.push(m)
    byParent.set(key, list)
  }
  const build = (parentId: string | null): TreeNode[] =>
    (byParent.get(parentId) ?? [])
      .sort((a, b) => a.createdAt.localeCompare(b.createdAt))
      .map((meta) => ({ meta, children: build(meta.id) }))
  return build(null)
}
