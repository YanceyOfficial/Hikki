import { render, screen } from '@testing-library/react'
import { useTheme } from 'next-themes'

import { ThemeProvider } from '#components/theme-provider'

function ThemeConsumer() {
  const { theme, setTheme } = useTheme()
  return (
    <div>
      <span data-testid="current-theme">{theme}</span>
      <button data-testid="go-dark" onClick={() => setTheme('dark')}>
        dark
      </button>
    </div>
  )
}

test('defaults to system and can switch to dark', async () => {
  render(
    <ThemeProvider>
      <ThemeConsumer />
    </ThemeProvider>
  )
  expect(await screen.findByTestId('current-theme')).toHaveTextContent('system')
})
