import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { test, expect } from 'vitest'

import { AppearanceSection } from '#components/settings/appearance-section'
import { ThemeProvider } from '#components/theme-provider'

test('clicking Dark sets the theme to dark', async () => {
  render(
    <ThemeProvider>
      <AppearanceSection />
    </ThemeProvider>
  )
  await userEvent.click(screen.getByTestId('appearance-mode-dark'))
  expect(document.documentElement.className).toContain('dark')
})

test('clicking Light sets the theme to light', async () => {
  render(
    <ThemeProvider>
      <AppearanceSection />
    </ThemeProvider>
  )
  await userEvent.click(screen.getByTestId('appearance-mode-light'))
  expect(document.documentElement.className).not.toContain('dark')
})
