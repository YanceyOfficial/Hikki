import { ERRORS, type ErrorId } from './generated/errors.js'

/**
 * Unsplash proxy logic (kept apart from the Hono app so it is unit-testable with a fake fetch).
 * Unsplash API guidelines this enforces: the Access Key never leaves the server, images are
 * hotlinked from `urls`, attribution links carry utm params, and a pick triggers `download_location`.
 */
export const UNSPLASH_API = 'https://api.unsplash.com'
export const UTM = 'utm_source=hikki&utm_medium=referral'
export const RATE_LIMIT_HEADERS = ['X-Ratelimit-Limit', 'X-Ratelimit-Remaining']

export type Photo = {
  id: string
  /** Hotlink URLs (required by the guidelines). */
  thumb: string
  regular: string
  full: string
  /** What a pick sets as the cover: high resolution, sized for a cover (`coverURL`). */
  cover: string
  color: string | null
  alt: string | null
  author: string
  /** Photographer profile, with utm params. */
  authorUrl: string
  /** Photo page on Unsplash, with utm params. */
  photoUrl: string
  /** POST this back to /api/unsplash/download when the user picks the photo. */
  downloadLocation: string
}

type RawPhoto = {
  id: string
  color?: string | null
  alt_description?: string | null
  urls: { raw?: string; thumb: string; small: string; regular: string; full: string }
  links: { html: string; download_location: string }
  user: { name: string; links: { html: string } }
}

const withUtm = (url: string) => `${url}${url.includes('?') ? '&' : '?'}${UTM}`

/** imgix params on `urls.raw` for a cover: 2560 px wide fills a Retina window edge to edge, where `full` (the
 * original size, often 6000 px and 10 MB+) is far more than a cover shows and `regular` (1080 px) is soft. */
export const COVER_PARAMS = { w: '2560', q: '85', fm: 'jpg', fit: 'max' } as const

/** The picture a pick sets as the cover: `urls.raw` sized by `COVER_PARAMS` (its `ixid` kept: still a hotlink),
 * `urls.full` when there is no raw URL. */
export function coverURL(urls: RawPhoto['urls']): string {
  if (!urls.raw) return urls.full
  let url: URL
  try {
    url = new URL(urls.raw)
  } catch {
    return urls.full
  }
  for (const [name, value] of Object.entries(COVER_PARAMS)) url.searchParams.set(name, value)
  return url.toString()
}

export function toPhoto(raw: RawPhoto): Photo {
  return {
    id: raw.id,
    thumb: raw.urls.small,
    regular: raw.urls.regular,
    full: raw.urls.full,
    cover: coverURL(raw.urls),
    color: raw.color ?? null,
    alt: raw.alt_description ?? null,
    author: raw.user.name,
    authorUrl: withUtm(raw.user.links.html),
    photoUrl: withUtm(raw.links.html),
    downloadLocation: raw.links.download_location
  }
}

type Fetch = (input: string | URL, init?: RequestInit) => Promise<Response>

/** What a proxied call answers with; `error` (a code from design/errors.json) for a failure, its body then built
 * with the request's id. */
export type ProxyResult = {
  status: number
  body: unknown
  headers: Record<string, string>
  error?: ErrorId
}

function rateHeaders(response: Response): Record<string, string> {
  const headers: Record<string, string> = {}
  for (const name of RATE_LIMIT_HEADERS) {
    const value = response.headers.get(name)
    if (value) headers[name] = value
  }
  return headers
}

/** Photos per answer; `/photos/random` takes at most 30. */
export const PER_PAGE = 24

/** Landscape photos for covers: a search when there is a query, a random batch otherwise. `/photos/random` has no
 * pages: each `page` is just another batch (a different URL, so not the cached one), duplicates within it dropped —
 * a client loading more de-duplicates across batches by id. */
export async function listPhotos(
  accessKey: string,
  query: string,
  page: number,
  fetcher: Fetch = fetch
): Promise<ProxyResult> {
  const q = query.trim()
  const url = new URL(q ? '/search/photos' : '/photos/random', UNSPLASH_API)
  if (q) {
    url.searchParams.set('query', q.slice(0, 100))
    url.searchParams.set('page', String(Math.max(1, Math.min(page, 50))))
    url.searchParams.set('per_page', String(PER_PAGE))
  } else {
    url.searchParams.set('count', String(PER_PAGE))
  }
  url.searchParams.set('orientation', 'landscape')
  const upstream = await call(fetcher, url, accessKey)
  if (!(upstream instanceof Response)) return upstream
  if (!upstream.ok) return upstreamFailure(upstream)
  let json: RawPhoto[] | { results: RawPhoto[]; total_pages: number }
  try {
    json = (await upstream.json()) as typeof json
  } catch {
    return failure('upstreamFailed', rateHeaders(upstream))
  }
  const raw = Array.isArray(json) ? json : json.results
  if (!Array.isArray(raw)) return failure('upstreamFailed', rateHeaders(upstream))
  const seen = new Set<string>()
  const unique = raw.filter((photo) => !seen.has(photo.id) && Boolean(seen.add(photo.id)))
  const totalPages = Array.isArray(json) ? null : json.total_pages
  return {
    status: 200,
    body: { photos: unique.map(toPhoto), totalPages },
    headers: rateHeaders(upstream)
  }
}

/** Counts a download for the photographer. Only Unsplash download URLs are accepted (no open proxy). */
export async function triggerDownload(
  accessKey: string,
  downloadLocation: unknown,
  fetcher: Fetch = fetch
): Promise<ProxyResult> {
  let url: URL
  try {
    url = new URL(String(downloadLocation))
  } catch {
    return { status: 400, body: null, error: 'badRequest', headers: {} }
  }
  if (
    url.protocol !== 'https:' ||
    url.host !== 'api.unsplash.com' ||
    !/^\/photos\/[\w-]+\/download$/u.test(url.pathname)
  ) {
    return { status: 400, body: null, error: 'badRequest', headers: {} }
  }
  const upstream = await call(fetcher, url, accessKey)
  if (!(upstream instanceof Response)) return upstream
  if (!upstream.ok) return upstreamFailure(upstream)
  return { status: 204, body: null, headers: rateHeaders(upstream) }
}

/** How long Unsplash may take to answer before the request counts as failed (a hung upstream holds no function). */
export const UPSTREAM_TIMEOUT_MS = 8000

/** Unsplash, or a failure result when it can't be reached at all (or doesn't answer in time). */
async function call(fetcher: Fetch, url: URL, accessKey: string): Promise<Response | ProxyResult> {
  try {
    return await fetcher(url, {
      headers: { Authorization: `Client-ID ${accessKey}`, 'Accept-Version': 'v1' },
      signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS)
    })
  } catch {
    return failure('upstreamFailed', {})
  }
}

const failure = (error: ErrorId, headers: Record<string, string>): ProxyResult => ({
  status: ERRORS[error].status,
  body: null,
  error,
  headers
})

/** Unsplash answered with an error: its hourly limit (it says 403), or anything else it failed at. */
function upstreamFailure(upstream: Response): ProxyResult {
  const error: ErrorId =
    upstream.status === 403 || upstream.status === 429 ? 'rateLimited' : 'upstreamFailed'
  return failure(error, rateHeaders(upstream))
}
