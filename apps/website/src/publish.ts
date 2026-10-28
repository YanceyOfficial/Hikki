/**
 * A published page (the app's page ⋯ → Publish…): one `PublishedPage` record in the app's CloudKit public database,
 * holding the page as HTML and its attachments. Published for people with the link, both are sealed with AES-GCM
 * under a key that travels only in the link's fragment (`/p/<record>#<key>`) — a browser never sends the fragment,
 * so neither iCloud nor this site can read the page; the reader opens it in the browser. Listed in Hikki Shared
 * (`/shared`, `/shared/<record>`), they are stored as they are, with the fields the list asks for: `listed` = 1,
 * `title`, `icon`, `excerpt`, `tags`, `author`, `terms` and `publishedAt`. Records are read through CloudKit's web service with
 * the site's API token (anonymous, read-only); the HTML is reduced to a safe allowlist before it is shown.
 */

import tokens from '../../../design/tokens.json'

export const CLOUDKIT_CONTAINER = 'iCloud.app.yancey.hikki'
export const RECORD_TYPE = 'PublishedPage'

export type PublishedPayload = {
  format: number
  title: string
  icon?: string | null
  html: string
  assets: { name: string; type: string }[]
  publishedAt: string
  /** Absent in pages published before covers, tags and authors went along. */
  cover?: PublishedCover | null
  tags?: string[] | null
  author?: string | null
}

/** A published page's cover (`PublishedCover` in HikkiCore): a built-in gradient, or a picture with its position. */
export type PublishedCover = { gradient?: string | null; image?: string | null; position?: number }

/** The built-in covers' colours (design/tokens.json's `cover`, as the app draws them: 135°, two stops). */
const GRADIENTS = Object.fromEntries(
  Object.entries(tokens.cover).filter((entry): entry is [string, string[]] =>
    Array.isArray(entry[1])
  )
)

/**
 * How the reader draws a cover: a gradient as CSS, or a picture — an https address (Unsplash's, hotlinked as its
 * rules ask) or one of the page's own attachments (`assets/<name>`, through `assetURL`) — with its vertical position;
 * null for anything else.
 */
/** The one host a cover may be drawn from (Unsplash's pictures); the app sends no other — `PublishedCover.from`. */
export const COVER_HOST = 'images.unsplash.com'

/**
 * The media types an attachment's blob may carry. A blob is the site's own origin, so a type the browser would run —
 * HTML, SVG, scripts — becomes a plain download instead, whatever the payload says.
 */
const BLOB_TYPES = new Set([
  'image/png',
  'image/jpeg',
  'image/gif',
  'image/webp',
  'image/avif',
  'image/heic',
  'video/mp4',
  'video/quicktime',
  'video/webm',
  'audio/mpeg',
  'audio/mp4',
  'audio/aac',
  'audio/wav',
  'audio/ogg'
])

export function blobType(type: string | null | undefined): string {
  const plain = (type ?? '').split(';')[0].trim().toLowerCase()
  return BLOB_TYPES.has(plain) ? plain : 'application/octet-stream'
}

export function coverView(
  cover: PublishedCover | null | undefined,
  assetURL: (name: string) => string | null
): { gradient: string } | { image: string; position: number } | null {
  if (!cover) return null
  if (cover.gradient) {
    const stops = GRADIENTS[cover.gradient]
    return stops ? { gradient: `linear-gradient(135deg, ${stops[0]} 0%, ${stops[1]} 100%)` } : null
  }
  const image = cover.image ?? ''
  const position = Math.min(100, Math.max(0, Number(cover.position ?? 50) || 0))
  if (image.startsWith('assets/')) {
    const url = assetURL(image.slice('assets/'.length))
    return url ? { image: url, position } : null
  }
  try {
    // A picture from anywhere would tell its host who reads the page: only Unsplash's, which covers hotlink.
    const url = new URL(image)
    return url.protocol === 'https:' && url.hostname === COVER_HOST
      ? { image: url.href, position }
      : null
  } catch {
    return null
  }
}

/**
 * The preset tags a listed page is filed under — the app's `PublishTags` (HikkiCore), both held to
 * `design/fixtures/publish.json`.
 */
export const PUBLISH_TAGS = [
  { id: 'study', label: 'Study' },
  { id: 'language', label: 'Languages' },
  { id: 'work', label: 'Work' },
  { id: 'tech', label: 'Tech' },
  { id: 'design', label: 'Design' },
  { id: 'writing', label: 'Writing' },
  { id: 'reading', label: 'Reading' },
  { id: 'travel', label: 'Travel' },
  { id: 'food', label: 'Food' },
  { id: 'health', label: 'Health' },
  { id: 'life', label: 'Life' },
  { id: 'templates', label: 'Templates' }
] as const

