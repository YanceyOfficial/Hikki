import { fauxAssistantMessage, fauxText } from '@earendil-works/pi-ai'
import { beforeEach, expect, test, vi } from 'vitest'

vi.mock('#lib/backend/index', () => ({
  backend: { getApiKey: vi.fn().mockResolvedValue('sk-test-key') },
  isTauri: () => false
}))

import { streamWritingTool } from '#lib/ai/client'
import {
  getAiModels,
  __getFauxProviderForTesting,
  __resetAiModelsForTesting
} from '#lib/ai/models'
import { backend } from '#lib/backend/index'

beforeEach(() => {
  __resetAiModelsForTesting()
  vi.mocked(backend.getApiKey).mockReset()
  vi.mocked(backend.getApiKey).mockResolvedValue('sk-test-key')
})

async function collect(
  action: Parameters<typeof streamWritingTool>[0],
  text: string
) {
  const events = []
  const modelId = getAiModels().getModels()[0].id
  for await (const event of streamWritingTool(action, text, {
    provider: 'openai',
    modelId
  })) {
    events.push(event)
  }
  return events
}

test('streams text deltas then a done event', async () => {
  getAiModels() // initialize the singleton (and its faux provider) first
  __getFauxProviderForTesting().setResponses([
    fauxAssistantMessage([fauxText('Corrected text.')])
  ])

  const events = await collect({ kind: 'proofread' }, 'some text')
  expect(events.some((e) => e.type === 'delta')).toBe(true)
  expect(events[events.length - 1]).toEqual({ type: 'done' })
  expect(
    events
      .filter((e) => e.type === 'delta')
      .map((e) => (e as { type: 'delta'; text: string }).text)
      .join('')
  ).toBe('Corrected text.')
})

test('yields exactly one error event, no delta/done, when no API key is configured', async () => {
  getAiModels() // initialize the singleton (and its faux provider) first
  vi.mocked(backend.getApiKey).mockResolvedValue(null)

  const events = await collect({ kind: 'proofread' }, 'some text')
  expect(events).toHaveLength(1)
  expect(events[0]).toMatchObject({ type: 'error' })
  expect(
    (events[0] as { type: 'error'; message: string }).message.toLowerCase()
  ).toContain('key')
})

test('yields a single error event, not an uncaught rejection, when the getApiKey IPC call itself rejects', async () => {
  getAiModels() // initialize the singleton (and its faux provider) first
  vi.mocked(backend.getApiKey).mockRejectedValue(
    new Error('keychain access denied')
  )

  const events = await collect({ kind: 'proofread' }, 'some text')
  expect(events).toEqual([{ type: 'error', message: 'keychain access denied' }])
})
