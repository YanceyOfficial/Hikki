/**
 * Unsplash client. Calls go through Hikki's BFF (bff/), which keeps the Access Key server-side.
 * The BFF base URL comes from VITE_HIKKI_BFF_URL at build time; without it Unsplash is unavailable.
 */
/** Unsplash home with the referral utm params the attribution guideline asks for. */
export const UNSPLASH_HOME = 'https://unsplash.com/?utm_source=hikki&utm_medium=referral'

export type UnsplashPhoto = {
  id: string
  thumb: string
  regular: string
  full: string
  color: string | null
  alt: string | null
  author: string
  authorUrl: string
  photoUrl: string
  downloadLocation: string
}

export type UnsplashPage = { photos: UnsplashPhoto[]; totalPages: number | null }

export class UnsplashError extends Error {
  constructor(
    message: string,
    readonly status: number,
    /** The BFF's error code (design/errors.json), when it sent one. */
    readonly code: ErrorId = 'unknown'
  ) {
    super(message)
  }
}

import { errorForCode, type ErrorId } from '../generated/errors'
import { bffURL } from './bff'

export { bffURL }

export async function searchUnsplash(
  query: string,
  page = 1,
  base = bffURL(),
  fetcher: typeof fetch = fetch
): Promise<UnsplashPage> {
  if (!base) throw new UnsplashError('unsplash_not_configured', 0)
  const url = new URL(`${base}/api/unsplash/photos`)
  url.searchParams.set('query', query.trim())
  url.searchParams.set('page', String(page))
  const response = await fetcher(url)
  if (!response.ok) {
    // `{ error: { code, … }, requestId }` from the BFF; an older one answered 403 for Unsplash's hourly limit.
    const body = (await response.json().catch(() => null)) as { error?: { code?: number } } | null
    const code = errorForCode(body?.error?.code)
    const limited = code === 'rateLimited' || response.status === 403 || response.status === 429
    throw new UnsplashError(limited ? 'rate_limited' : 'unsplash_error', response.status, code)
  }
  return (await response.json()) as UnsplashPage
}

/** Unsplash guideline: picking a photo counts as a download. Fire-and-forget; never blocks the pick. */
export function trackUnsplashDownload(
  photo: UnsplashPhoto,
  base = bffURL(),
  fetcher: typeof fetch = fetch
): void {
  if (!base) return
  fetcher(`${base}/api/unsplash/download`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ downloadLocation: photo.downloadLocation })
  }).catch((error: unknown) => console.warn('[hikki] unsplash download tracking failed', error))
}
