import { beforeEach, expect, test } from 'vitest'

import {
  getAiModels,
  __getFauxProviderForTesting,
  __resetAiModelsForTesting
} from '#lib/ai/models'

beforeEach(() => {
  __resetAiModelsForTesting()
})

test('dev/test mode registers a faux provider with at least one model', () => {
  const models = getAiModels()
  const providers = models.getProviders()
  expect(providers.length).toBeGreaterThan(0)

  const allModels = models.getModels()
  expect(allModels.length).toBeGreaterThan(0)
})

test('repeated calls within a session return the same collection instance', () => {
  expect(getAiModels()).toBe(getAiModels())
})

test('the faux provider handle is reachable for scripting responses', () => {
  getAiModels() // ensure the singleton (and its faux provider) is initialized
  const faux = __getFauxProviderForTesting()
  expect(typeof faux.setResponses).toBe('function')
})
