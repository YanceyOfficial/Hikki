import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { expect, test } from 'vitest'

import { AiSettingsDialog } from '#components/ai-settings-dialog'
import { backend } from '#lib/backend/index'

test('saving an API key persists it through the backend', async () => {
  render(<AiSettingsDialog />)
  await userEvent.click(screen.getByTestId('ai-settings-trigger'))

  const openaiKeyInput = await screen.findByTestId('ai-settings-key-openai')
  await userEvent.type(openaiKeyInput, 'sk-test-key')
  await userEvent.click(screen.getByTestId('ai-settings-save-openai'))

  await waitFor(async () => {
    expect(await backend.getApiKey('openai')).toBe('sk-test-key')
  })
})

test('changing the default model persists through the backend', async () => {
  render(<AiSettingsDialog />)
  await userEvent.click(screen.getByTestId('ai-settings-trigger'))

  const modelSelect = await screen.findByTestId('ai-settings-default-model')
  await userEvent.selectOptions(
    modelSelect,
    modelSelect.querySelectorAll('option')[1] as HTMLOptionElement
  )

  await waitFor(async () => {
    const settings = await backend.getAiSettings()
    expect(settings.defaultAiModel).not.toBeNull()
  })
})
