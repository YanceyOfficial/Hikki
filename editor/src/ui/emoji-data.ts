/**
 * Emoji catalog from the bundled emojibase data (./emojibase/<locale>/{data,messages}.json),
 * grouped by category. Pure helpers so grouping/search are unit-tested.
 */
export type RawEmoji = { emoji: string; hexcode: string; label: string; tags?: string[]; group?: number; order?: number; version?: number }
export type RawMessages = { groups: { key: string; message: string; order: number }[] }

export type EmojiEntry = { emoji: string; hexcode: string; label: string; keywords: string }
export type EmojiCategory = { key: string; label: string; emojis: EmojiEntry[] }

/** Newer emoji may render as blank boxes on current system fonts. */
export const MAX_EMOJI_VERSION = 16

export function buildCategories(
  data: RawEmoji[],
  messages: RawMessages,
  extraKeywords: Map<string, string> = new Map(),
  maxVersion = MAX_EMOJI_VERSION,
): EmojiCategory[] {
  const groups = [...messages.groups].filter((g) => g.key !== 'component').sort((a, b) => a.order - b.order)
  const byGroup = new Map<number, RawEmoji[]>()
  for (const e of data) {
    if (e.group === undefined || (e.version ?? 0) > maxVersion) continue
    const list = byGroup.get(e.group) ?? []
    list.push(e)
    byGroup.set(e.group, list)
  }
  return groups
    .map((g) => ({
      key: g.key,
      label: g.message.charAt(0).toUpperCase() + g.message.slice(1),
      emojis: (byGroup.get(g.order) ?? [])
        .sort((a, b) => (a.order ?? 0) - (b.order ?? 0))
        .map((e) => ({
          emoji: e.emoji,
          hexcode: e.hexcode,
          label: e.label,
          keywords: [e.label, ...(e.tags ?? []), extraKeywords.get(e.hexcode) ?? ''].join(' ').toLowerCase(),
        })),
    }))
    .filter((c) => c.emojis.length > 0)
}

/** Label-prefix matches first, then label/keyword substring matches; catalog order within each. */
export function searchEmoji(categories: EmojiCategory[], query: string, limit = 240): EmojiEntry[] {
  const q = query.trim().toLowerCase()
  if (!q) return []
  const prefix: EmojiEntry[] = []
  const rest: EmojiEntry[] = []
  for (const c of categories) {
    for (const e of c.emojis) {
      if (e.label.toLowerCase().startsWith(q)) prefix.push(e)
      else if (e.keywords.includes(q)) rest.push(e)
    }
  }
  return [...prefix, ...rest].slice(0, limit)
}

// MARK: loading

const cache = new Map<string, Promise<EmojiCategory[]>>()

/** Categories labelled in `locale`; search also matches English keywords. Cached per locale. */
export function loadEmojiCategories(locale: 'en' | 'zh', baseURL = new URL('./emojibase/', document.baseURI).href): Promise<EmojiCategory[]> {
  let pending = cache.get(locale)
  if (!pending) {
    const get = (path: string) => fetch(new URL(path, baseURL)).then((r) => {
      if (!r.ok) throw new Error(`emoji data ${path}: HTTP ${r.status}`)
      return r.json()
    })
    pending = Promise.all([get(`${locale}/data.json`), get(`${locale}/messages.json`), locale === 'en' ? null : get('en/data.json')])
      .then(([data, messages, english]: [RawEmoji[], RawMessages, RawEmoji[] | null]) => {
        const extra = new Map((english ?? []).map((e) => [e.hexcode, [e.label, ...(e.tags ?? [])].join(' ')]))
        return buildCategories(data, messages, extra)
      })
    pending.catch(() => cache.delete(locale)) // retry next time
    cache.set(locale, pending)
  }
  return pending
}

// MARK: recents (per-device convenience; storage may be unavailable)

const RECENT_KEY = 'hikki.emoji.recent'
const RECENT_MAX = 27

export function recentEmoji(): string[] {
  try {
    const value = JSON.parse(localStorage.getItem(RECENT_KEY) ?? '[]')
    return Array.isArray(value) ? value.filter((x): x is string => typeof x === 'string').slice(0, RECENT_MAX) : []
  } catch {
    return []
  }
}

export function rememberEmoji(emoji: string): void {
  try {
    localStorage.setItem(RECENT_KEY, JSON.stringify([emoji, ...recentEmoji().filter((e) => e !== emoji)].slice(0, RECENT_MAX)))
  } catch {
    // Private mode / blocked storage: recents are optional.
  }
}
