import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter, Route, Routes } from 'react-router'

import { backend } from '#lib/backend/index'
import DocumentPage from '#pages/document-page'

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

test('unknown id shows not-found state', async () => {
  renderPage('missing-id')
  expect(await screen.findByTestId('doc-not-found')).toBeInTheDocument()
})