export const tagLabel = (id: string) => PUBLISH_TAGS.find((tag) => tag.id === id)?.label ?? id

const MAX_TERMS = 1500
const MAX_QUERY_TERMS = 5
const MAX_WORD_LENGTH = 40

/** Han, kana and Hangul — the scripts written without spaces between words (the app's `PublishSearch.isCJK`). */
function isCJK(char: string): boolean {
  const code = char.codePointAt(0) ?? 0
  return (
    (code >= 0x3040 && code <= 0x30ff) ||
    (code >= 0x31f0 && code <= 0x31ff) ||
    (code >= 0x3400 && code <= 0x4dbf) ||
    (code >= 0x4e00 && code <= 0x9fff) ||
    (code >= 0xf900 && code <= 0xfaff) ||
    (code >= 0xac00 && code <= 0xd7af) ||
    (code >= 0x1100 && code <= 0x11ff) ||
    (code >= 0x3130 && code <= 0x318f) ||
    (code >= 0x20000 && code <= 0x2fa1f)
  )
}

const isWordChar = (char: string) =>
  /[\p{L}\p{N}]/u.test(char) || (/\p{M}/u.test(char) && isCJK(char))

/**
 * The words a listed page is found by, as the app gives them to the record (`PublishSearch.terms`): folded — no case,
 * no Latin accents, full-width as half-width — each run of letters or digits two characters or longer as one term,
 * and in Chinese, Japanese and Korean every character and every pair of neighbours.
 */
export function searchTerms(text: string): string[] {
  const folded = text
    .normalize('NFKD')
    .replaceAll(/[\u0300-\u036f]/gu, '')
    .normalize('NFC')
    .toLowerCase()
  const terms: string[] = []
  const seen = new Set<string>()
  const add = (term: string) => {
    if (terms.length >= MAX_TERMS || seen.has(term)) return
    seen.add(term)
    terms.push(term)
  }
  const flush = (segment: string[], cjk: boolean) => {
    if (cjk) {
      segment.forEach((char, index) => {
        add(char)
        if (index + 1 < segment.length) add(char + segment[index + 1])
      })
    } else if (segment.length >= 2) {
      add(segment.slice(0, MAX_WORD_LENGTH).join(''))
    }
  }
  let segment: string[] = []
  let cjk = false
  for (const char of folded) {
    if (!isWordChar(char)) {
      if (segment.length) flush(segment, cjk)
      segment = []
      continue
    }
    const charCJK = isCJK(char)
    if (segment.length && charCJK !== cjk) {
      flush(segment, cjk)
      segment = []
    }
    cjk = charCJK
    segment.push(char)
  }
  if (segment.length) flush(segment, cjk)
  return terms
}

const singleCJK = (term: string) => [...term].length === 1 && isCJK(term)

/** A query's terms (`PublishSearch.queryTerms`): a character already inside one of the query's pairs is left out. */
export function queryTerms(query: string): string[] {
  const all = searchTerms(query)
  const pairs = all.filter((term) => [...term].length === 2 && isCJK(term))
  return all
    .filter((term) => !singleCJK(term) || !pairs.some((pair) => pair.includes(term)))
    .slice(0, MAX_QUERY_TERMS)
}

/** One listed page in the list. */
export type ListedPage = {
  id: string
  title: string
  icon: string | null
  excerpt: string
  tags: string[]
  author: string | null
  publishedAt: number | null
}

export const PAGE_SIZE = 24

/** The list's query: listed pages, newest first, under a tag and holding every term of the search, a page at a time. */
export function listURL(env: string, token: string): string {
  return lookupURL(env, token).replace('/records/lookup', '/records/query')
}

