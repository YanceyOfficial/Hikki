import { normalizeHref } from '../core/links'

/** What an embed block shows: a third-party page in a frame, or a snippet of HTML in a sandboxed one. */
export type EmbedKind = 'iframe' | 'html'
export type EmbedProvider =
  | 'youtube'
  | 'vimeo'
  | 'figma'
  | 'googleMaps'
  | 'googleDrive'
  | 'gist'
  | 'tweet'
  | 'codepen'
  | 'drawio'
  | 'loom'
  | 'excalidraw'
  | 'miro'
  | 'airtable'
  | 'spotify'
  | 'codesandbox'
  | 'generic'

export type EmbedSource =
  | {
      kind: 'iframe'
      provider: EmbedProvider
      /** What the frame loads (the provider's embed URL). */
      src: string
      /** What the user gave (the page to open outside). */
      original: string
      height: number
    }
  | { kind: 'html'; provider: 'generic'; html: string; height: number }

/** Default frame heights, by what usually lives inside. */
const HEIGHT: Record<EmbedProvider, number> = {
  youtube: 400,
  vimeo: 400,
  figma: 450,
  googleMaps: 400,
  googleDrive: 480,
  gist: 400,
  tweet: 520,
  codepen: 400,
  drawio: 450,
  loom: 400,
  excalidraw: 450,
  miro: 450,
  airtable: 533,
  spotify: 352,
  codesandbox: 500,
  generic: 400
}

/** Spotify's compact player (a track, an episode) is this tall; albums, playlists and shows take `HEIGHT`. */
const SPOTIFY_COMPACT = 152

export const MIN_EMBED_HEIGHT = 120
export const MAX_EMBED_HEIGHT = 1200

const host = (url: URL) => url.hostname.replace(/^www\./u, '').toLowerCase()

/**
 * Turns a link the user pasted into what a frame can show: the providers' own embed URLs where the page
 * itself refuses to be framed (YouTube, Figma, Google Maps / Drive / Docs, Gists, tweets, CodePen, draw.io,
 * Loom, Miro, Airtable, Spotify, CodeSandbox), the link as it is otherwise. Every URL built here is https on
 * the provider's own host, with ids matched to their alphabet, so nothing pasted can steer the frame elsewhere.
 * Only https; null when it is no link at all.
 */
