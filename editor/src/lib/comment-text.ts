/**
 * A comment's words with page mentions in them. Stored as plain text where a mention is a Markdown link,
 * `[@Title](hikki://page/<id>)`, so the comments file stays readable and the native side can show "@Title"; the
 * editor draws each one as a chip with the page's current icon and title.
 */

export type CommentPart = { text: string } | { pageId: string; label: string }

/** A mention while the comment is typed: the "@Title" in the field and the page it stands for. */
export type DraftMention = { label: string; pageId: string }

const MENTION = /\[@([^\]\n]*)\]\(hikki:\/\/page\/([\w-]+)\)/g

/** The stored text as runs of text and mentions, in order. */
export function commentParts(body: string): CommentPart[] {
  const parts: CommentPart[] = []
  let last = 0
  for (const match of body.matchAll(MENTION)) {
    const index = match.index ?? 0
    if (index > last) parts.push({ text: body.slice(last, index) })
    parts.push({ label: match[1], pageId: match[2] })
    last = index + match[0].length
  }
  if (last < body.length) parts.push({ text: body.slice(last) })
  return parts
}

/** What goes into the field to edit a stored comment: mentions as "@Title", with the pages they stand for. */
export function draftFromBody(body: string): { text: string; mentions: DraftMention[] } {
  const mentions: DraftMention[] = []
  const text = commentParts(body)
    .map((part) => {
      if ('text' in part) return part.text
      mentions.push({ label: part.label, pageId: part.pageId })
      return `@${part.label}`
    })
    .join('')
  return { text, mentions }
}

/** The field's text to store: each "@Title" still in it (left to right) becomes its mention; one deleted or
 * edited away stays plain text. */
export function bodyFromDraft(text: string, mentions: DraftMention[]): string {
  let out = ''
  let rest = text
  const pending = [...mentions]
  while (pending.length > 0) {
    let first: { at: number; mention: DraftMention; index: number } | null = null
    pending.forEach((mention, index) => {
      const at = rest.indexOf(`@${mention.label}`)
      if (at >= 0 && (first === null || at < first.at)) first = { at, mention, index }
    })
    if (first === null) break
    const { at, mention, index } = first as { at: number; mention: DraftMention; index: number }
    const label = mention.label.replace(/[\]\n]/g, ' ')
    out += rest.slice(0, at) + `[@${label}](hikki://page/${mention.pageId})`
    rest = rest.slice(at + mention.label.length + 1)
    pending.splice(index, 1)
  }
  return out + rest
}

/** The "@query" being typed right before the caret (from an "@" at the start or after a space), or null. */
export function mentionQuery(text: string, caret: number): { start: number; query: string } | null {
  const before = text.slice(0, caret)
  const at = before.lastIndexOf('@')
  if (at < 0) return null
  if (at > 0 && !/\s/.test(before[at - 1])) return null
  const query = before.slice(at + 1)
  if (/[\n]/.test(query) || query.length > 40) return null
  return { start: at, query }
}
