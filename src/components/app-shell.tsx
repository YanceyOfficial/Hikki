import { Outlet } from 'react-router'

import { SidebarLeft } from '#components/sidebar-left'
import { TitleBar } from '#components/title-bar'
import { SidebarInset, SidebarProvider } from '#components/ui/sidebar'
import { Toaster } from '#components/ui/sonner'

export function AppShell() {
  return (
    <SidebarProvider>
      <SidebarLeft />
      <SidebarInset className="h-svh overflow-hidden">
        <TitleBar />
        <div
          data-testid="page-content"
          className="no-scrollbar @container min-h-0 flex-1 overflow-y-auto"
        >
          <Outlet />
        </div>
      </SidebarInset>
      <Toaster />
    </SidebarProvider>
  )
}
