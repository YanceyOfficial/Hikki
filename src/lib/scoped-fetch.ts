// AI provider domains that actually need @tauri-apps/plugin-http's fetch to
// bypass the webview's CORS restrictions (spec §14b) - kept in exact sync
// with src-tauri/capabilities/default.json's http:default origin scope.
const AI_PROVIDER_ORIGINS = [
  'https://api.openai.com',
  'https://api.anthropic.com'
]

function requestUrl(input: RequestInfo | URL): string {
  if (typeof input === 'string') return input
  if (input instanceof URL) return input.href
  return input.url
}

export function isAiProviderUrl(url: string): boolean {
  return AI_PROVIDER_ORIGINS.some(
    (origin) => url === origin || url.startsWith(`${origin}/`)
  )
}

/**
 * Wraps `window.fetch` so only requests to the AI provider domains route
 * through `tauriFetch` (the expensive, IPC-backed native HTTP client) -
 * every other request (Vite dev tooling, the emoji picker's relative-URL
 * fetch, anything else in the app) keeps using the plain native fetch.
 *
 * A blanket `window.fetch = tauriFetch` replacement (the original approach)
 * silently rerouted every fetch call in the app through this same expensive
 * path, including ones that have nothing to do with the AI feature - which
 * turned out to pin the real Tauri webview's CPU/memory pegged even on an
 * idle dashboard with no AI request ever in flight.
 */
export function createScopedFetch(
  nativeFetch: typeof fetch,
  tauriFetch: typeof fetch
): typeof fetch {
  return (input, init) =>
    isAiProviderUrl(requestUrl(input))
      ? tauriFetch(input, init)
      : nativeFetch(input, init)
}
