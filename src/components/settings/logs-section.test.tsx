import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, expect, test, vi } from 'vitest'

vi.mock('@tauri-apps/plugin-dialog', () => ({ save: vi.fn() }))

import { save as saveDialog } from '@tauri-apps/plugin-dialog'

import { LogsSection } from '#components/settings/logs-section'
import { backend } from '#lib/backend/index'

beforeEach(async () => {
  await backend.clearLogs()
  vi.mocked(saveDialog).mockReset()
})

test('renders existing log entries newest first', async () => {
  await backend.appendLog({
    level: 'info',
    scope: 'a',
    message: 'first',
    timestamp: new Date(0).toISOString()
  })
  await backend.appendLog({
    level: 'error',
    scope: 'b',
    message: 'second',
    timestamp: new Date(1).toISOString()
  })
  render(<LogsSection />)
  const rows = await screen.findAllByTestId('log-row')
  expect(rows).toHaveLength(2)
  expect(rows[0]).toHaveTextContent('second')
  expect(rows[1]).toHaveTextContent('first')
})

test('level filter narrows the visible rows', async () => {
  await backend.appendLog({
    level: 'info',
    scope: 'a',
    message: 'calm',
    timestamp: new Date().toISOString()
  })
  await backend.appendLog({
    level: 'error',
    scope: 'b',
    message: 'boom',
    timestamp: new Date().toISOString()
  })
  render(<LogsSection />)
  await screen.findAllByTestId('log-row')
  // Base UI's Select renders a trigger <button> (role="combobox"), not a
  // native <select> - open it, then click the "Error" option in the
  // portaled listbox, rather than userEvent.selectOptions.
  await userEvent.click(screen.getByTestId('log-level-filter'))
  await userEvent.click(await screen.findByRole('option', { name: 'Error' }))
  await waitFor(async () => {
    const rows = await screen.findAllByTestId('log-row')
    expect(rows).toHaveLength(1)
    expect(rows[0]).toHaveTextContent('boom')
  })
})

test('text search narrows the visible rows', async () => {
  await backend.appendLog({
    level: 'info',
    scope: 'a',
    message: 'vault reindexed',
    timestamp: new Date().toISOString()
  })
  await backend.appendLog({
    level: 'info',
    scope: 'b',
    message: 'ai request sent',
    timestamp: new Date().toISOString()
  })
  render(<LogsSection />)
  await screen.findAllByTestId('log-row')
  await userEvent.type(screen.getByTestId('log-search'), 'vault')
  await waitFor(async () => {
    const rows = await screen.findAllByTestId('log-row')
    expect(rows).toHaveLength(1)
    expect(rows[0]).toHaveTextContent('vault reindexed')
  })
})

test('clear button empties the log list', async () => {
  await backend.appendLog({
    level: 'info',
    scope: 'a',
    message: 'x',
    timestamp: new Date().toISOString()
  })
  render(<LogsSection />)
  await screen.findAllByTestId('log-row')
  await userEvent.click(screen.getByTestId('logs-clear'))
  await waitFor(() =>
    expect(screen.queryAllByTestId('log-row')).toHaveLength(0)
  )
})

test('export writes the currently-filtered rows via the native save dialog', async () => {
  vi.mocked(saveDialog).mockResolvedValue('/tmp/hikki-logs.jsonl')
  await backend.appendLog({
    level: 'info',
    scope: 'a',
    message: 'x',
    timestamp: new Date().toISOString()
  })
  render(<LogsSection />)
  await screen.findAllByTestId('log-row')
  await userEvent.click(screen.getByTestId('logs-export'))
  await waitFor(() => expect(saveDialog).toHaveBeenCalled())
})
