import type { Node as PMNode } from '@tiptap/pm/model'
import type { Transaction } from '@tiptap/pm/state'

export type Range = { from: number; to: number }

/**
 * Where `transactions` changed the document, in the final document's positions (a position of margin each side), so
 * an `appendTransaction` that fixes something up looks there instead of walking the whole page on every keystroke.
 * Null when a step's reach can't be told (an unknown kind of step): look everywhere.
 */
export function changedRanges(transactions: readonly Transaction[], doc: PMNode): Range[] | null {
  let ranges: [number, number][] = []
  for (const tr of transactions) {
    if (!tr.docChanged) continue
    for (const [i, step] of tr.steps.entries()) {
      const map = tr.mapping.maps[i]
      ranges = ranges.map(([a, b]) => [map.map(a, -1), map.map(b, 1)])
      let reached = false
      map.forEach((_oldStart, _oldEnd, newStart, newEnd) => {
        ranges.push([newStart, newEnd])
        reached = true
      })
      // Mark and attribute steps move nothing: their own positions say where they acted.
      const { from, to, pos } = step as { from?: number; to?: number; pos?: number }
      if (typeof from === 'number' && typeof to === 'number') {
        ranges.push([from, to])
        reached = true
      } else if (typeof pos === 'number') {
        ranges.push([pos, pos + 1])
        reached = true
      }
      if (!reached) return null
    }
  }
  const size = doc.content.size
  return ranges.map(([a, b]) => ({
    from: Math.max(0, Math.min(a, b) - 1),
    to: Math.min(size, Math.max(a, b) + 1)
  }))
}

/**
 * `doc.nodesBetween` over each changed range (ancestors included, each node once), or `doc.descendants` when the
 * ranges are unknown. `visit` returns false to skip a node's children, as with ProseMirror's own walkers.
 */
export function visitChanged(
  doc: PMNode,
  ranges: Range[] | null,
  visit: (node: PMNode, pos: number) => boolean
): void {
  if (ranges === null) {
    doc.descendants(visit)
    return
  }
  // A node two ranges share is visited once; whether to look inside it stays as its first visit said.
  const descend = new Map<number, boolean>()
  for (const { from, to } of ranges) {
    doc.nodesBetween(from, to, (node, pos) => {
      const known = descend.get(pos)
      if (known !== undefined) return known
      const inside = visit(node, pos)
      descend.set(pos, inside)
      return inside
    })
  }
}
