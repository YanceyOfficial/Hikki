import { buildTree } from '#lib/tree'
import type { DocumentMeta } from '#lib/types'

const meta = (over: Partial<DocumentMeta>): DocumentMeta => ({
  id: 'x',
  parentId: null,
  title: '',
  icon: null,
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  deletedAt: null,
  ...over
})

test('nests children under parents', () => {
  const tree = buildTree([
    meta({ id: 'a', title: 'A' }),
    meta({ id: 'b', parentId: 'a', title: 'B' }),
    meta({ id: 'c', parentId: 'b', title: 'C' })
  ])
  expect(tree).toHaveLength(1)
  expect(tree[0].children[0].meta.id).toBe('b')
  expect(tree[0].children[0].children[0].meta.id).toBe('c')
})

test('excludes deleted documents and their subtrees', () => {
  const tree = buildTree([
    meta({ id: 'a', title: 'A', deletedAt: '2026-01-02T00:00:00Z' }),
    meta({ id: 'b', parentId: 'a', title: 'B' })
  ])
  expect(tree).toHaveLength(0)
})

test('orphans (missing parent) surface at root', () => {
  const tree = buildTree([meta({ id: 'b', parentId: 'ghost', title: 'B' })])
  expect(tree).toHaveLength(1)
  expect(tree[0].meta.id).toBe('b')
})

test('siblings sort by createdAt', () => {
  const tree = buildTree([
    meta({ id: 'later', createdAt: '2026-01-02T00:00:00Z' }),
    meta({ id: 'earlier', createdAt: '2026-01-01T00:00:00Z' })
  ])
  expect(tree.map((n) => n.meta.id)).toEqual(['earlier', 'later'])
})
