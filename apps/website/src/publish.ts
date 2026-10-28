/**
 * A published page (the app's page ⋯ → Publish Link): one `PublishedPage` record in the app's CloudKit public
 * database, holding the page as HTML and its attachments, each sealed with AES-GCM under a key that travels only in
 * the link's fragment (`/p/<record>#<key>`) — a browser never sends the fragment, so neither iCloud nor this site
 * can read the page; the reader opens it in the browser. The record is read through CloudKit's web service with
 * the site's API token (anonymous, read-only); the HTML is reduced to a safe allowlist before it is shown.
 */

export const CLOUDKIT_CONTAINER = 'iCloud.app.yancey.hikki'
export const RECORD_TYPE = 'PublishedPage'

export type PublishedPayload = {
  format: number
  title: string
  icon?: string | null
  html: string
  assets: { name: string; type: string }[]
  publishedAt: string
}

/** Where the record is read: the container's public database, `development` while the schema isn't deployed. */
export function lookupURL(env: string, token: string): string {
  const environment = env === 'development' ? 'development' : 'production'
  return `https://api.apple-cloudkit.com/database/1/${CLOUDKIT_CONTAINER}/${environment}/public/records/lookup?ckAPIToken=${encodeURIComponent(token)}`
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
export function sanitize(html: string, assetURL: (name: string) => string | null): string {
  const doc = new DOMParser().parseFromString(`<body>${html}</body>`, 'text/html')
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
      walk(child)
    }
  }
  walk(doc.body)
  return doc.body.innerHTML
}
