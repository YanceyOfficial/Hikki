import { ChevronRight, FileText, MoreHorizontal, Trash2 } from 'lucide-react'

import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger
} from '#components/ui/collapsible'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger
} from '#components/ui/dropdown-menu'
import {
  SidebarGroup,
  SidebarGroupContent,
  SidebarGroupLabel,
  SidebarMenu,
  SidebarMenuAction,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarMenuSub
} from '#components/ui/sidebar'
import type { TreeNode } from '#lib/tree'

interface DocTreeProps {
  nodes: TreeNode[]
  activeId?: string
  onSelect: (id: string) => void
  onDelete: (id: string) => void
}

function TreeItem({
  node,
  activeId,
  onSelect,
  onDelete
}: { node: TreeNode } & Omit<DocTreeProps, 'nodes'>) {
  const { meta, children } = node
  const hasChildren = children.length > 0
  return (
    <Collapsible defaultOpen className="group/collapsible">
      <SidebarMenuItem>
        <div className="flex items-center gap-0.5">
          {hasChildren && (
            <CollapsibleTrigger
              render={
                <button
                  type="button"
                  aria-label="Toggle nested documents"
                  className="text-muted-foreground hover:bg-sidebar-accent hover:text-sidebar-accent-foreground flex size-5 shrink-0 items-center justify-center rounded-md transition-colors duration-150"
                  data-testid={`doc-toggle-${meta.id}`}
                />
              }
            >
              <ChevronRight className="size-4 shrink-0 transition-transform group-data-open/collapsible:rotate-90" />
            </CollapsibleTrigger>
          )}
          <SidebarMenuButton
            isActive={meta.id === activeId}
            onClick={() => onSelect(meta.id)}
            className="w-auto min-w-0 flex-1 transition-colors duration-150"
            data-testid={`doc-item-${meta.id}`}
          >
            <span className="text-muted-foreground flex size-4 items-center justify-center">
              {meta.icon ?? <FileText className="size-4" />}
            </span>
            <span className="truncate">{meta.title || 'Untitled'}</span>
          </SidebarMenuButton>
        </div>
        <DropdownMenu>
          <DropdownMenuTrigger
            render={
              <SidebarMenuAction
                className="transition-colors duration-150"
                showOnHover
                data-testid={`doc-actions-${meta.id}`}
              />
            }
          >
            <MoreHorizontal />
          </DropdownMenuTrigger>
          <DropdownMenuContent side="right" align="start">
            <DropdownMenuItem
              variant="destructive"
              onClick={() => onDelete(meta.id)}
              data-testid={`doc-delete-${meta.id}`}
            >
              <Trash2 />
              Move to Trash
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
        {hasChildren && (
          <CollapsibleContent>
            <SidebarMenuSub className="mr-0 pr-0">
              {children.map((child) => (
                <TreeItem
                  key={child.meta.id}
                  node={child}
                  activeId={activeId}
                  onSelect={onSelect}
                  onDelete={onDelete}
                />
              ))}
            </SidebarMenuSub>
          </CollapsibleContent>
        )}
      </SidebarMenuItem>
    </Collapsible>
  )
}

export function DocTree({ nodes, activeId, onSelect, onDelete }: DocTreeProps) {
  return (
    <SidebarGroup>
      <SidebarGroupLabel>Documents</SidebarGroupLabel>
      <SidebarGroupContent>
        <SidebarMenu data-testid="doc-tree">
          {nodes.map((node) => (
            <TreeItem
              key={node.meta.id}
              node={node}
              activeId={activeId}
              onSelect={onSelect}
              onDelete={onDelete}
            />
          ))}
        </SidebarMenu>
      </SidebarGroupContent>
    </SidebarGroup>
  )
}
