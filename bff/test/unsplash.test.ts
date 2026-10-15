import { describe, expect, test } from 'bun:test'

import { listPhotos, toPhoto, triggerDownload } from '../src/unsplash.js'

const raw = {
  id: 'abc',
  color: '#0c2626',
  alt_description: 'storm',
  urls: { thumb: 't', small: 's', regular: 'r', full: 'f' },
  links: {
    html: 'https://unsplash.com/photos/abc',
    download_location: 'https://api.unsplash.com/photos/abc/download?ixid=x'
  },
  user: { name: 'Jeremy Bishop', links: { html: 'https://unsplash.com/@jeremybishop' } }
}

const fakeFetch = (body: unknown, status = 200, seen: string[] = []) =>
  (async (input: string | URL, init?: RequestInit) => {
    seen.push(`${String(input)} ${new Headers(init?.headers).get('Authorization')}`)
    return new Response(JSON.stringify(body), {
      status,
      headers: { 'X-Ratelimit-Remaining': '49' }
    })
  }) as typeof fetch

describe('toPhoto', () => {
  test('keeps hotlink URLs and adds utm params to attribution links', () => {
    const photo = toPhoto(raw)
    expect(photo.thumb).toBe('s')
    expect(photo.regular).toBe('r')
    expect(photo.authorUrl).toBe(
      'https://unsplash.com/@jeremybishop?utm_source=hikki&utm_medium=referral'
    )
    expect(photo.photoUrl).toBe(
      'https://unsplash.com/photos/abc?utm_source=hikki&utm_medium=referral'
    )
    expect(photo.downloadLocation).toBe(raw.links.download_location)
  })
})

describe('listPhotos', () => {
  test('searches landscape photos with the server-side key', async () => {
    const seen: string[] = []
    const result = await listPhotos(
      'KEY',
      ' clouds ',
      2,
      fakeFetch({ results: [raw], total_pages: 7 }, 200, seen)
    )
    expect(seen[0]).toContain(
      '/search/photos?page=2&per_page=24&query=clouds&orientation=landscape'
    )
    expect(seen[0]).toEndWith('Client-ID KEY')
    expect(result.status).toBe(200)
    expect(result.body).toEqual({ photos: [toPhoto(raw)], totalPages: 7 })
    expect(result.headers['X-Ratelimit-Remaining']).toBe('49')
  })

  test('uses the editorial feed without a query and clamps the page', async () => {
    const seen: string[] = []
    await listPhotos('KEY', '', 999, fakeFetch([raw], 200, seen))
    expect(seen[0]).toContain('/photos?page=50&per_page=24')
    expect(seen[0]).not.toContain('query=')
  })

  test('passes upstream errors through without leaking the key', async () => {
    const result = await listPhotos(
      'KEY',
      'x',
      1,
      fakeFetch({ errors: ['Rate Limit Exceeded'] }, 403)
    )
    // Unsplash's 403 is its hourly limit: our rateLimited code (429); anything else is upstreamFailed (502).
    expect(result.status).toBe(429)
    expect(result.error).toBe('rateLimited')
    expect(JSON.stringify(result)).not.toContain('KEY')
    const broken = await listPhotos('KEY', 'x', 1, fakeFetch({}, 500))
    expect(broken).toMatchObject({ status: 502, error: 'upstreamFailed' })
  })
})

describe('triggerDownload', () => {
  test('forwards genuine Unsplash download URLs', async () => {
    const seen: string[] = []
    const result = await triggerDownload(
      'KEY',
      raw.links.download_location,
      fakeFetch({ url: 'x' }, 200, seen)
    )
    expect(result.status).toBe(204)
    expect(seen[0]).toStartWith('https://api.unsplash.com/photos/abc/download')
  })

  test('refuses anything else (no open proxy)', async () => {
    for (const bad of [
      'https://evil.example/photos/abc/download',
      'http://api.unsplash.com/photos/abc/download',
      'https://api.unsplash.com/me',
      'not a url',
      42
    ]) {
      const result = await triggerDownload('KEY', bad, fakeFetch({}))
      expect(result).toMatchObject({ status: 400, error: 'badRequest' })
    }
  })
})
