import { act } from 'react'
import { afterEach } from 'vitest'

// Initialise i18next for every test (the app does this in main.tsx); tests run in English.
import '../src/i18n'

// No real network in tests: anything not mocked gets a 503 instead of reaching localhost (unhandled
// connection errors fail the run). Tests that care stub fetch themselves.
globalThis.fetch = (async () => new Response(null, { status: 503 })) as typeof fetch

// React schedules its work on setImmediate; a render still queued when a test ends ran after the DOM was torn
// down ("window is not defined", reported as an unhandled error). Flush it while the environment is up.
afterEach(async () => {
  await act(async () => {})
})
