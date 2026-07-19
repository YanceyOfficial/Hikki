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
  SidebarMenuItem
} from '#components/ui/sidebar'
import { backend } from '#lib/backend/index'
import { docMetasAtom, refreshDocsAtom } from '#lib/store'
import { buildTree } from '#lib/tree'

export function SidebarLeft(props: React.ComponentProps<typeof Sidebar>) {
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
        <div className="flex items-center justify-between px-2 pt-1">
          <span className="text-sm font-semibold tracking-tight">Hikki</span>
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
