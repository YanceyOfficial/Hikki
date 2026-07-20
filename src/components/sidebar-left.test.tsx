import { render, screen } from '@testing-library/react'
import { MemoryRouter } from 'react-router'

import { SidebarLeft } from '#components/sidebar-left'
import { SidebarProvider } from '#components/ui/sidebar'

const renderSidebar = () =>
  render(
    <MemoryRouter>
      <SidebarProvider>
        <SidebarLeft />
      </SidebarProvider>
    </MemoryRouter>
  )

test('sidebar header is a drag region', () => {
  renderSidebar()
  expect(screen.getByTestId('sidebar-header-row')).toHaveAttribute(
    'data-tauri-drag-region'
  )
})

test('no traffic-light inset outside Tauri', () => {
  renderSidebar()
  expect(screen.getByTestId('sidebar-header-row').className).not.toContain(
    'pl-[76px]'
  )
})
