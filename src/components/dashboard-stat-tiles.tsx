import { Card, CardContent, CardHeader, CardTitle } from '#components/ui/card'
import type { DashboardStats } from '#lib/types'

export function DashboardStatTiles({ stats }: { stats: DashboardStats }) {
  const tiles = [
    {
      key: 'total-documents',
      label: 'Documents',
      value: stats.totalDocuments
    },
    { key: 'total-words', label: 'Words written', value: stats.totalWords },
    { key: 'streak-days', label: 'Day streak', value: stats.streakDays },
    {
      key: 'docs-edited-this-week',
      label: 'Edited this week',
      value: stats.docsEditedThisWeek
    }
  ]

  return (
    <div
      data-testid="dashboard-stat-tiles"
      className="grid grid-cols-2 gap-4 @lg:grid-cols-4"
    >
      {tiles.map((tile) => (
        <Card key={tile.key} data-testid={`stat-tile-${tile.key}`}>
          <CardHeader>
            <CardTitle className="text-muted-foreground text-xs font-normal tracking-wide uppercase">
              {tile.label}
            </CardTitle>
          </CardHeader>
          <CardContent className="text-2xl font-semibold tabular-nums">
            {tile.value.toLocaleString()}
          </CardContent>
        </Card>
      ))}
    </div>
  )
}
