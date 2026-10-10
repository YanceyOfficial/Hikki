/**
 * Unsplash client. Calls go through Hikki's BFF (bff/), which keeps the Access Key server-side.
 * The BFF base URL comes from VITE_HIKKI_BFF_URL at build time; without it Unsplash is unavailable.
 */
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
    readonly status: number
  ) {
    super(message)
  }
}

export function bffURL(): string | null {
  const url = import.meta.env.VITE_HIKKI_BFF_URL as string | undefined
  return url ? url.replace(/\/$/u, '') : null
}

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
  if (!response.ok)
    throw new UnsplashError(
      response.status === 403 ? 'rate_limited' : 'unsplash_error',
      response.status
    )
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
