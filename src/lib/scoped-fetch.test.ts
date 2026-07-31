import { createScopedFetch, isAiProviderUrl } from '#lib/scoped-fetch'

test('isAiProviderUrl is true for the exact AI provider origins', () => {
  expect(isAiProviderUrl('https://api.openai.com/v1/responses')).toBe(true)
  expect(isAiProviderUrl('https://api.anthropic.com/v1/messages')).toBe(true)
})

test('isAiProviderUrl is false for everything else, including similar-looking hosts', () => {
  expect(
    isAiProviderUrl('http://localhost:1420/emojibase-data/en/data.json')
  ).toBe(false)
  expect(isAiProviderUrl('/emojibase-data/en/data.json')).toBe(false)
  expect(isAiProviderUrl('https://evil.com/api.openai.com')).toBe(false)
  expect(isAiProviderUrl('https://notapi.openai.com/v1/responses')).toBe(false)
  expect(isAiProviderUrl('https://api.openai.com.evil.com/v1')).toBe(false)
})

test('createScopedFetch routes AI provider requests through tauriFetch', async () => {
  const nativeFetch = vi.fn().mockResolvedValue(new Response('native'))
  const tauriFetch = vi.fn().mockResolvedValue(new Response('tauri'))
  const scopedFetch = createScopedFetch(nativeFetch, tauriFetch)

  await scopedFetch('https://api.openai.com/v1/responses')

  expect(tauriFetch).toHaveBeenCalledOnce()
  expect(nativeFetch).not.toHaveBeenCalled()
})

test('createScopedFetch routes every other request through the native fetch', async () => {
  const nativeFetch = vi.fn().mockResolvedValue(new Response('native'))
  const tauriFetch = vi.fn().mockResolvedValue(new Response('tauri'))
  const scopedFetch = createScopedFetch(nativeFetch, tauriFetch)

  await scopedFetch('/emojibase-data/en/data.json')
  await scopedFetch(new URL('http://localhost:1420/some/asset.js'))
  await scopedFetch(new Request('http://localhost:1420/vite-hmr-ping'))

  expect(nativeFetch).toHaveBeenCalledTimes(3)
  expect(tauriFetch).not.toHaveBeenCalled()
})

test('createScopedFetch handles Request/URL input the same way as a string URL', async () => {
  const nativeFetch = vi.fn().mockResolvedValue(new Response('native'))
  const tauriFetch = vi.fn().mockResolvedValue(new Response('tauri'))
  const scopedFetch = createScopedFetch(nativeFetch, tauriFetch)

  await scopedFetch(new URL('https://api.anthropic.com/v1/messages'))
  await scopedFetch(new Request('https://api.anthropic.com/v1/messages'))

  expect(tauriFetch).toHaveBeenCalledTimes(2)
  expect(nativeFetch).not.toHaveBeenCalled()
})
