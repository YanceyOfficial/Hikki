import { render, screen } from '@testing-library/react'
import { getDefaultStore } from 'jotai'

import { PageMentionRender } from '#components/page-mention'
import { docMetasAtom } from '#lib/store'
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

afterEach(() => {
  getDefaultStore().set(docMetasAtom, [])
})

test('renders the icon and title of a live document', () => {
  getDefaultStore().set(docMetasAtom, [
    meta({ id: 'a', title: 'Alpha', icon: '📘' })
  ])
  render(<PageMentionRender inlineContent={{ props: { docId: 'a' } }} />)
  const pill = screen.getByTestId('page-mention-a')
  expect(pill).toHaveTextContent('Alpha')
  expect(pill).toHaveTextContent('📘')
})

test('renders a fallback file icon when the document has none', () => {
  getDefaultStore().set(docMetasAtom, [meta({ id: 'a', icon: null })])
  render(<PageMentionRender inlineContent={{ props: { docId: 'a' } }} />)
  expect(screen.getByTestId('page-mention-a')).toBeInTheDocument()
})

test('renders a broken, non-clickable pill for a soft-deleted document', () => {
  getDefaultStore().set(docMetasAtom, [
    meta({ id: 'a', title: 'Alpha', deletedAt: '2026-01-02T00:00:00Z' })
  ])
  render(<PageMentionRender inlineContent={{ props: { docId: 'a' } }} />)
  const pill = screen.getByTestId('page-mention-broken-a')
  expect(pill).toHaveTextContent('Alpha')
  expect(screen.queryByTestId('page-mention-a')).not.toBeInTheDocument()
})

test('renders a broken pill with a "Missing page" label for an unknown docId', () => {
  getDefaultStore().set(docMetasAtom, [])
  render(<PageMentionRender inlineContent={{ props: { docId: 'ghost' } }} />)
  expect(screen.getByTestId('page-mention-broken-ghost')).toHaveTextContent(
    'Missing page'
  )
})

test('clicking a resolved mention navigates via the hash router', () => {
  getDefaultStore().set(docMetasAtom, [meta({ id: 'a', title: 'Alpha' })])
  render(<PageMentionRender inlineContent={{ props: { docId: 'a' } }} />)
  window.location.hash = ''
  screen.getByTestId('page-mention-a').click()
  expect(window.location.hash).toBe('#/doc/a')
})
