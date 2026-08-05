import { SidebarTrigger, useSidebar } from '#components/ui/sidebar'
import { useTrafficLightInset } from '#hooks/use-traffic-light-inset'
import { titleBarNeedsInset } from '#lib/traffic-light-gate'
import { cn } from '#lib/utils'

export function TitleBar() {
  const trafficLight = useTrafficLightInset()
  // The sidebar's own header (SidebarLeft) sits at the window's top-left
  // corner — and reserves the traffic-light inset itself — whenever it's
  // open on desktop. This bar only needs its own inset when *it's* the one
  // flush against that corner: sidebar collapsed on desktop, or always on
  // mobile (there the sidebar is an overlay Sheet, not part of the layout
  // flow, so this bar spans the full width regardless of open state). See
  // `#lib/traffic-light-gate` for the shared gating logic (and its tests).
  const { isMobile, state } = useSidebar()
  const inset = titleBarNeedsInset(trafficLight, isMobile, state)

  return (
    <header
      data-tauri-drag-region
      data-testid="titlebar"
      className={cn(
        'bg-sidebar flex h-9 shrink-0 items-center gap-2 border-b border-border/60 px-3',
        inset && 'pl-[76px]'
      )}
    >
      <SidebarTrigger data-testid="sidebar-toggle" />
      <div className="flex-1" />
    </header>
  )
}
