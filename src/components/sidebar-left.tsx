import { useAtomValue, useSetAtom } from 'jotai'
import { LayoutDashboard, Plus } from 'lucide-react'
import { useEffect, useMemo } from 'react'
import { useLocation, useNavigate } from 'react-router'

import { DocTree } from '#components/doc-tree'
import { Button } from '#components/ui/button'
import {
  Sidebar,
  SidebarContent,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  useSidebar
} from '#components/ui/sidebar'
import { useTrafficLightInset } from '#hooks/use-traffic-light-inset'
import { backend } from '#lib/backend/index'
import { docMetasAtom, refreshDocsAtom } from '#lib/store'
import { sidebarHeaderNeedsInset } from '#lib/traffic-light-gate'
import { buildTree } from '#lib/tree'
import { cn } from '#lib/utils'

export function SidebarLeft(props: React.ComponentProps<typeof Sidebar>) {
  const trafficLight = useTrafficLightInset()
  // Mirror of TitleBar's own gating: this header only sits at the window's
  // corner (and therefore only needs the inset) when the sidebar is actually
  // open on desktop. Collapsed (offcanvas) it's translated off-screen, and on
  // mobile it renders as an overlay Sheet rather than taking this corner, so
  // in both of those cases TitleBar reserves the inset instead. See
  // `#lib/traffic-light-gate` for the shared gating logic (and its tests).
  const { isMobile, state } = useSidebar()
  const inset = sidebarHeaderNeedsInset(trafficLight, isMobile, state)
  const metas = useAtomValue(docMetasAtom)
  const refresh = useSetAtom(refreshDocsAtom)
  const navigate = useNavigate()
  const location = useLocation()

  useEffect(() => {
    refresh()
  }, [refresh])

  const nodes = useMemo(() => buildTree(metas), [metas])
  const activeId = location.pathname.startsWith('/doc/')
    ? location.pathname.slice('/doc/'.length)
    : undefined

  const createDoc = async () => {
    const doc = await backend.createDocument(null, '')
    await refresh()
    navigate(`/doc/${doc.id}`)
  }

  const deleteDoc = async (id: string) => {
    await backend.deleteDocument(id)
    await refresh()
    if (id === activeId) navigate('/')
  }

  return (
    <Sidebar className="border-r-0" {...props}>
      <SidebarHeader>
        <div
          data-tauri-drag-region
          data-testid="sidebar-header-row"
          className={cn(
            'flex items-center justify-between px-2 pt-1 h-4.5',
            inset && 'pl-[76px]'
          )}
        >
          <span
            data-tauri-drag-region
            className="text-sm font-semibold tracking-tight"
          >
            Hikki
          </span>
          <Button
            variant="ghost"
            size="icon"
            className="text-muted-foreground hover:text-foreground size-7 transition-colors"
            onClick={createDoc}
            data-testid="new-doc"
          >
            <Plus />
            <span className="sr-only">New page</span>
          </Button>
        </div>
        <SidebarMenu>
          <SidebarMenuItem>
            <SidebarMenuButton
              isActive={location.pathname === '/'}
              onClick={() => navigate('/')}
              data-testid="nav-dashboard"
            >
              <LayoutDashboard />
              Dashboard
            </SidebarMenuButton>
          </SidebarMenuItem>
        </SidebarMenu>
      </SidebarHeader>
      <SidebarContent>
        <DocTree
          nodes={nodes}
          activeId={activeId}
          onSelect={(id) => navigate(`/doc/${id}`)}
          onDelete={deleteDoc}
        />
      </SidebarContent>
    </Sidebar>
  )
}
