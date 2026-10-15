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
  urls: { thumb: string; small: string; regular: string; full: string }
  links: { html: string; download_location: string }
  user: { name: string; links: { html: string } }
}

const withUtm = (url: string) => `${url}${url.includes('?') ? '&' : '?'}${UTM}`

export function toPhoto(raw: RawPhoto): Photo {
  return {
    id: raw.id,
    thumb: raw.urls.small,
    regular: raw.urls.regular,
    full: raw.urls.full,
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

/** Landscape photos for covers: search when there is a query, the editorial feed otherwise. */
export async function listPhotos(
  accessKey: string,
  query: string,
  page: number,
  fetcher: Fetch = fetch
): Promise<ProxyResult> {
  const q = query.trim()
  const url = new URL(q ? '/search/photos' : '/photos', UNSPLASH_API)
  url.searchParams.set('page', String(Math.max(1, Math.min(page, 50))))
  url.searchParams.set('per_page', '24')
  if (q) {
    url.searchParams.set('query', q.slice(0, 100))
    url.searchParams.set('orientation', 'landscape')
  }
  const upstream = await fetcher(url, {
    headers: { Authorization: `Client-ID ${accessKey}`, 'Accept-Version': 'v1' }
  })
  if (!upstream.ok) {
    // Unsplash says 403 when the hourly limit is used up.
    const error: ErrorId =
      upstream.status === 403 || upstream.status === 429 ? 'rateLimited' : 'upstreamFailed'
    return { status: ERRORS[error].status, body: null, error, headers: rateHeaders(upstream) }
  }
  const json = (await upstream.json()) as RawPhoto[] | { results: RawPhoto[]; total_pages: number }
  const raw = Array.isArray(json) ? json : json.results
  const totalPages = Array.isArray(json) ? null : json.total_pages
  return {
    status: 200,
    body: { photos: raw.map(toPhoto), totalPages },
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
  const upstream = await fetcher(url, {
    headers: { Authorization: `Client-ID ${accessKey}`, 'Accept-Version': 'v1' }
  })
  return { status: upstream.ok ? 204 : upstream.status, body: null, headers: rateHeaders(upstream) }
}
