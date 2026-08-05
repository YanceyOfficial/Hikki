import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { test, expect, vi, beforeEach } from 'vitest'

vi.mock('@tauri-apps/plugin-dialog', () => ({ open: vi.fn() }))

import { open as openDialog } from '@tauri-apps/plugin-dialog'

import { GeneralSection } from '#components/settings/general-section'
import { ThemeProvider } from '#components/theme-provider'
import { backend } from '#lib/backend/index'

// `useTheme()` is used directly by GeneralSection's own AppearanceSwitcher
// now that Appearance is folded in, not a separate section - every render
// needs the same ThemeProvider wrapping appearance-section.test.tsx used.
const renderGeneral = () =>
  render(<GeneralSection />, { wrapper: ThemeProvider })

beforeEach(async () => {
  vi.mocked(openDialog).mockReset()
  // `backend` is this app's shared module-level singleton (imported the same
  // way the component itself imports it), not a fresh instance per test -
  // reset its vault path back to the known default so tests don't leak
  // state into each other regardless of declaration order.
  await backend.setVaultPath('(in-memory)')
})

test('shows the current vault path on mount', async () => {
  renderGeneral()
  await waitFor(() =>
    expect(screen.getByTestId('vault-path')).toHaveTextContent('(in-memory)')
  )
})

test('choosing a folder from the native picker updates the vault path', async () => {
  vi.mocked(openDialog).mockResolvedValue('/tmp/new-vault')
  renderGeneral()
  await waitFor(() => screen.getByTestId('vault-path'))
  await userEvent.click(screen.getByTestId('change-vault-path'))
  await waitFor(() =>
    expect(screen.getByTestId('vault-path')).toHaveTextContent('/tmp/new-vault')
  )
})

test('cancelling the native picker (null result) leaves the vault path unchanged', async () => {
  vi.mocked(openDialog).mockResolvedValue(null)
  renderGeneral()
  await waitFor(() => screen.getByTestId('vault-path'))
  await userEvent.click(screen.getByTestId('change-vault-path'))
  await waitFor(() =>
    expect(screen.getByTestId('vault-path')).toHaveTextContent('(in-memory)')
  )
})

test('rebuild index button calls backend.rebuildIndex', async () => {
  const spy = vi.spyOn(backend, 'rebuildIndex')
  renderGeneral()
  await waitFor(() => screen.getByTestId('vault-path'))
  await userEvent.click(screen.getByTestId('rebuild-index'))
  await waitFor(() => expect(spy).toHaveBeenCalled())
  spy.mockRestore()
})

test('clicking Dark sets the theme to dark', async () => {
  renderGeneral()
  await userEvent.click(screen.getByTestId('appearance-mode-dark'))
  expect(document.documentElement.className).toContain('dark')
})

test('clicking Light sets the theme to light', async () => {
  renderGeneral()
  await userEvent.click(screen.getByTestId('appearance-mode-light'))
  expect(document.documentElement.className).not.toContain('dark')
})
