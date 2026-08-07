import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'

import { DocTree } from '#components/doc-tree'
import { SidebarProvider } from '#components/ui/sidebar'
import type { TreeNode } from '#lib/tree'
import type { DocumentMeta } from '#lib/types'

const meta = (id: string, title: string): DocumentMeta => ({
  id,
  parentId: null,
  title,
  icon: null,
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  deletedAt: null
})

const nodes: TreeNode[] = [
  {
    meta: meta('a', 'Parent'),
    children: [{ meta: meta('b', 'Child'), children: [] }]
  }
]

const threeLevelNodes: TreeNode[] = [
  {
    meta: meta('a', 'Grandparent'),
    children: [
      {
        meta: meta('b', 'Parent'),
        children: [{ meta: meta('c', 'Child'), children: [] }]
      }
    ]
  }
]

const setup = (over: Partial<React.ComponentProps<typeof DocTree>> = {}) => {
  const onSelect = vi.fn()
  const onDelete = vi.fn()
  const onCreateChild = vi.fn()
  render(
    <SidebarProvider>
      <DocTree
        nodes={nodes}
        onSelect={onSelect}
        onDelete={onDelete}
        onCreateChild={onCreateChild}
        {...over}
      />
    </SidebarProvider>
  )
  return { onSelect, onDelete, onCreateChild }
}

test('renders nested titles', () => {
  setup()
  expect(screen.getByText('Parent')).toBeInTheDocument()
  expect(screen.getByText('Child')).toBeInTheDocument()
})

test('untitled documents get a fallback label', () => {
  const onSelect = vi.fn()
  render(
    <SidebarProvider>
      <DocTree
        nodes={[{ meta: meta('x', ''), children: [] }]}
        onSelect={onSelect}
        onDelete={vi.fn()}
        onCreateChild={vi.fn()}
      />
    </SidebarProvider>
  )
  expect(screen.getByText('Untitled')).toBeInTheDocument()
})

test('clicking a row selects it', async () => {
  const { onSelect } = setup()
  await userEvent.click(screen.getByText('Child'))
  expect(onSelect).toHaveBeenCalledWith('b')
})

test('delete action fires onDelete', async () => {
  const { onDelete } = setup()
  await userEvent.click(screen.getByTestId('doc-actions-a'))
  await userEvent.click(await screen.findByTestId('doc-delete-a'))
  expect(onDelete).toHaveBeenCalledWith('a')
})

test('add-child action fires onCreateChild with the parent id', async () => {
  const { onCreateChild } = setup()
  await userEvent.click(screen.getByTestId('doc-actions-a'))
  await userEvent.click(await screen.findByTestId('doc-add-child-a'))
  expect(onCreateChild).toHaveBeenCalledWith('a')
})

test('expand/collapse toggle only renders for nodes with children', () => {
  setup()
  expect(screen.getByTestId('doc-toggle-a')).toBeInTheDocument()
  expect(screen.queryByTestId('doc-toggle-b')).not.toBeInTheDocument()
})

test('toggling expand/collapse does not select the row', async () => {
  const { onSelect } = setup()
  await userEvent.click(screen.getByTestId('doc-toggle-a'))
  expect(onSelect).not.toHaveBeenCalled()
})

test('hovering a nested child does not reveal its ancestor actions', async () => {
  setup()
  await userEvent.hover(screen.getByTestId('doc-item-b'))
  expect(screen.getByTestId('doc-actions-b').className).toContain(
    'md:opacity-100'
  )
  expect(screen.getByTestId('doc-actions-a').className).not.toContain(
    'md:opacity-100'
  )
})

test('moving the pointer onto the actions button keeps it visible', async () => {
  setup()
  await userEvent.hover(screen.getByTestId('doc-item-a'))
  await userEvent.hover(screen.getByTestId('doc-actions-a'))
  expect(screen.getByTestId('doc-actions-a').className).toContain(
    'md:opacity-100'
  )
})

test('collapsing a nested item does not affect its still-open ancestor', async () => {
  setup({ nodes: threeLevelNodes })
  // Both start expanded (`defaultOpen`); collapse just the middle item ("b")
  // while its grandparent ("a") stays open - regression coverage for the
  // chevron rotation cascading via a reused Tailwind named group (see
  // doc-tree.tsx's `[&[data-panel-open]>svg]:rotate-90` comment).
  await userEvent.click(screen.getByTestId('doc-toggle-b'))
  expect(screen.getByTestId('doc-toggle-a')).toHaveAttribute('data-panel-open')
  expect(screen.getByTestId('doc-toggle-b')).not.toHaveAttribute(
    'data-panel-open'
  )
  expect(screen.queryByText('Child')).not.toBeInTheDocument()
})
