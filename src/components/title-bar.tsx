import { Separator } from '#components/ui/separator'
import { SidebarTrigger } from '#components/ui/sidebar'
import { useTrafficLightInset } from '#hooks/use-traffic-light-inset'
import { cn } from '#lib/utils'

export function TitleBar() {
  const inset = useTrafficLightInset()
  return (
    <header
      data-tauri-drag-region
      data-testid="titlebar"
      className={cn(
        'bg-background flex h-11 shrink-0 items-center gap-2 border-b px-3',
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
        className="text-muted-foreground text-sm font-medium select-none"
      >
        Hikki
      </span>
    </header>
  )
}