export function embedFromURL(input: string): EmbedSource | null {
  const href = normalizeHref(input.trim())
  if (!href) return null
  let url: URL
  try {
    url = new URL(href)
  } catch {
    return null
  }
  // Only https, and only a real host: "nope" would otherwise become https://nope.
  if (url.protocol !== 'https:' || !url.hostname.includes('.')) return null
  const frame = (provider: EmbedProvider, src: string): EmbedSource => ({
    kind: 'iframe',
    provider,
    src,
    original: url.href,
    height: HEIGHT[provider]
  })
  const h = host(url)
  const path = url.pathname

  // YouTube: watch?v=, youtu.be/, shorts/, live/, embed/.
  if (['youtube.com', 'm.youtube.com', 'youtube-nocookie.com', 'youtu.be'].includes(h)) {
    const id =
      h === 'youtu.be'
        ? path.slice(1).split('/')[0]
        : (url.searchParams.get('v') ?? /^\/(?:shorts|live|embed)\/([\w-]+)/u.exec(path)?.[1])
    if (id && /^[\w-]{6,}$/u.test(id)) {
      const start = url.searchParams.get('t') ?? url.searchParams.get('start')
      const query = start ? `?start=${Number.parseInt(start, 10) || 0}` : ''
      return frame('youtube', `https://www.youtube-nocookie.com/embed/${id}${query}`)
    }
  }
  if (h === 'vimeo.com' || h === 'player.vimeo.com') {
    const id = /(\d{6,})/u.exec(path)?.[1]
    if (id) return frame('vimeo', `https://player.vimeo.com/video/${id}`)
  }
  if (h === 'figma.com' && /^\/(?:file|design|proto|board|slides|deck)\//u.test(path)) {
    return frame(
      'figma',
      `https://www.figma.com/embed?embed_host=hikki&url=${encodeURIComponent(url.href)}`
    )
  }
  if ((h === 'google.com' || h === 'maps.google.com') && path.startsWith('/maps')) {
    if (path.startsWith('/maps/embed') || url.searchParams.get('output') === 'embed')
      return frame('googleMaps', url.href)
    const q =
      url.searchParams.get('q') ??
      /^\/maps\/(?:place|search)\/([^/]+)/u.exec(path)?.[1] ??
      /@(-?\d+\.\d+),(-?\d+\.\d+)/u.exec(path)?.slice(1, 3).join(',')
    if (q) {
      const query = decodeURIComponent(q.replaceAll('+', ' '))
      return frame(
        'googleMaps',
        `https://maps.google.com/maps?q=${encodeURIComponent(query)}&output=embed`
      )
    }
  }
  if (h === 'drive.google.com') {
    const file = /^\/file\/d\/([\w-]+)/u.exec(path)?.[1]
    if (file) return frame('googleDrive', `https://drive.google.com/file/d/${file}/preview`)
    const folder = /^\/drive\/(?:u\/\d+\/)?folders\/([\w-]+)/u.exec(path)?.[1]
    if (folder)
      return frame('googleDrive', `https://drive.google.com/embeddedfolderview?id=${folder}`)
  }
  if (h === 'docs.google.com') {
    const match = /^\/(document|spreadsheets|presentation|forms)\/d\/(?:e\/)?([\w-]+)/u.exec(path)
    if (match) {
      const [, type, id] = match
      const src =
        type === 'forms'
          ? `https://docs.google.com/forms/d/e/${id}/viewform?embedded=true`
          : `https://docs.google.com/${type}/d/${id}/preview`
      return frame('googleDrive', src)
    }
  }
  if (h === 'gist.github.com') {
    const match = /^\/([\w-]+)\/([0-9a-f]+)/u.exec(path)
    if (match) {
      // GitHub serves gists as a script that writes the gist in: a page of our own holds it.
      const [, user, id] = match
      return {
        kind: 'html',
        provider: 'generic',
        html: `<script src="https://gist.github.com/${user}/${id}.js"></script>`,
        height: HEIGHT.gist
      }
    }
  }
  if (['twitter.com', 'mobile.twitter.com', 'x.com'].includes(h)) {
    const id = /\/status(?:es)?\/(\d+)/u.exec(path)?.[1]
    if (id) return frame('tweet', `https://platform.twitter.com/embed/Tweet.html?id=${id}&dnt=true`)
  }
  if (h === 'codepen.io') {
    const match = /^\/([\w-]+)\/(?:pen|full|details)\/([\w-]+)/u.exec(path)
    if (match) {
      const [, user, id] = match
      return frame('codepen', `https://codepen.io/${user}/embed/${id}?default-tab=result`)
    }
  }
  // draw.io: the viewer frames itself; an editor link (app.diagrams.net, draw.io) names its diagram in the
  // fragment (#G<Drive id>, #U<url>, #R<compressed XML>…), which the viewer reads the same way.
  if (h === 'viewer.diagrams.net' || h === 'embed.diagrams.net') return frame('drawio', url.href)
  if (
    ['app.diagrams.net', 'diagrams.net', 'draw.io', 'app.draw.io'].includes(h) &&
    url.hash.length > 2
  ) {
    return frame('drawio', `https://viewer.diagrams.net/?nav=1${url.hash}`)
  }
  if (h === 'loom.com') {
    const id = /^\/(?:share|embed)\/([0-9a-f]{16,})/u.exec(path)?.[1]
    if (id) return frame('loom', `https://www.loom.com/embed/${id}`)
  }
  // Excalidraw keeps the drawing (and its key) in the fragment: the page itself is the embed.
  if (h === 'excalidraw.com' && /^#(?:json|room)=[\w,-]+$/u.test(url.hash)) {
    return frame('excalidraw', `https://excalidraw.com/${url.hash}`)
  }
  if (h === 'miro.com') {
    const id = /^\/app\/(?:board|live-embed)\/([\w-]+=*)/u.exec(path)?.[1]
    if (id)
      return frame('miro', `https://miro.com/app/live-embed/${id}/?embedMode=view_only_without_ui`)
  }
  if (h === 'airtable.com') {
    const view = /^\/(?:embed\/)?((?:app\w+\/)?shr\w+)/u.exec(path)?.[1]
    if (view) return frame('airtable', `https://airtable.com/embed/${view}`)
  }
  if (h === 'open.spotify.com') {
    const match =
      /^\/(?:intl-[\w-]+\/)?(?:embed\/)?(track|album|playlist|episode|show|artist)\/(\w+)/u.exec(
        path
      )
    if (match) {
      const [, type, id] = match
      const source = frame('spotify', `https://open.spotify.com/embed/${type}/${id}`)
      return type === 'track' || type === 'episode'
        ? { ...source, height: SPOTIFY_COMPACT }
        : source
    }
  }
  if (h === 'codesandbox.io') {
    const id = /^\/(?:s|embed|p\/sandbox)\/([\w-]+)/u.exec(path)?.[1]
    if (id) return frame('codesandbox', `https://codesandbox.io/embed/${id}`)
  }
  return frame('generic', url.href)
}

