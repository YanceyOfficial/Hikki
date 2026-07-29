import {
  createModels,
  fauxProvider,
  type FauxProviderHandle,
  type Models
} from '@earendil-works/pi-ai'
import { anthropicProvider } from '@earendil-works/pi-ai/providers/anthropic'
import { openaiProvider } from '@earendil-works/pi-ai/providers/openai'

import { isTauri } from '#lib/backend/index'

export const AI_PROVIDER_IDS = ['openai', 'anthropic'] as const
export type AiProviderId = (typeof AI_PROVIDER_IDS)[number]

// Module-level lazy singleton - mirrors `backend/index.ts`'s own singleton
// pattern - so every call site (the AI client, the settings dialog, the
// popover) shares one `Models` collection, and in dev/test mode, one faux
// provider instance, rather than each independently creating its own
// isolated (and in the faux case, unscriptable-from-outside) collection.
let cachedModels: Models | undefined
let cachedFaux: FauxProviderHandle | undefined

export function getAiModels(): Models {
  if (cachedModels) return cachedModels

  const models = createModels()

  if (isTauri()) {
    models.setProvider(openaiProvider())
    models.setProvider(anthropicProvider())
  } else {
    // Dev server (pnpm dev) and Playwright e2e both run in plain-browser
    // mode, never inside the real Tauri app - real provider API calls would
    // need real API keys and would hit real, billed endpoints from CI/local
    // dev. The faux provider gives real streaming semantics (text_delta,
    // done, error - the same event shapes the UI code handles) with
    // deterministic, scripted, free responses instead.
    cachedFaux = fauxProvider()
    models.setProvider(cachedFaux.provider)
  }

  cachedModels = models
  return models
}

/** Test-only: clears the cached singleton so the next getAiModels() call builds a fresh collection (and, in non-Tauri mode, a fresh faux provider) - call in beforeEach so scripted responses never leak between tests. */
export function __resetAiModelsForTesting() {
  cachedModels = undefined
  cachedFaux = undefined
}

/** Test-only: the current cached faux-provider handle, for scripting responses via `.setResponses(...)`. Call `getAiModels()` at least once first (directly or indirectly) so the singleton - and its faux provider - actually exists. Throws if the cached instance is running in real-provider (Tauri) mode. */
export function __getFauxProviderForTesting(): FauxProviderHandle {
  if (!cachedFaux) {
    throw new Error(
      '__getFauxProviderForTesting() called with no cached faux provider - call getAiModels() first, and confirm this is not running in Tauri mode'
    )
  }
  return cachedFaux
}
