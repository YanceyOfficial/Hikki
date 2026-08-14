import { render, screen, waitFor } from '@testing-library/react'
import { getDefaultStore } from 'jotai'
import { MemoryRouter } from 'react-router'

vi.mock('#lib/errors', () => ({ reportError: vi.fn() }))

import { backend } from '#lib/backend/index'
import { reportError } from '#lib/errors'
import { dashboardStatsAtom, recentDocsAtom } from '#lib/store'
import type { DashboardStats } from '#lib/types'
import DashboardPage from '#pages/dashboard-page'

const stats: DashboardStats = {
  totalDocuments: 2,
  totalWords: 40,
  streakDays: 1,
  docsEditedThisWeek: 1,
  dailyWords: [{ date: '2026-01-01', wordDelta: 40 }],
  dailyActivity: [{ date: '2026-01-01', activityCount: 1 }]
}

afterEach(() => {
  getDefaultStore().set(dashboardStatsAtom, null)
  getDefaultStore().set(recentDocsAtom, [])
  vi.restoreAllMocks()
})

test('fetches stats and recent documents on mount and renders every section', async () => {
  vi.spyOn(backend, 'getDashboardStats').mockResolvedValue(stats)
  vi.spyOn(backend, 'getRecentDocuments').mockResolvedValue([])

  render(
    <MemoryRouter>
      <DashboardPage />
    </MemoryRouter>
  )

  expect(await screen.findByTestId('dashboard-greeting')).toBeInTheDocument()
  expect(screen.getByTestId('dashboard-stat-tiles')).toBeInTheDocument()
  expect(screen.getByTestId('dashboard-activity-chart')).toBeInTheDocument()
  expect(screen.getByTestId('dashboard-heatmap')).toBeInTheDocument()
  expect(screen.getByTestId('dashboard-recent-empty')).toBeInTheDocument()
  expect(screen.getByTestId('stat-tile-total-documents')).toHaveTextContent('2')
})

test('a failed load reports HK-7001 and still renders a zeroed page instead of crashing', async () => {
  vi.spyOn(backend, 'getDashboardStats').mockRejectedValue(new Error('boom'))
  vi.spyOn(backend, 'getRecentDocuments').mockResolvedValue([])

  render(
    <MemoryRouter>
      <DashboardPage />
    </MemoryRouter>
  )

  expect(await screen.findByTestId('dashboard-greeting')).toBeInTheDocument()
  expect(screen.getByTestId('dashboard-recent-empty')).toBeInTheDocument()
  // waitFor because reportError fires from an async .catch() inside a
  // useEffect, not synchronously with render.
  await waitFor(() => expect(reportError).toHaveBeenCalledWith('HK-7001'))
})