export function listRequest(options: {
  query?: string
  tag?: string | null
  marker?: string | null
}): RequestInit {
  const filterBy: unknown[] = [
    { fieldName: 'listed', comparator: 'EQUALS', fieldValue: { value: 1, type: 'INT64' } }
  ]
  if (options.tag) {
    filterBy.push({
      fieldName: 'tags',
      comparator: 'LIST_CONTAINS',
      fieldValue: { value: options.tag, type: 'STRING' }
    })
  }
  for (const term of queryTerms(options.query ?? '')) {
    filterBy.push({
      fieldName: 'terms',
      comparator: 'LIST_CONTAINS',
      fieldValue: { value: term, type: 'STRING' }
    })
  }
  const body: Record<string, unknown> = {
    query: {
      recordType: RECORD_TYPE,
      filterBy,
      sortBy: [{ fieldName: 'publishedAt', ascending: false }]
    },
    resultsLimit: PAGE_SIZE,
    desiredKeys: ['title', 'icon', 'excerpt', 'tags', 'author', 'publishedAt']
  }
  if (options.marker) body.continuationMarker = options.marker
  // A string body and no headers: a simple request, as CloudKit's CORS needs (see `lookupRequest`).
  return { method: 'POST', body: JSON.stringify(body) }
}

type Field = { value?: unknown } | undefined

/** The list's answer: the pages it read (a record missing its title is left out) and where the next page starts. */
export function parseList(body: unknown): { pages: ListedPage[]; marker: string | null } | null {
  if (!body || typeof body !== 'object') return null
  const answer = body as {
    records?: unknown[]
    continuationMarker?: string
    serverErrorCode?: string
  }
  if (answer.serverErrorCode || !Array.isArray(answer.records)) return null
  const pages: ListedPage[] = []
  for (const item of answer.records) {
    const record = item as { recordName?: string; fields?: Record<string, Field> }
    const title = record.fields?.title?.value
    if (!record.recordName || typeof title !== 'string') continue
    const icon = record.fields?.icon?.value
    const excerpt = record.fields?.excerpt?.value
    const tags = record.fields?.tags?.value
    const publishedAt = record.fields?.publishedAt?.value
    const author = record.fields?.author?.value
    pages.push({
      id: record.recordName,
      title,
      icon: typeof icon === 'string' ? icon : null,
      excerpt: typeof excerpt === 'string' ? excerpt : '',
      tags: Array.isArray(tags) ? tags.filter((tag): tag is string => typeof tag === 'string') : [],
      author: typeof author === 'string' && author.trim() ? author.trim() : null,
      publishedAt: typeof publishedAt === 'number' ? publishedAt : null
    })
  }
  return { pages, marker: answer.continuationMarker ?? null }
}

/** Whether a record read by name is listed — stored readable, opened without a key. */
export function isListed(record: unknown): boolean {
  const fields = (record as { fields?: Record<string, Field> } | null)?.fields
  return fields?.listed?.value === 1
}

/**
 * "Save to Hikki": the app's own link to the record (`hikki://shared/<record>`, the key as the fragment for a page
 * only for people with the link) — the app fetches the page and imports it as a new page.
 */
export function saveToHikkiURL(recordName: string, key?: string | null): string {
  return `hikki://shared/${encodeURIComponent(recordName)}${key ? `#${key}` : ''}`
}

/** Where the record is read: the container's public database, `development` while the schema isn't deployed. */
export function lookupURL(env: string, token: string): string {
  const environment = env === 'development' ? 'development' : 'production'
  return `https://api.apple-cloudkit.com/database/1/${CLOUDKIT_CONTAINER}/${environment}/public/records/lookup?ckAPIToken=${encodeURIComponent(token)}`
}

/**
 * The lookup's request: a POST with the record's name and no headers of its own. CloudKit's CORS preflight answers
 * no `Access-Control-Allow-Headers`, so a `content-type: application/json` header made the browser refuse the request
 * before it was sent; a string body goes as `text/plain`, a simple request with no preflight, and CloudKit reads the
 * JSON all the same.
 */
export function lookupRequest(recordName: string): RequestInit {
  return { method: 'POST', body: JSON.stringify({ records: [{ recordName }] }) }
}

