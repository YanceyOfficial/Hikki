import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { test, expect, vi, beforeEach } from 'vitest'

vi.mock('@tauri-apps/plugin-dialog', () => ({ open: vi.fn() }))

import { open as openDialog } from '@tauri-apps/plugin-dialog'

import { GeneralSection } from '#components/settings/general-section'
import { backend } from '#lib/backend/index'

beforeEach(async () => {
  vi.mocked(openDialog).mockReset()
  // `backend` is this app's shared module-level singleton (imported the same
  // way the component itself imports it), not a fresh instance per test -
  // reset its vault path back to the known default so tests don't leak
  // state into each other regardless of declaration order.
  await backend.setVaultPath('(in-memory)')
})

test('shows the current vault path on mount', async () => {
  render(<GeneralSection />)
  await waitFor(() =>
    expect(screen.getByTestId('vault-path')).toHaveTextContent('(in-memory)')
  )
})

test('choosing a folder from the native picker updates the vault path', async () => {
  vi.mocked(openDialog).mockResolvedValue('/tmp/new-vault')
  render(<GeneralSection />)
  await waitFor(() => screen.getByTestId('vault-path'))
  await userEvent.click(screen.getByTestId('change-vault-path'))
  await waitFor(() =>
    expect(screen.getByTestId('vault-path')).toHaveTextContent('/tmp/new-vault')
  )
})

test('cancelling the native picker (null result) leaves the vault path unchanged', async () => {
  vi.mocked(openDialog).mockResolvedValue(null)
  render(<GeneralSection />)
  await waitFor(() => screen.getByTestId('vault-path'))
  await userEvent.click(screen.getByTestId('change-vault-path'))
  await waitFor(() =>
    expect(screen.getByTestId('vault-path')).toHaveTextContent('(in-memory)')
  )
})

test('rebuild index button calls backend.rebuildIndex', async () => {
  const spy = vi.spyOn(backend, 'rebuildIndex')
  render(<GeneralSection />)
  await waitFor(() => screen.getByTestId('vault-path'))
  await userEvent.click(screen.getByTestId('rebuild-index'))
  await waitFor(() => expect(spy).toHaveBeenCalled())
  spy.mockRestore()
})
