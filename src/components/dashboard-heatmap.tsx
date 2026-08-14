import { format, parseISO } from 'date-fns'

import { bucketActivityLevel, type ActivityLevel } from '#lib/activity-level'
import type { DailyActivity } from '#lib/types'

// 35 days = exactly 5 full weeks, so a plain 7-column grid in chronological
// order naturally keeps every column aligned to the same weekday - no
// leading blank cells needed, unlike a literal calendar-month grid.
const LEVEL_CLASSES: Record<ActivityLevel, string> = {
  none: 'bg-muted',
  low: 'bg-primary/25',
  medium: 'bg-primary/55',
  high: 'bg-primary/90'
}

export function DashboardHeatmap({ days }: { days: DailyActivity[] }) {
  return (
    <div data-testid="dashboard-heatmap" className="grid grid-cols-7 gap-1">
      {days.map((day) => {
        const level = bucketActivityLevel(day.activityCount)
        const label = `${day.activityCount} edit${day.activityCount === 1 ? '' : 's'}`
        return (
          <div
            key={day.date}
            data-testid={`heatmap-cell-${day.date}`}
            title={`${format(parseISO(day.date), 'MMM d')}: ${label}`}
            className={`aspect-square rounded-sm ${LEVEL_CLASSES[level]}`}
          />
        )
      })}
    </div>
  )
}
