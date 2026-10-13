import { Hono, type Context } from 'hono'
import { env } from 'hono/adapter'
import { cors } from 'hono/cors'

import { listPhotos, triggerDownload, type ProxyResult } from './unsplash.js'

/**
 * Hikki's backend-for-frontend: keeps third-party API keys server-side (Unsplash requires its
 * Access Key to stay confidential). Deployed on Vercel; set UNSPLASH_ACCESS_KEY in the project env.
 */
const app = new Hono()

// The editor runs in a WKWebView (origin hikki-editor://app) and in a browser during development;
// no cookies or credentials are involved, so any origin may call these read-only endpoints.
app.use(
  '/api/*',
  cors({ origin: '*', allowMethods: ['GET', 'POST'], exposeHeaders: ['X-Ratelimit-Remaining'] })
)

app.get('/', (c) => c.text('hikki-bff'))

// Embed shim: YouTube's player refuses to play (error 153) without an HTTP Referer, and the editor's page
// — on the app's own scheme — sends none. This page, on https, holds the player, so the player sees a
// referrer. The id is checked, so it is the only thing that varies in the markup.
const YOUTUBE_ID = /^[\w-]{6,20}$/u

app.get('/embed/youtube/:id', (c) => {
  const id = c.req.param('id')
  if (!YOUTUBE_ID.test(id)) return c.text('bad id', 400)
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

function send(result: ProxyResult): Response {
  const headers = new Headers(result.headers)
  if (result.body === null) return new Response(null, { status: result.status, headers })
  headers.set('Content-Type', 'application/json')
  headers.set('Cache-Control', result.status === 200 ? 'public, max-age=300' : 'no-store')
  return new Response(JSON.stringify(result.body), { status: result.status, headers })
}

app.get('/api/unsplash/photos', async (c) => {
  const key = accessKey(c)
  if (!key) return c.json({ error: 'unsplash_not_configured' }, 503)
  return send(
    await listPhotos(key, c.req.query('query') ?? '', Number(c.req.query('page') ?? 1) || 1)
  )
})

app.post('/api/unsplash/download', async (c) => {
  const key = accessKey(c)
  if (!key) return c.json({ error: 'unsplash_not_configured' }, 503)
  const body = await c.req.json().catch(() => ({}))
  return send(await triggerDownload(key, (body as { downloadLocation?: unknown }).downloadLocation))
})

export default app
