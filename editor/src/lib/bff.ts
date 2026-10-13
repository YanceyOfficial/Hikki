/**
 * The backend-for-frontend (`bff/`, Hono on Vercel): the Unsplash proxy and the embed shim pages. Its base URL
 * comes from VITE_HIKKI_BFF_URL at build time (editor/.env.*); without it those features are unavailable.
 */
export function bffURL(): string | null {
  const url = import.meta.env.VITE_HIKKI_BFF_URL as string | undefined
  return url ? url.replace(/\/+$/u, '') : null
}
