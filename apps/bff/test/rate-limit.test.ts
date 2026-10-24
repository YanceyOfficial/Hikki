import { describe, expect, it } from 'bun:test'

import { Hono } from 'hono'

import app, { allowedOrigin } from '../src/index.js'
import { rateLimit } from '../src/rate-limit.js'

describe('who may call the API', () => {
  it("answers CORS for the app's editor and a local dev server only", async () => {
    expect(allowedOrigin('hikki-editor://app')).toBe('hikki-editor://app')
    expect(allowedOrigin('http://localhost:5173')).toBe('http://localhost:5173')
    expect(allowedOrigin('http://127.0.0.1:4000')).toBe('http://127.0.0.1:4000')
    for (const origin of [
      'https://evil.example',
      'http://localhost.evil.example',
      'hikki-editor://other',
      undefined
    ])
      expect(allowedOrigin(origin)).toBeNull()

    const ours = await app.request('/api/unsplash/photos', {
      headers: { Origin: 'hikki-editor://app', 'X-Real-IP': '198.51.100.1' }
    })
    expect(ours.headers.get('Access-Control-Allow-Origin')).toBe('hikki-editor://app')
    const theirs = await app.request('/api/unsplash/photos', {
      headers: { Origin: 'https://evil.example', 'X-Real-IP': '198.51.100.2' }
    })
    expect(theirs.headers.get('Access-Control-Allow-Origin')).toBeNull()
  })
})

describe('rate limit', () => {
  it('stops one address past the limit with 429, Retry-After and the BFF error shape; others go on', async () => {
    const statuses: number[] = []
    for (let i = 0; i < 31; i++) {
      const response = await app.request('/api/unsplash/photos?query=x', {
        headers: { 'X-Real-IP': '203.0.113.7', 'X-Request-Id': 'req-limit-1' }
      })
      statuses.push(response.status)
      if (i === 30) {
        expect(response.status).toBe(429)
        expect(Number(response.headers.get('Retry-After'))).toBeGreaterThan(0)
        expect(await response.json()).toEqual({
          error: {
            code: 7006,
            id: 'rateLimited',
            message: 'Too many requests — try again in a moment.'
          },
          requestId: 'req-limit-1'
        })
      }
    }
    // Unconfigured here (no key): the first 30 reach the handler.
    expect(statuses.slice(0, 30).every((s) => s === 503)).toBe(true)
    const other = await app.request('/api/unsplash/photos?query=x', {
      headers: { 'X-Real-IP': '203.0.113.8' }
    })
    expect(other.status).toBe(503)
  })

  it('opens a new window once the old one has passed, and keeps its memory bounded', async () => {
    let now = 0
    const probe = new Hono()
    probe.use('*', rateLimit({ limit: 2, windowMs: 1000, now: () => now, maxClients: 2 }))
    probe.get('/', (c) => c.text('ok'))
    const hit = (ip: string) =>
      probe.request('/', { headers: { 'X-Forwarded-For': `${ip}, 10.0.0.1` } })
    expect((await hit('a')).status).toBe(200)
    expect((await hit('a')).status).toBe(200)
    const limited = await hit('a')
    expect(limited.status).toBe(429)
    expect(limited.headers.get('Retry-After')).toBe('1')
    now = 1000
    expect((await hit('a')).status).toBe(200)
    expect((await hit('a')).status).toBe(200)
    // Two more addresses push the oldest window out: 'a' starts over (it would be at its limit otherwise).
    await hit('b')
    await hit('c')
    expect((await hit('a')).status).toBe(200)
  })
})