/** Raw HTML to show in a sandboxed frame of its own; null when there is nothing to show. */
export function embedFromHTML(html: string): EmbedSource | null {
  const trimmed = html.trim()
  return trimmed
    ? { kind: 'html', provider: 'generic', html: trimmed, height: HEIGHT.generic }
    : null
}

/** The document a sandboxed HTML embed shows: the snippet, on the page's appearance, no margins. */
export function htmlEmbedDocument(html: string, dark: boolean): string {
  const scheme = dark ? 'dark' : 'light'
  return `<!doctype html><html><head><meta charset="utf-8"><meta name="color-scheme" content="${scheme}"><style>html,body{margin:0;padding:0;color-scheme:${scheme}}img,video,iframe{max-width:100%}</style></head><body>${html}</body></html>`
}

/** The tweet frame follows the page's appearance (the other providers pick it up themselves). */
export function themedEmbedSrc(provider: EmbedProvider, src: string, dark: boolean): string {
  return provider === 'tweet' ? `${src}&theme=${dark ? 'dark' : 'light'}` : src
}

/**
 * What the frame actually loads. YouTube's player refuses to play without an HTTP Referer, and a page on
 * the app's own scheme sends none — so with a BFF the frame loads the BFF's shim page (https), which holds
 * the player; the player then sees the shim as its referrer. Without a BFF (a dev build in a browser) the
 * player loads directly.
 */
export function frameSrc(provider: EmbedProvider, src: string, bff: string | null): string {
  if (provider !== 'youtube' || !bff) return src
  const match = /youtube-nocookie\.com\/embed\/([\w-]+)(\?start=(\d+))?/u.exec(src)
  if (!match) return src
  const [, id, , start] = match
  return `${bff}/embed/youtube/${id}${start ? `?start=${start}` : ''}`
}

/**
 * A frame `src` as stored in a document is untrusted (a synced page, a paste): only an https page may load,
 * never `javascript:`, `data:` or the editor's own scheme, which would run inside this page's origin.
 */
export function safeFrameSrc(src: string | null | undefined): string | null {
  if (!src) return null
  try {
    const url = new URL(src)
    return url.protocol === 'https:' ? url.href : null
  } catch {
    return null
  }
}

/** Whether `href` is a web page the system browser can be handed. */
export function isWebURL(href: string | null | undefined): href is string {
  if (!href) return false
  try {
    const { protocol } = new URL(href)
    return protocol === 'https:' || protocol === 'http:'
  } catch {
    return false
  }
}

/** What a link card shows: what the page says about itself (any of it may be missing). */
export type LinkCard = { title: string | null; description: string | null; icon: string | null }

/** A non-empty trimmed string, or null. */
const text = (v: unknown) => (typeof v === 'string' && v.trim() ? v.trim() : null)

/** A native `linkPreview` reply, checked: strings or nulls only, an icon only when it is a web URL. */
export function linkCardFrom(reply: unknown): LinkCard | null {
  if (!reply || typeof reply !== 'object') return null
  const r = reply as Record<string, unknown>
  const icon = text(r.icon)
  return {
    title: text(r.title),
    description: text(r.description),
    icon: isWebURL(icon) ? icon : null
  }
}

export const clampEmbedHeight = (height: number): number =>
  Math.round(Math.min(MAX_EMBED_HEIGHT, Math.max(MIN_EMBED_HEIGHT, height)))
