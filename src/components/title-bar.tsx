import { useSetAtom } from 'jotai'
import { Moon, Settings as SettingsIcon, Sun } from 'lucide-react'
import { useTheme } from 'next-themes'
import { useEffect } from 'react'

import { SettingsDialog } from '#components/settings-dialog'
import { Button } from '#components/ui/button'
import { SidebarTrigger, useSidebar } from '#components/ui/sidebar'
import { useTrafficLightInset } from '#hooks/use-traffic-light-inset'
import { openSettingsAtom } from '#lib/store'
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
  const { resolvedTheme, setTheme } = useTheme()
  const openSettings = useSetAtom(openSettingsAtom)

  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === ',' && (event.metaKey || event.ctrlKey)) {
        event.preventDefault()
        openSettings()
      }
    }
    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [openSettings])

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
      <Button
        variant="ghost"
        size="icon"
        className="size-7"
        data-testid="settings-trigger"
        onClick={() => openSettings()}
      >
        <SettingsIcon className="size-4" />
        <span className="sr-only">Settings</span>
      </Button>
      <SettingsDialog />
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
