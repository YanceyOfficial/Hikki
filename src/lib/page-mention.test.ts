import {
  resolveDocPath,
  resolveHeadingMentionText,
  resolvePageMentionDisplay,
  searchPageMentionCandidates
} from '#lib/page-mention'
import type { DocumentMeta } from '#lib/types'

const meta = (over: Partial<DocumentMeta> = {}): DocumentMeta => ({
  id: 'a',
  parentId: null,
  title: 'Alpha',
  icon: null,
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  deletedAt: null,
  ...over
})

test('resolves an alive document with its current title and icon', () => {
  const metas = [meta({ id: 'a', title: 'Alpha', icon: '📘' })]
  expect(resolvePageMentionDisplay('a', metas)).toEqual({
    title: 'Alpha',
    icon: '📘',
    isBroken: false
  })
})

test('falls back to "Untitled" for an alive document with an empty title', () => {
  const metas = [meta({ id: 'a', title: '' })]
  expect(resolvePageMentionDisplay('a', metas)).toEqual({
    title: 'Untitled',
    icon: null,
    isBroken: false
  })
})

test('renders a soft-deleted document as broken, keeping its last known title', () => {
  const metas = [
    meta({ id: 'a', title: 'Alpha', deletedAt: '2026-01-02T00:00:00Z' })
  ]
  expect(resolvePageMentionDisplay('a', metas)).toEqual({
    title: 'Alpha',
    icon: null,
    isBroken: true
  })
})

test('renders a docId with no matching meta at all as broken with a "Missing page" label', () => {
  expect(resolvePageMentionDisplay('does-not-exist', [])).toEqual({
    title: 'Missing page',
    icon: null,
    isBroken: true
  })
})

test('resolves the heading snapshot text when the heading id is still present', () => {
  expect(resolveHeadingMentionText('h1', 'Section Three', ['h1', 'h2'])).toBe(
    'Section Three'
  )
})

test('resolves to null when the heading id is no longer present', () => {
  expect(
    resolveHeadingMentionText('h1', 'Section Three', ['h2', 'h3'])
  ).toBeNull()
})

test('resolves to null for an empty headingId (a plain whole-document mention)', () => {
  expect(resolveHeadingMentionText('', 'Section Three', ['h1'])).toBeNull()
})

test('returns the plain title for a top-level document with no parent', () => {
  const metas = [meta({ id: 'a', title: 'Alpha', parentId: null })]
  expect(resolveDocPath(metas[0], metas)).toBe('Alpha')
})

test('returns "Parent / Title" for a nested document whose parent is present', () => {
  const metas = [
    meta({ id: 'p', title: 'N5 Grammar', parentId: null }),
    meta({ id: 'a', title: '笔记', parentId: 'p' })
  ]
  expect(resolveDocPath(metas[1], metas)).toBe('N5 Grammar / 笔记')
})

test('falls back to the plain title when the parent id does not resolve to any meta', () => {
  const metas = [meta({ id: 'a', title: 'Alpha', parentId: 'missing-parent' })]
  expect(resolveDocPath(metas[0], metas)).toBe('Alpha')
})

test('falls back to "Untitled" for an empty title with no parent', () => {
  const metas = [meta({ id: 'a', title: '', parentId: null })]
  expect(resolveDocPath(metas[0], metas)).toBe('Untitled')
})

test('uses "Untitled" for either side of the path when a title is empty', () => {
  const metas = [
    meta({ id: 'p', title: '', parentId: null }),
    meta({ id: 'a', title: '笔记', parentId: 'p' })
  ]
  expect(resolveDocPath(metas[1], metas)).toBe('Untitled / 笔记')
})

test('an empty query returns every alive document', () => {
  const metas = [
    meta({ id: 'a', title: 'Alpha' }),
    meta({ id: 'b', title: 'Beta' })
  ]
  expect(searchPageMentionCandidates('', metas).map((m) => m.id)).toEqual([
    'a',
    'b'
  ])
})

test('filters by a case-insensitive substring match on title', () => {
  const metas = [
    meta({ id: 'a', title: 'Alpha' }),
    meta({ id: 'b', title: 'Beta' })
  ]
  expect(searchPageMentionCandidates('AL', metas).map((m) => m.id)).toEqual([
    'a'
  ])
})

test('excludes soft-deleted documents from search results', () => {
  const metas = [
    meta({ id: 'a', title: 'Alpha' }),
    meta({ id: 'b', title: 'Alpha 2', deletedAt: '2026-01-02T00:00:00Z' })
  ]
  expect(searchPageMentionCandidates('Alpha', metas).map((m) => m.id)).toEqual([
    'a'
  ])
})
