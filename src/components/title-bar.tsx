import { Moon, Sun } from 'lucide-react'
import { useTheme } from 'next-themes'

import { Button } from '#components/ui/button'
import { Separator } from '#components/ui/separator'
import { SidebarTrigger } from '#components/ui/sidebar'
import { useTrafficLightInset } from '#hooks/use-traffic-light-inset'
import { cn } from '#lib/utils'

export function TitleBar() {
  const inset = useTrafficLightInset()
  const { resolvedTheme, setTheme } = useTheme()
  return (
    <header
      data-tauri-drag-region
      data-testid="titlebar"
      className={cn(
        'bg-background flex h-11 shrink-0 items-center gap-2 border-b border-border/60 px-3',
        inset && 'pl-[76px]'
      )}
    >
      <SidebarTrigger data-testid="sidebar-toggle" />
      <Separator
        orientation="vertical"
        className="mr-1 data-[orientation=vertical]:h-4"
      />
      <span
        data-tauri-drag-region
        className="text-muted-foreground text-sm font-medium transition-colors select-none"
      >
        Hikki
      </span>
      <div className="flex-1" />
      <Button
        variant="ghost"
        size="icon"
        className="size-7"
        data-testid="theme-toggle"
        onClick={() => setTheme(resolvedTheme === 'dark' ? 'light' : 'dark')}
      >
        {resolvedTheme === 'dark' ? (
          <Sun className="size-4" />
        ) : (
          <Moon className="size-4" />
        )}
        <span className="sr-only">Toggle theme</span>
      </Button>
    </header>
  )
}
