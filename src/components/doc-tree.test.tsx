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

const setup = (over: Partial<React.ComponentProps<typeof DocTree>> = {}) => {
  const onSelect = vi.fn()
  const onDelete = vi.fn()
  render(
    <SidebarProvider>
      <DocTree
        nodes={nodes}
        onSelect={onSelect}
        onDelete={onDelete}
        {...over}
      />
    </SidebarProvider>
  )
  return { onSelect, onDelete }
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
