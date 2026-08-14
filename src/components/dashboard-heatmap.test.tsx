import { render, screen } from '@testing-library/react'

import { DashboardHeatmap } from '#components/dashboard-heatmap'
import type { DailyActivity } from '#lib/types'

test('renders one cell per day, each with a title describing the count', () => {
  const days: DailyActivity[] = [
    { date: '2026-01-01', activityCount: 0 },
    { date: '2026-01-02', activityCount: 4 }
  ]
  render(<DashboardHeatmap days={days} />)
  expect(screen.getByTestId('heatmap-cell-2026-01-01')).toHaveAttribute(
    'title',
    expect.stringContaining('0 edits')
  )
  expect(screen.getByTestId('heatmap-cell-2026-01-02')).toHaveAttribute(
    'title',
    expect.stringContaining('4 edits')
  )
})
