import { format, parseISO } from 'date-fns'
import { Area, AreaChart, CartesianGrid, XAxis } from 'recharts'

import { ChartContainer, type ChartConfig } from '#components/ui/chart'
import type { DailyWordCount } from '#lib/types'

const chartConfig: ChartConfig = {
  wordDelta: { label: 'Words written', color: 'var(--chart-1)' }
}

export function DashboardActivityChart({ days }: { days: DailyWordCount[] }) {
  return (
    <ChartContainer
      config={chartConfig}
      data-testid="dashboard-activity-chart"
      className="aspect-auto h-48 w-full"
    >
      <AreaChart data={days}>
        <CartesianGrid vertical={false} />
        <XAxis
          dataKey="date"
          tickLine={false}
          axisLine={false}
          minTickGap={32}
          tickFormatter={(value: string) => format(parseISO(value), 'MMM d')}
        />
        <Area
          dataKey="wordDelta"
          type="monotone"
          fill="var(--color-wordDelta)"
          stroke="var(--color-wordDelta)"
          fillOpacity={0.2}
        />
      </AreaChart>
    </ChartContainer>
  )
}
