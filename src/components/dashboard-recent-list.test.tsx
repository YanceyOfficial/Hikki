import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter, Route, Routes } from 'react-router'

import { DashboardRecentList } from '#components/dashboard-recent-list'
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

test('shows an empty-state prompt when there are no documents', () => {
  render(
    <MemoryRouter>
      <DashboardRecentList docs={[]} />
    </MemoryRouter>
  )
  expect(screen.getByTestId('dashboard-recent-empty')).toBeInTheDocument()
})

test('falls back to "Untitled" for an empty title, and navigates on click', async () => {
  render(
    <MemoryRouter initialEntries={['/']}>
      <Routes>
        <Route
          path="/"
          element={<DashboardRecentList docs={[meta({ title: '' })]} />}
        />
        <Route path="/doc/:id" element={<div data-testid="doc-page" />} />
      </Routes>
    </MemoryRouter>
  )
  const row = screen.getByTestId('dashboard-recent-a')
  expect(row).toHaveTextContent('Untitled')
  await userEvent.click(row)
  expect(await screen.findByTestId('doc-page')).toBeInTheDocument()
})
