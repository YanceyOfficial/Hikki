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
