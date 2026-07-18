import { render, screen } from '@testing-library/react'
import { MemoryRouter } from 'react-router'

import { TitleBar } from '#components/title-bar'
import { SidebarProvider } from '#components/ui/sidebar'

const renderBar = () =>
  render(
    <MemoryRouter>
      <SidebarProvider>
        <TitleBar />
      </SidebarProvider>
    </MemoryRouter>
  )

test('titlebar is a drag region', () => {
  renderBar()
  const bar = screen.getByTestId('titlebar')
  expect(bar).toHaveAttribute('data-tauri-drag-region')
})

test('no traffic-light inset outside Tauri', () => {
  renderBar()
  expect(screen.getByTestId('titlebar').className).not.toContain('pl-[76px]')
})

test('renders sidebar toggle', () => {
  renderBar()
  expect(screen.getByTestId('sidebar-toggle')).toBeInTheDocument()
})
