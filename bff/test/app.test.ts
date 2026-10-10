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
