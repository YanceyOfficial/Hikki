import { useAtomValue, useSetAtom } from 'jotai'
import { useEffect } from 'react'

import { DashboardActivityChart } from '#components/dashboard-activity-chart'
import { DashboardGreeting } from '#components/dashboard-greeting'
import { DashboardHeatmap } from '#components/dashboard-heatmap'
import { DashboardRecentList } from '#components/dashboard-recent-list'
import { DashboardStatTiles } from '#components/dashboard-stat-tiles'
import { reportError } from '#lib/errors'
import {
  dashboardStatsAtom,
  recentDocsAtom,
  refreshDashboardAtom
} from '#lib/store'

const EMPTY_STATS = {
  totalDocuments: 0,
  totalWords: 0,
  streakDays: 0,
  docsEditedThisWeek: 0,
  dailyWords: [],
  dailyActivity: []
}

export default function DashboardPage() {
  const stats = useAtomValue(dashboardStatsAtom)
  const recentDocs = useAtomValue(recentDocsAtom)
  const refreshDashboard = useSetAtom(refreshDashboardAtom)

  useEffect(() => {
    let active = true
    refreshDashboard().catch(() => {
      if (active) reportError('HK-7001')
    })
    return () => {
      active = false
    }
  }, [refreshDashboard])

  const shown = stats ?? EMPTY_STATS

  return (
    <div
      data-testid="dashboard-page"
      className="mx-auto flex w-full max-w-3xl flex-col gap-8 p-8"
    >
      <DashboardGreeting />
      <DashboardStatTiles stats={shown} />
      <DashboardActivityChart days={shown.dailyWords} />
      <DashboardHeatmap days={shown.dailyActivity} />
      <div>
        <h2 className="mb-2 text-sm font-medium">Recently edited</h2>
        <DashboardRecentList docs={recentDocs} />
      </div>
    </div>
  )
}
