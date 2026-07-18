import { render, screen } from '@testing-library/react'
import { MemoryRouter, Route, Routes } from 'react-router'

import { AppShell } from '#components/app-shell'

test('renders exactly one main landmark', () => {
  render(
    <MemoryRouter>
      <Routes>
        <Route path="/" element={<AppShell />}>
          <Route index element={<div data-testid="child" />} />
        </Route>
      </Routes>
    </MemoryRouter>
  )
  expect(screen.getAllByRole('main')).toHaveLength(1)
  expect(screen.getByTestId('child')).toBeInTheDocument()
})
