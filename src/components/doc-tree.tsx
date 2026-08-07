import {
  ChevronRight,
  FilePlus,
  FileText,
  MoreHorizontal,
  Trash2
} from 'lucide-react'
import { useState } from 'react'

import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger
} from '#components/ui/collapsible'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
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
import { cn } from '#lib/utils'

interface DocTreeProps {
  nodes: TreeNode[]
  activeId?: string
  onSelect: (id: string) => void
  onDelete: (id: string) => void
  onCreateChild: (parentId: string) => void
}

function TreeItem({
  node,
  activeId,
  onSelect,
  onDelete,
  onCreateChild
}: { node: TreeNode } & Omit<DocTreeProps, 'nodes'>) {
  const { meta, children } = node
  const hasChildren = children.length > 0
  // `SidebarMenuAction`'s own `showOnHover` relies on Tailwind's named
  // `group-hover/menu-item` selector - but since `SidebarMenuItem` reuses
  // that *same* group name at every nesting depth (this component renders
  // itself recursively), and hovering a descendant also satisfies `:hover`
  // on every ancestor carrying that class, hovering any nested item lit up
  // its parents' action buttons too, not just its own. `onMouseEnter`/
  // `onMouseLeave` (unlike CSS `:hover`) don't bubble in React, so tracking
  // hover locally instead fixes that - but the listeners have to sit on a
  // wrapper containing *both* the row and the (absolutely-positioned,
  // sibling-in-the-DOM) action button, not just the row alone: moving the
  // cursor from the row onto the action button otherwise exits the row's
  // own bounds and fires onMouseLeave right as the user tries to reach it,
  // hiding it out from under the pointer. `CollapsibleContent` (the nested
  // children) stays *outside* this wrapper, as a sibling within
  // `SidebarMenuItem` - keeping it out of the hover-tracked subtree is what
  // stops a nested child's hover from re-cascading up to its ancestors.
  const [rowActive, setRowActive] = useState(false)
  const [menuOpen, setMenuOpen] = useState(false)
  const showActions = rowActive || menuOpen
  return (
    <Collapsible defaultOpen>
      <SidebarMenuItem>
        <div
          className="relative flex items-center gap-0.5"
          onMouseEnter={() => setRowActive(true)}
          onMouseLeave={() => setRowActive(false)}
          onFocus={() => setRowActive(true)}
          onBlur={() => setRowActive(false)}
        >
          <div className="flex min-w-0 flex-1 items-center gap-0.5">
            {hasChildren && (
              <CollapsibleTrigger
                render={
                  <button
                    type="button"
                    aria-label="Toggle nested documents"
                    // Rotates this row's own chevron directly off `&`
                    // (this exact button's own `data-panel-open`, which
                    // Base UI's `CollapsibleTrigger` mirrors from its own
                    // Collapsible) rather than Tailwind's named
                    // `group-data-open/collapsible` mechanism: that
                    // mechanism compiles to a plain descendant selector
                    // (`:is(.group\/collapsible[data-open] *)`), and since
                    // `TreeItem` renders itself recursively, every nesting
                    // depth reuses the *same* group name - so an ancestor's
                    // open state satisfied a descendant's own rotation
                    // selector too. Confirmed live: collapsing a 2-levels-
                    // deep item while its still-expanded ancestor stayed
                    // open left that item's own chevron rotated as if it
                    // were still open. Scoping to `&` (this exact element)
                    // makes the rotation depend only on this row's own
                    // state, regardless of ancestors.
                    className="text-muted-foreground hover:bg-sidebar-accent hover:text-sidebar-accent-foreground flex size-5 shrink-0 items-center justify-center rounded-md transition-colors duration-150 [&>svg]:transition-transform [&[data-panel-open]>svg]:rotate-90"
                    data-testid={`doc-toggle-${meta.id}`}
                  />
                }
              >
                <ChevronRight className="size-4 shrink-0" />
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
          <DropdownMenu open={menuOpen} onOpenChange={setMenuOpen}>
            <DropdownMenuTrigger
              render={
                <SidebarMenuAction
                  className={cn(
                    'transition-colors duration-150 md:opacity-0',
                    showActions && 'md:opacity-100'
                  )}
                  data-testid={`doc-actions-${meta.id}`}
                />
              }
            >
              <MoreHorizontal />
            </DropdownMenuTrigger>
            <DropdownMenuContent side="right" align="start" className="w-fit">
              <DropdownMenuItem
                onClick={() => onCreateChild(meta.id)}
                data-testid={`doc-add-child-${meta.id}`}
              >
                <FilePlus />
                New page inside
              </DropdownMenuItem>
              <DropdownMenuSeparator />
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
        </div>
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
                  onCreateChild={onCreateChild}
                />
              ))}
            </SidebarMenuSub>
          </CollapsibleContent>
        )}
      </SidebarMenuItem>
    </Collapsible>
  )
}

export function DocTree({
  nodes,
  activeId,
  onSelect,
  onDelete,
  onCreateChild
}: DocTreeProps) {
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
              onCreateChild={onCreateChild}
            />
          ))}
        </SidebarMenu>
      </SidebarGroupContent>
    </SidebarGroup>
  )
}
