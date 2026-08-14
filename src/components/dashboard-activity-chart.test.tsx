import { render, screen } from '@testing-library/react'

import { DashboardActivityChart } from '#components/dashboard-activity-chart'
import type { DailyWordCount } from '#lib/types'

const days: DailyWordCount[] = [
  { date: '2026-01-01', wordDelta: 10 },
  { date: '2026-01-02', wordDelta: -3 }
]

test('renders the chart container', () => {
  render(<DashboardActivityChart days={days} />)
  expect(screen.getByTestId('dashboard-activity-chart')).toBeInTheDocument()
})
