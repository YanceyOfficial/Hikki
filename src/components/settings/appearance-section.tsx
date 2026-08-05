import { useTheme } from 'next-themes'

import { Button } from '#components/ui/button'
import { cn } from '#lib/utils'

const MODES = ['light', 'dark', 'system'] as const

export function AppearanceSection() {
  const { theme, setTheme } = useTheme()

  return (
    <div className="flex flex-col gap-2">
      <p className="text-sm font-medium">Appearance</p>
      <div className="flex gap-2">
        {MODES.map((mode) => (
          <Button
            key={mode}
            variant="outline"
            size="sm"
            data-testid={`appearance-mode-${mode}`}
            className={cn(theme === mode && 'border-ring')}
            onClick={() => setTheme(mode)}
          >
            {mode[0].toUpperCase() + mode.slice(1)}
          </Button>
        ))}
      </div>
    </div>
  )
}
