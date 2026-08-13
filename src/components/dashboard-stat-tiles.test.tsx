import { render, screen } from '@testing-library/react'

import { DashboardStatTiles } from '#components/dashboard-stat-tiles'
import type { DashboardStats } from '#lib/types'

const stats: DashboardStats = {
  totalDocuments: 12,
  totalWords: 3456,
  streakDays: 5,
  docsEditedThisWeek: 3,
  dailyWords: [],
  dailyActivity: []
}

test('renders all four tiles with their values', () => {
  render(<DashboardStatTiles stats={stats} />)
  expect(screen.getByTestId('stat-tile-total-documents')).toHaveTextContent(
    '12'
  )
  expect(screen.getByTestId('stat-tile-total-words')).toHaveTextContent('3,456')
  expect(screen.getByTestId('stat-tile-streak-days')).toHaveTextContent('5')
  expect(
    screen.getByTestId('stat-tile-docs-edited-this-week')
  ).toHaveTextContent('3')
})
