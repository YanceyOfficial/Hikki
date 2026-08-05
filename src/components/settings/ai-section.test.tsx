import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { toast } from 'sonner'
import { beforeEach, expect, test, vi } from 'vitest'

import { AiSection } from '#components/settings/ai-section'
import { backend } from '#lib/backend/index'
import { reportError } from '#lib/errors'

vi.mock('sonner', () => ({
  toast: { error: vi.fn(), success: vi.fn() }
}))

vi.mock('#lib/errors', () => ({ reportError: vi.fn() }))

beforeEach(() => {
  vi.clearAllMocks()
})

test('saving an API key persists it through the backend', async () => {
  render(<AiSection />)

  const openaiKeyInput = await screen.findByTestId('ai-settings-key-openai')
  await userEvent.type(openaiKeyInput, 'sk-test-key')
  await userEvent.click(screen.getByTestId('ai-settings-save-openai'))

  await waitFor(async () => {
    expect(await backend.getApiKey('openai')).toBe('sk-test-key')
  })
})

test('changing the default model persists through the backend', async () => {
  render(<AiSection />)

  // Base UI's Select renders a trigger <button> (role="combobox"), not a
  // native <select> - open it, then click the first option in the portaled
  // listbox, rather than userEvent.selectOptions (native-<select>-only).
  await userEvent.click(await screen.findByTestId('ai-settings-default-model'))
  const options = await screen.findAllByRole('option')
  await userEvent.click(options[0])

  await waitFor(async () => {
    const settings = await backend.getAiSettings()
    expect(settings.defaultAiModel).not.toBeNull()
  })
})

test('a failed API key save surfaces a toast instead of failing silently', async () => {
  const setApiKeySpy = vi
    .spyOn(backend, 'setApiKey')
    .mockRejectedValueOnce(new Error('Keychain write failed'))
  render(<AiSection />)

  const openaiKeyInput = await screen.findByTestId('ai-settings-key-openai')
  await userEvent.type(openaiKeyInput, 'sk-test-key')
  await userEvent.click(screen.getByTestId('ai-settings-save-openai'))

  await waitFor(() => {
    expect(reportError).toHaveBeenCalledWith('HK-3003', {
      provider: 'openai',
      message: 'Keychain write failed'
    })
  })
  expect(toast.success).not.toHaveBeenCalled()
  setApiKeySpy.mockRestore()
})

test('a successful API key save surfaces a success toast', async () => {
  render(<AiSection />)

  const openaiKeyInput = await screen.findByTestId('ai-settings-key-openai')
  await userEvent.type(openaiKeyInput, 'sk-test-key')
  await userEvent.click(screen.getByTestId('ai-settings-save-openai'))

  await waitFor(() => {
    expect(toast.success).toHaveBeenCalledWith('Saved openai API key')
  })
})

test('a failed settings load surfaces a toast instead of an unhandled rejection', async () => {
  const getAiSettingsSpy = vi
    .spyOn(backend, 'getAiSettings')
    .mockRejectedValueOnce(new Error('IPC channel closed'))
  render(<AiSection />)

  await waitFor(() => {
    expect(reportError).toHaveBeenCalledWith('HK-3002', {
      message: 'IPC channel closed'
    })
  })
  getAiSettingsSpy.mockRestore()
})

test('a failed default provider/model save surfaces a toast', async () => {
  const saveAiSettingsSpy = vi
    .spyOn(backend, 'saveAiSettings')
    .mockRejectedValueOnce(new Error('disk full'))
  render(<AiSection />)

  await userEvent.click(await screen.findByTestId('ai-settings-default-model'))
  const options = await screen.findAllByRole('option')
  await userEvent.click(options[0])

  await waitFor(() => {
    expect(reportError).toHaveBeenCalledWith('HK-3004', {
      message: 'disk full'
    })
  })
  saveAiSettingsSpy.mockRestore()
})
