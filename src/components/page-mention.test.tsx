import { render, screen } from '@testing-library/react'
import { getDefaultStore } from 'jotai'

import { PageMentionRender } from '#components/page-mention'
import { headingCacheAtom } from '#lib/heading-mention-cache'
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
  getDefaultStore().set(headingCacheAtom, {})
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

test('renders just the document title, with an href carrying the heading, when the heading still exists', () => {
  getDefaultStore().set(docMetasAtom, [meta({ id: 'a', title: 'Alpha' })])
  getDefaultStore().set(headingCacheAtom, {
    a: {
      status: 'loaded',
      updatedAt: '2026-01-01T00:00:00Z',
      headings: [{ id: 'h1', text: 'Section Three', depth: 1 }]
    }
  })
  render(
    <PageMentionRender
      inlineContent={{
        props: { docId: 'a', headingId: 'h1', headingText: 'Section Three' }
      }}
    />
  )
  const pill = screen.getByTestId('page-mention-a')
  // The heading snapshot now only ever surfaces via the hover tooltip (not
  // rendered into the DOM until actually triggered - Base UI portals it
  // lazily, confirmed live), so the pill's own text stays just the title;
  // the href is what actually carries the heading target.
  expect(pill).toHaveTextContent('Alpha')
  expect(pill).not.toHaveTextContent('Section Three')
  expect(pill).toHaveAttribute('href', '#/doc/a?heading=h1')
})

test('links to the plain whole-document hash for a plain whole-document mention', () => {
  getDefaultStore().set(docMetasAtom, [meta({ id: 'a', title: 'Alpha' })])
  render(<PageMentionRender inlineContent={{ props: { docId: 'a' } }} />)
  expect(screen.getByTestId('page-mention-a')).toHaveAttribute(
    'href',
    '#/doc/a'
  )
})

test('links to the plain whole-document hash once the heading has degraded away', () => {
  getDefaultStore().set(docMetasAtom, [meta({ id: 'a', title: 'Alpha' })])
  getDefaultStore().set(headingCacheAtom, {
    a: {
      status: 'loaded',
      updatedAt: '2026-01-01T00:00:00Z',
      headings: [{ id: 'h2', text: 'A different section', depth: 1 }]
    }
  })
  render(
    <PageMentionRender
      inlineContent={{
        props: { docId: 'a', headingId: 'h1', headingText: 'Section Three' }
      }}
    />
  )
  expect(screen.getByTestId('page-mention-a')).toHaveAttribute(
    'href',
    '#/doc/a'
  )
})

test('degrades to a plain whole-document mention when the heading no longer exists', () => {
  getDefaultStore().set(docMetasAtom, [meta({ id: 'a', title: 'Alpha' })])
  getDefaultStore().set(headingCacheAtom, {
    a: {
      status: 'loaded',
      updatedAt: '2026-01-01T00:00:00Z',
      headings: [{ id: 'h2', text: 'A different section', depth: 1 }]
    }
  })
  render(
    <PageMentionRender
      inlineContent={{
        props: { docId: 'a', headingId: 'h1', headingText: 'Section Three' }
      }}
    />
  )
  const pill = screen.getByTestId('page-mention-a')
  expect(pill).toHaveTextContent('Alpha')
  expect(pill).not.toHaveTextContent('Section Three')
})

test('renders the plain whole-document mention while the heading cache has not loaded yet', () => {
  getDefaultStore().set(docMetasAtom, [meta({ id: 'a', title: 'Alpha' })])
  render(
    <PageMentionRender
      inlineContent={{
        props: { docId: 'a', headingId: 'h1', headingText: 'Section Three' }
      }}
    />
  )
  const pill = screen.getByTestId('page-mention-a')
  expect(pill).toHaveTextContent('Alpha')
  expect(pill).not.toHaveTextContent('Section Three')
})

test('a resolved mention is a real link to the hash router route', () => {
  getDefaultStore().set(docMetasAtom, [meta({ id: 'a', title: 'Alpha' })])
  render(<PageMentionRender inlineContent={{ props: { docId: 'a' } }} />)
  // A real `<a href>` now drives navigation (letting the browser handle it
  // natively, including middle-click/cmd-click "open in new tab") rather
  // than a manual `window.location.hash = ...` in an onClick handler -
  // jsdom doesn't implement real anchor-click navigation, so this checks
  // the href attribute directly instead of simulating a click.
  expect(screen.getByTestId('page-mention-a').tagName).toBe('A')
  expect(screen.getByTestId('page-mention-a')).toHaveAttribute(
    'href',
    '#/doc/a'
  )
})
