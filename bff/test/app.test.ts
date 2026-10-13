import { afterEach, describe, expect, it } from 'bun:test'

import app from '../src/index.js'

const realFetch = globalThis.fetch

describe('app', () => {
  afterEach(() => {
    globalThis.fetch = realFetch
    delete process.env.UNSPLASH_ACCESS_KEY
  })

  it('reports Unsplash as unconfigured without UNSPLASH_ACCESS_KEY', async () => {
    delete process.env.UNSPLASH_ACCESS_KEY
    const response = await app.request('/api/unsplash/photos')
    expect(response.status).toBe(503)
  })

  it('serves the YouTube shim page for a valid id, with the start offset, and refuses anything else', async () => {
    const ok = await app.request('/embed/youtube/dQw4w9WgXcQ?start=42')
    expect(ok.status).toBe(200)
    expect(ok.headers.get('Content-Type')).toContain('text/html')
    const html = await ok.text()
    expect(html).toContain('src="https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?start=42"')
    expect(html).toContain('referrerpolicy="strict-origin-when-cross-origin"')
    const plain = await (await app.request('/embed/youtube/dQw4w9WgXcQ')).text()
    expect(plain).toContain('src="https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ"')
    expect((await app.request('/embed/youtube/%3Cscript%3E')).status).toBe(400)
    expect((await app.request('/embed/youtube/a')).status).toBe(400)
  })

  it('reads UNSPLASH_ACCESS_KEY from the runtime env and sends it upstream', async () => {
    process.env.UNSPLASH_ACCESS_KEY = 'test-key'
    let auth = null as string | null
    globalThis.fetch = (async (_url: string | URL | Request, init?: RequestInit) => {
      auth = new Headers(init?.headers).get('Authorization')
      return new Response('[]')
    }) as typeof fetch
    const response = await app.request('/api/unsplash/photos')
    expect(response.status).toBe(200)
    expect(auth).toBe('Client-ID test-key')
  })
})