/** The key from the link's fragment (`#<base64url>`): 32 bytes, or null when the link has none or a broken one. */
export function keyFromFragment(hash: string): Uint8Array | null {
  const text = hash.replace(/^#/u, '').trim()
  if (!text) return null
  const base64 =
    text.replaceAll('-', '+').replaceAll('_', '/') + '='.repeat((4 - (text.length % 4)) % 4)
  try {
    const bytes = Uint8Array.from(atob(base64), (c) => c.codePointAt(0) ?? 0)
    return bytes.length === 32 ? bytes : null
  } catch {
    return null
  }
}

/** Opens what the app sealed: AES-GCM, the 12-byte nonce first, then the ciphertext with its tag. */
export async function decrypt(sealed: ArrayBuffer, key: Uint8Array): Promise<ArrayBuffer> {
  if (sealed.byteLength < 12 + 16) throw new Error('too short')
  // A copy: WebCrypto wants a view over a plain ArrayBuffer.
  const raw = new Uint8Array(key)
  const cryptoKey = await crypto.subtle.importKey('raw', raw, 'AES-GCM', false, ['decrypt'])
  return crypto.subtle.decrypt(
    { name: 'AES-GCM', iv: sealed.slice(0, 12) },
    cryptoKey,
    sealed.slice(12)
  )
}

export type RecordFiles = { payloadURL: string; fileURLs: string[] }

/** CloudKit writes `${f}` into a download address where the file's name goes. */
const named = (url: string, name: string) => url.replace('${f}', encodeURIComponent(name))

/** The record's files by name — the sealed payload and the sealed attachments in the payload's order. */
export function recordFiles(record: unknown): RecordFiles | 'notFound' | null {
  if (!record || typeof record !== 'object') return null
  const r = record as { serverErrorCode?: string; fields?: Record<string, { value?: unknown }> }
  if (r.serverErrorCode === 'NOT_FOUND') return 'notFound'
  if (r.serverErrorCode) return null
  const payload = r.fields?.payloadFile?.value as { downloadURL?: string } | undefined
  if (!payload?.downloadURL) return null
  const files = (r.fields?.files?.value as { downloadURL?: string }[] | undefined) ?? []
  return {
    payloadURL: named(payload.downloadURL, 'payload'),
    fileURLs: files.map((f, i) => named(f.downloadURL ?? '', `file-${i}`)).filter(Boolean)
  }
}

const ALLOWED = new Set([
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'p',
  'br',
  'hr',
  'ul',
  'ol',
  'li',
  'blockquote',
  'pre',
  'code',
  'strong',
  'b',
  'em',
  'i',
  'u',
  's',
  'del',
  'sub',
  'sup',
  'mark',
  'span',
  'div',
  'a',
  'img',
  'table',
  'thead',
  'tbody',
  'tr',
  'th',
  'td',
  'details',
  'summary',
  'figure',
  'figcaption',
  'time',
  'video',
  'audio',
  'ruby',
  'rb',
  'rt',
  'rp',
  'input',
  'label'
])
const ALLOWED_ATTRIBUTES = new Set([
  'alt',
  'title',
  'colspan',
  'rowspan',
  'datetime',
  'open',
  'class',
  'type',
  'checked',
  'disabled',
  'controls',
  'start'
])

/** Elements dropped with everything in them: never part of what the page says. */
const DROPPED = [
  'head',
  'title',
  'style',
  'script',
  'template',
  'noscript',
  'meta',
  'link',
  'object',
  'embed',
  'svg',
  'math',
  'colgroup'
]

/** A link target the page may carry: web addresses and mail. */
function safeHref(href: string): string | null {
  const value = href.trim()
  return /^(https?:|mailto:)/iu.test(value) ? value : null
}

/**
 * The page's HTML reduced to what a reader needs: an allowlist of elements and attributes, links only to the web,
 * pictures and media only from the page's own attachments (`assetURL` maps `assets/<name>` to a blob the reader
 * made), scripts, styles, handlers and frames gone — a frame becomes a link to what it embedded.
 */
export function sanitize(
  html: string,
  assetURL: (name: string) => string | null,
  title?: string
): string {
  // The export is a whole document: its head (title, style) never reaches the body — read into one, it was text.
  const doc = new DOMParser().parseFromString(html, 'text/html')
  for (const element of Array.from(doc.body.querySelectorAll(DROPPED.join(',')))) element.remove()
  // The export opens with the title as a heading; the reader shows the title itself.
  const first = doc.body.firstElementChild
  if (title && first?.tagName === 'H1' && first.textContent?.trim() === title.trim()) first.remove()
  const walk = (node: Element) => {
    for (const child of Array.from(node.children)) {
      const tag = child.tagName.toLowerCase()
      if (tag === 'iframe') {
        const src = safeHref(child.getAttribute('src') ?? '')
        const replacement = doc.createElement(src ? 'a' : 'span')
        if (src) {
          replacement.setAttribute('href', src)
          replacement.setAttribute('rel', 'noopener noreferrer')
          replacement.setAttribute('target', '_blank')
        }
        replacement.textContent = src ?? ''
        child.replaceWith(replacement)
        continue
      }
      if (!ALLOWED.has(tag) || (tag === 'input' && child.getAttribute('type') !== 'checkbox')) {
        // Unknown wrappers keep their text (a block type this reader doesn't know still reads).
        const text = doc.createTextNode(child.textContent ?? '')
        child.replaceWith(text)
        continue
      }
      for (const attribute of Array.from(child.attributes)) {
        const name = attribute.name.toLowerCase()
        if (name === 'href' && tag === 'a') {
          const href = safeHref(attribute.value)
          if (href) {
            child.setAttribute('href', href)
            child.setAttribute('rel', 'noopener noreferrer')
            child.setAttribute('target', '_blank')
          } else {
            child.removeAttribute(attribute.name)
            // A link into the author's own Hikki (another page, a block) can't open here: it reads as one, marked.
            if (/^hikki:/iu.test(attribute.value.trim())) {
              child.setAttribute('data-link', 'private')
              child.setAttribute('title', PRIVATE_LINK_TITLE)
            }
          }
          continue
        }
        if (name === 'src' && (tag === 'img' || tag === 'video' || tag === 'audio')) {
          const match = /^assets\/([\w.-]+)$/u.exec(attribute.value.trim())
          const url = match ? assetURL(match[1]) : null
          if (url) child.setAttribute('src', url)
          else child.removeAttribute(attribute.name)
          continue
        }
        if (ALLOWED_ATTRIBUTES.has(name) || name.startsWith('data-')) continue
        child.removeAttribute(attribute.name)
      }
      if ((tag === 'img' || tag === 'video' || tag === 'audio') && !child.getAttribute('src')) {
        child.remove()
        continue
      }
      if (tag === 'input') child.setAttribute('disabled', '')
      if (child.getAttribute('data-type') === 'mention')
        child.setAttribute('title', PRIVATE_LINK_TITLE)
      walk(child)
    }
  }
  walk(doc.body)
  return doc.body.innerHTML
}

/** What a link into the author's own Hikki says when pointed at. */
export const PRIVATE_LINK_TITLE = "A page in the author's own Hikki. It opens only in their app."

/**
 * Whether to say that some links may not open: the page links somewhere — another page of the author's Hikki (a link
 * or a mention), or the web, where a page may need a sign-in or not be public.
 */
export const hasLinks = (html: string) => /<a[\s>]|data-type="mention"/u.test(html)

type KaTeX = {
  renderToString: (latex: string, options: Record<string, unknown>) => string
}

/** Whether the page holds formulas (KaTeX is loaded only then). */
export const hasMath = (html: string) => html.includes('data-latex')

/**
 * The page's formulas drawn. The export keeps a formula as its source only — `<span data-type="inline-math"
 * data-latex="…">` or `<div data-type="block-math" …>`, empty, as the editor draws it with KaTeX — so the reader draws
 * it the same way, after `sanitize` (KaTeX's own markup, with no links or HTML of its own: `trust` stays off).
 */
export function renderMath(html: string, katex: KaTeX): string {
  const doc = new DOMParser().parseFromString(`<body>${html}</body>`, 'text/html')
  for (const node of Array.from(doc.body.querySelectorAll('[data-latex]'))) {
    const type = node.getAttribute('data-type')
    if (type !== 'inline-math' && type !== 'block-math') continue
    node.innerHTML = katex.renderToString(node.getAttribute('data-latex') ?? '', {
      displayMode: type === 'block-math',
      throwOnError: false,
      strict: 'ignore',
      trust: false
    })
  }
  return doc.body.innerHTML
}

/** A shared page's tab: its title, then the place. */
export const sharedTitle = (title: string) => `${title.trim() || 'Untitled'} · Hikki Shared`

/** Names the browser's tab after the page, once it has been read. */
export function nameTab(title: string) {
  document.title = sharedTitle(title)
}

/** One heading in a page's contents. */
export type OutlineItem = { id: string; level: number; text: string }

/**
 * The page's contents: every h1–h3 of the sanitized HTML given an id of its own (`toc-<n>`, made here — never one
 * the page brought) and listed with its level and words; headings with no words are left out.
 */
export function outline(html: string): { html: string; items: OutlineItem[] } {
  const doc = new DOMParser().parseFromString(`<body>${html}</body>`, 'text/html')
  const items: OutlineItem[] = []
  for (const heading of Array.from(doc.body.querySelectorAll('h1, h2, h3'))) {
    const text = (heading.textContent ?? '').replaceAll(/\s+/gu, ' ').trim()
    if (!text) continue
    const id = `toc-${items.length + 1}`
    heading.setAttribute('id', id)
    items.push({ id, level: Number(heading.tagName.slice(1)), text })
  }
  return { html: items.length ? doc.body.innerHTML : html, items }
}
