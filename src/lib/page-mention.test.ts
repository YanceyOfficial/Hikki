import {
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
