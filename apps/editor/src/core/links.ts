/**
 * Link targets the editor will store, render or open. An allowlist, not a blocklist: a page file synced
 * from another device (or imported) can carry any href, and a `javascript:` one opened inside the web view
 * would run with access to the native bridge.
 */
const SAFE_SCHEMES = ['http', 'https', 'mailto', 'tel', 'hikki']

/** Browsers ignore whitespace and control characters inside a scheme ("java\tscript:"). */
// oxlint-disable-next-line no-control-regex
const stripControls = (value: string) => value.replace(/[\u0000-\u0020\u007f-\u009f]/gu, '')

/** True for http(s), mailto, tel, hikki (page links) and same-document/relative references. */
export function isSafeHref(raw: string | null | undefined): boolean {
  if (!raw) return false
  const href = stripControls(raw)
  const scheme = /^([a-z][a-z0-9+.-]*):/iu.exec(href)?.[1]?.toLowerCase()
  if (scheme === undefined)
    return !href.includes(':') || href.startsWith('/') || href.startsWith('#')
  return SAFE_SCHEMES.includes(scheme)
}

/** What the user typed into the link field, as an href: bare domains become https; unsafe schemes → null. */
export function normalizeHref(raw: string): string | null {
  const value = stripControls(raw)
  if (!value) return null
  const href =
    /^[a-z][a-z0-9+.-]*:/iu.test(value) || /^[/#]/u.test(value) ? value : `https://${value}`
  return isSafeHref(href) ? href : null
}
