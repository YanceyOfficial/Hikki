import { Hono, type Context } from 'hono'
import { env } from 'hono/adapter'
import { cors } from 'hono/cors'

import { errorBody, fail, onError, requestIdOf, requestLog } from './http.js'
import { rateLimit } from './rate-limit.js'
import { listPhotos, triggerDownload, type ProxyResult } from './unsplash.js'

/**
 * Hikki's backend-for-frontend: keeps third-party API keys server-side (Unsplash requires its
 * Access Key to stay confidential). Deployed on Vercel; set UNSPLASH_ACCESS_KEY in the project env.
 */
const app = new Hono()

app.use('*', requestLog())
app.onError(onError)

/**
 * Pages that may call the API from a browser: the editor in the app's web view (its custom scheme, `hikki-editor://app`
 * — EditorSchemeHandler.entryURL) and the editor's dev server on this machine. The native app's own requests
 * (URLSession: the cover sheet's Unsplash) carry no Origin and aren't subject to CORS. CORS only keeps other web pages
 * from using the API through their visitors' browsers; the rate limit below is what holds back everyone else.
 */
export function allowedOrigin(origin: string | undefined): string | null {
  if (!origin) return null
  if (origin === 'hikki-editor://app') return origin
  return /^http:\/\/(?:localhost|127\.0\.0\.1)(?::\d{1,5})?$/u.test(origin) ? origin : null
}

app.use(
  '/api/*',
  cors({
    origin: (origin) => allowedOrigin(origin),
    allowMethods: ['GET', 'POST'],
    exposeHeaders: ['X-Ratelimit-Remaining', 'X-Request-Id', 'Retry-After']
  })
)

// Each search is an upstream request on the operator's Unsplash key: one address gets 30 a minute, picks (download
// reports) as many. Searches are debounced in the editor and a page of results is 30 photos, so a person picking a
// cover stays well under it.
app.use('/api/unsplash/photos', rateLimit({ limit: 30, windowMs: 60_000 }))
app.use('/api/unsplash/download', rateLimit({ limit: 30, windowMs: 60_000 }))

app.get('/', (c) => c.text('hikki-bff'))

// Embed shim: YouTube's player refuses to play (error 153) without an HTTP Referer, and the editor's page
// — on the app's own scheme — sends none. This page, on https, holds the player, so the player sees a
// referrer. The id is checked, so it is the only thing that varies in the markup.
const YOUTUBE_ID = /^[\w-]{6,20}$/u

app.get('/embed/youtube/:id', (c) => {
  const id = c.req.param('id')
  if (!YOUTUBE_ID.test(id)) return fail(c, 'badRequest')
  const start = Number.parseInt(c.req.query('start') ?? '', 10)
  const src = `https://www.youtube-nocookie.com/embed/${id}${start > 0 ? `?start=${start}` : ''}`
  c.header('Cache-Control', 'public, max-age=86400')
  c.header(
    'Content-Security-Policy',
    "default-src 'none'; frame-src https://www.youtube-nocookie.com; style-src 'unsafe-inline'"
  )
  return c.html(
    `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>YouTube</title><style>html,body{margin:0;height:100%;background:#000}iframe{display:block;width:100%;height:100%;border:0}</style></head><body><iframe src="${src}" allow="autoplay; fullscreen; picture-in-picture; encrypted-media; clipboard-write" allowfullscreen referrerpolicy="strict-origin-when-cross-origin"></iframe></body></html>`
  )
})

// Read through Hono's adapter (not `process.env`) so the source needs no Node/Bun ambient types:
// Vercel type-checks src/ with its own compiler and doesn't see bun's isolated @types.
function accessKey(c: Context): string | null {
  return env<{ UNSPLASH_ACCESS_KEY?: string }>(c).UNSPLASH_ACCESS_KEY || null
}

function send(c: Context, result: ProxyResult): Response {
  const headers = new Headers(result.headers)
  if (result.body === null && !result.error)
    return new Response(null, { status: result.status, headers })
  // A failure from the proxy names its code; the body gets this request's id.
  const body = result.error ? errorBody(result.error, requestIdOf(c)) : result.body
  headers.set('Content-Type', 'application/json')
  headers.set('Cache-Control', result.status === 200 ? 'public, max-age=300' : 'no-store')
  return new Response(JSON.stringify(body), { status: result.status, headers })
}

app.get('/api/unsplash/photos', async (c) => {
  const key = accessKey(c)
  if (!key) return fail(c, 'unsplashNotConfigured')
  return send(
    c,
    await listPhotos(key, c.req.query('query') ?? '', Number(c.req.query('page') ?? 1) || 1)
  )
})

app.post('/api/unsplash/download', async (c) => {
  const key = accessKey(c)
  if (!key) return fail(c, 'unsplashNotConfigured')
  const body = await c.req.json().catch(() => ({}))
  return send(
    c,
    await triggerDownload(key, (body as { downloadLocation?: unknown }).downloadLocation)
  )
})

export default app
