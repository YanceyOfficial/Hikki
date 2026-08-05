import { act, render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { getDefaultStore } from 'jotai'
import { test, expect, beforeEach } from 'vitest'

import { SettingsDialog } from '#components/settings-dialog'
import { settingsDialogOpenAtom, settingsDialogSectionAtom } from '#lib/store'

beforeEach(() => {
  getDefaultStore().set(settingsDialogOpenAtom, false)
  getDefaultStore().set(settingsDialogSectionAtom, 'general')
})

test('closed by default, opens when settingsDialogOpenAtom is set', () => {
  render(<SettingsDialog />)
  expect(screen.queryByTestId('settings-dialog')).not.toBeInTheDocument()
  // `getDefaultStore().set` fires outside any React event handler, so React
  // 19's automatic batching defers the resulting re-render to a microtask;
  // without this `act` wrap the assertion below runs before the DOM updates.
  act(() => {
    getDefaultStore().set(settingsDialogOpenAtom, true)
  })
  expect(screen.getByTestId('settings-dialog')).toBeInTheDocument()
})

test('shows the General section by default and switches sections on nav click', async () => {
  getDefaultStore().set(settingsDialogOpenAtom, true)
  render(<SettingsDialog />)
  expect(screen.getByTestId('settings-section-general')).toBeInTheDocument()
  await userEvent.click(screen.getByTestId('settings-nav-ai'))
  expect(screen.getByTestId('settings-section-ai')).toBeInTheDocument()
  expect(
    screen.queryByTestId('settings-section-general')
  ).not.toBeInTheDocument()
})

test('opens directly to whichever section settingsDialogSectionAtom holds', () => {
  getDefaultStore().set(settingsDialogSectionAtom, 'logs')
  getDefaultStore().set(settingsDialogOpenAtom, true)
  render(<SettingsDialog />)
  expect(screen.getByTestId('settings-section-logs')).toBeInTheDocument()
})
