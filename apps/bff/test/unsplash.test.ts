import { describe, expect, test } from 'bun:test'

import { coverURL, listPhotos, toPhoto, triggerDownload } from '../src/unsplash.js'

const raw = {
  id: 'abc',
  color: '#0c2626',
  alt_description: 'storm',
  urls: {
    raw: 'https://images.unsplash.com/photo-1?ixid=M3w&ixlib=rb-4.0.3',
    thumb: 't',
    small: 's',
    regular: 'r',
    full: 'f'
  },
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

  test('the cover is the raw picture sized for a cover, not the original or the 1080 px one', () => {
    const cover = new URL(toPhoto(raw).cover)
    expect(cover.origin + cover.pathname).toBe('https://images.unsplash.com/photo-1')
    // Unsplash's ixid stays (still a hotlink of urls.raw); imgix sizes it.
    expect(cover.searchParams.get('ixid')).toBe('M3w')
    expect(cover.searchParams.get('w')).toBe('2560')
    expect(cover.searchParams.get('q')).toBe('85')
    expect(cover.searchParams.get('fm')).toBe('jpg')
    expect(cover.searchParams.get('fit')).toBe('max')
    // Params already on raw are replaced, not doubled.
    const resized = new URL(coverURL({ ...raw.urls, raw: 'https://images.unsplash.com/p?w=100' }))
    expect(resized.searchParams.getAll('w')).toEqual(['2560'])
    // No (or a broken) raw URL: the full-size one.
    expect(coverURL({ ...raw.urls, raw: undefined })).toBe('f')
    expect(coverURL({ ...raw.urls, raw: 'not a url' })).toBe('f')
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
      '/search/photos?query=clouds&page=2&per_page=24&orientation=landscape'
    )
    expect(seen[0]).toEndWith('Client-ID KEY')
    expect(result.status).toBe(200)
    expect(result.body).toEqual({ photos: [toPhoto(raw)], totalPages: 7 })
    expect(result.headers['X-Ratelimit-Remaining']).toBe('49')
  })

  test('without a query, a random batch of 24 landscape photos (no pages), duplicates dropped', async () => {
    const seen: string[] = []
    const result = await listPhotos(
      'KEY',
      '',
      999,
      fakeFetch([raw, { ...raw, id: 'def' }, raw], 200, seen)
    )
    const url = new URL(seen[0]!.split(' ')[0]!)
    expect(url.origin + url.pathname).toBe('https://api.unsplash.com/photos/random')
    expect(url.searchParams.get('orientation')).toBe('landscape')
    expect(url.searchParams.get('count')).toBe('24')
    expect(url.searchParams.has('page')).toBe(false)
    expect(url.searchParams.has('per_page')).toBe(false)
    expect(url.searchParams.has('query')).toBe(false)
    expect(result.body).toEqual({
      photos: [toPhoto(raw), toPhoto({ ...raw, id: 'def' })],
      totalPages: null
    })
  })

  test('an answer without a list of photos is a failure', async () => {
    expect(await listPhotos('KEY', 'x', 1, fakeFetch({ results: null }))).toMatchObject({
      status: 502,
      error: 'upstreamFailed'
    })
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

  test("Unsplash's failures answer with the error contract, not its raw status", async () => {
    const location = 'https://api.unsplash.com/photos/abc/download'
    expect(await triggerDownload('KEY', location, fakeFetch({}, 403))).toMatchObject({
      status: 429,
      error: 'rateLimited'
    })
    expect(await triggerDownload('KEY', location, fakeFetch({}, 404))).toMatchObject({
      status: 502,
      error: 'upstreamFailed'
    })
    const offline = (async () => {
      throw new Error('network down')
    }) as unknown as typeof fetch
    expect(await triggerDownload('KEY', location, offline)).toMatchObject({
      status: 502,
      error: 'upstreamFailed'
    })
    expect(await listPhotos('KEY', 'storm', 1, offline)).toMatchObject({
      status: 502,
      error: 'upstreamFailed'
    })
    const notJSON = (async () => new Response('<html>', { status: 200 })) as unknown as typeof fetch
    expect(await listPhotos('KEY', 'storm', 1, notJSON)).toMatchObject({
      status: 502,
      error: 'upstreamFailed'
    })
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
