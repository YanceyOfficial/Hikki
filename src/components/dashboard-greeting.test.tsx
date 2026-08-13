import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router'

import {
  DashboardGreeting,
  timeOfDayGreeting
} from '#components/dashboard-greeting'
import { backend } from '#lib/backend/index'

test.each([
  [0, 'Good morning'],
  [11, 'Good morning'],
  [12, 'Good afternoon'],
  [17, 'Good afternoon'],
  [18, 'Good evening'],
  [23, 'Good evening']
])('timeOfDayGreeting(%i) is %s', (hour, expected) => {
  expect(timeOfDayGreeting(hour)).toBe(expected)
})

test('renders a New document button that creates a document', async () => {
  render(
    <MemoryRouter>
      <DashboardGreeting />
    </MemoryRouter>
  )
  const before = await backend.listDocuments()
  await userEvent.click(screen.getByTestId('dashboard-new-doc'))
  const after = await backend.listDocuments()
  expect(after.length).toBe(before.length + 1)
})
