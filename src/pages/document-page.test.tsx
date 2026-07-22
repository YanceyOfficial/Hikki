import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter, Route, Routes } from 'react-router'

import { backend } from '#lib/backend/index'
import DocumentPage from '#pages/document-page'

// BlockNote cannot render under jsdom (ProseMirror needs real layout APIs),
// so the real editor is only exercised by Task 9's Playwright e2e tests.
vi.mock('#components/editor', () => ({
  Editor: ({
    docId,
    initialBlocks,
    onBlocksChange,
    commentsPortalTarget
  }: {
    docId: string
    initialBlocks: unknown[]
    onBlocksChange: (blocks: unknown[]) => void
    commentsPortalTarget: HTMLElement | null
  }) => (
    <button
      data-testid="mock-editor"
      data-doc-id={docId}
      data-block-count={initialBlocks.length}
      data-has-rail-target={commentsPortalTarget !== null}
      onClick={() => onBlocksChange([{ type: 'paragraph', content: 'edited' }])}
    >
      mock editor
    </button>
  )
}))

const renderPage = (id: string) =>
  render(
    <MemoryRouter initialEntries={[`/doc/${id}`]}>
      <Routes>
        <Route path="/doc/:id" element={<DocumentPage />} />
      </Routes>
    </MemoryRouter>
  )

test('loads and shows the document title', async () => {
  const doc = await backend.createDocument(null, 'My note')
  renderPage(doc.id)
  expect(await screen.findByTestId('doc-title')).toHaveValue('My note')
})

test('typing autosaves after debounce', async () => {
  const doc = await backend.createDocument(null, '')
  renderPage(doc.id)
  const input = await screen.findByTestId('doc-title')
  await userEvent.type(input, 'Renamed')
  await waitFor(
    async () =>
      expect((await backend.loadDocument(doc.id)).title).toBe('Renamed'),
    {
      timeout: 3000
    }
  )
})

test('flushes pending save on unmount', async () => {
  const doc = await backend.createDocument(null, 'Before')
  const { unmount } = renderPage(doc.id)
  const input = await screen.findByTestId('doc-title')
  await userEvent.clear(input)
  await userEvent.type(input, 'After')
  unmount()
  expect((await backend.loadDocument(doc.id)).title).toBe('After')
})

test('unknown id shows not-found state', async () => {
  renderPage('missing-id')
  expect(await screen.findByTestId('doc-not-found')).toBeInTheDocument()
})

test('renders the editor with the loaded blocks', async () => {
  const doc = await backend.createDocument(null, 'Has editor')
  await backend.saveDocument({ ...doc, blocks: [{ type: 'paragraph' }] })
  renderPage(doc.id)
  const editor = await screen.findByTestId('mock-editor')
  expect(editor).toHaveAttribute('data-doc-id', doc.id)
  expect(editor).toHaveAttribute('data-block-count', '1')
})

test('provides the editor with a real rail DOM node to portal comments into', async () => {
  const doc = await backend.createDocument(null, 'Has rail')
  renderPage(doc.id)
  expect(await screen.findByTestId('page-rail')).toBeInTheDocument()
  await waitFor(() =>
    expect(screen.getByTestId('mock-editor')).toHaveAttribute(
      'data-has-rail-target',
      'true'
    )
  )
})

test('block changes are autosaved', async () => {
  const doc = await backend.createDocument(null, 'Blocks')
  renderPage(doc.id)
  await userEvent.click(await screen.findByTestId('mock-editor'))
  await waitFor(
    async () =>
      expect((await backend.loadDocument(doc.id)).blocks).toEqual([
        { type: 'paragraph', content: 'edited' }
      ]),
    { timeout: 3000 }
  )
})
