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
    const response = await app.request('/api/unsplash/photos', {
      headers: { 'X-Request-Id': 'req-12345678' }
    })
    expect(response.status).toBe(503)
    // Every failure names its code and the request, which is echoed in a header for reports.
    expect(await response.json()).toEqual({
      error: {
        code: 7101,
        id: 'unsplashNotConfigured',
        message: "Unsplash isn't set up on the server."
      },
      requestId: 'req-12345678'
    })
    expect(response.headers.get('X-Request-Id')).toBe('req-12345678')
  })

  it('gives every request an id and logs one structured line without the query', async () => {
    const lines: string[] = []
    const { onError, requestLog } = await import('../src/http.js')
    const { Hono } = await import('hono')
    const probe = new Hono()
    probe.use(
      '*',
      requestLog((line: string) => lines.push(line))
    )
    probe.onError(onError)
    probe.get('/api/x', (c) => c.text('ok'))
    probe.get('/boom', () => {
      throw new Error('kaput')
    })
    const ok = await probe.request('/api/x?query=my+private+search')
    expect(ok.headers.get('X-Request-Id')).toMatch(/^[\w-]{8,}$/)
    const boom = await probe.request('/boom')
    expect(boom.status).toBe(500)
    expect((await boom.json()).error.code).toBe(1000)
    const [first, second] = lines.map((line) => JSON.parse(line))
    expect(first).toMatchObject({ level: 'info', method: 'GET', path: '/api/x', status: 200 })
    expect(lines[0]).not.toContain('private')
    expect(second).toMatchObject({ level: 'error', path: '/boom', status: 500, error: 'kaput' })
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
