import type { Fragment, Node as PMNode, Schema } from '@tiptap/pm/model'
import { DOMParser as PMDOMParser, DOMSerializer } from '@tiptap/pm/model'
import type { EditorState } from '@tiptap/pm/state'

import { isSafeHref } from '../core/links'
import type { AIMediaRef } from '../core/protocol'

/**
 * One piece of the selection AI works on: the selected part of one text block. The model gets `html` (the block's
 * inline formatting kept) under `key` and answers with new inline HTML for that key; `from`/`to` are where it goes.
 */
export type AIUnit = { key: string; from: number; to: number; html: string; text: string }

/** Placeholder a non-text inline node (a mention, a formula) stands for in the text a diff compares. */
export const OBJECT_CHAR = '￼'

/** The selected part of every text block the selection touches (code blocks and empty parts left out). */
export function selectionUnits(state: EditorState): AIUnit[] {
  const { from, to } = state.selection
  const units: AIUnit[] = []
  state.doc.nodesBetween(from, to, (node, pos) => {
    if (!node.isTextblock) return true
    if (node.type.spec.code) return false
    const start = Math.max(from, pos + 1)
    const end = Math.min(to, pos + node.nodeSize - 1)
    if (end <= start) return false
    const text = textBetween(state.doc, start, end).text
    if (!text.trim()) return false
    const id = (node.attrs.id as string | undefined) ?? 'b'
    units.push({
      key: `${id}:${units.length}`,
      from: start,
      to: end,
      html: rangeHTML(state.schema, node, pos, start, end),
      text
    })
    return false
  })
  return units
}

/** A block of the page as Ask AI sees it (to propose changes by id): its kind in a word and its inline HTML. */
export type AIPageBlock = { id: string; type: string; html: string }

/** Every text block of the page with an id, in order (empty ones left out; code as its text). */
export function pageBlocks(state: EditorState): AIPageBlock[] {
  const blocks: AIPageBlock[] = []
  state.doc.descendants((node, pos, parent) => {
    if (!node.isTextblock) return true
    const id = node.attrs.id as string | undefined
    if (!id || !node.textContent.trim()) return false
    const container = parent?.type.name
    const list = container && pos > 0 ? state.doc.resolve(pos).node(-1)?.type.name : undefined
    let type = node.type.name
    if (type === 'heading') type = `heading${node.attrs.level as number}`
    else if (type === 'codeBlock') type = 'code'
    else if (container === 'taskItem') type = 'todo'
    else if (container === 'listItem') type = list === 'orderedList' ? 'numbered' : 'bullet'
    else if (container === 'blockquote') type = 'quote'
    const html = node.type.spec.code
      ? escapeHTML(node.textContent)
      : rangeHTML(state.schema, node, pos, pos + 1, pos + node.nodeSize - 1)
    blocks.push({ id, type, html })
    return false
  })
  return blocks
}

const escapeHTML = (text: string) =>
  text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')

/** Inline HTML for part of a text block (its marks as tags). */
function rangeHTML(
  schema: Schema,
  block: PMNode,
  blockPos: number,
  from: number,
  to: number
): string {
  const content = block.slice(from - blockPos - 1, to - blockPos - 1).content
  const container = document.createElement('div')
  container.append(DOMSerializer.fromSchema(schema).serializeFragment(content))
  return container.innerHTML
}

/**
 * The text of a range in one text block, one entry per code point, with the document position of each: what a diff
 * compares and where its removals land. Non-text inline nodes count as `OBJECT_CHAR`, a hard break as "\n".
 */
export function textBetween(
  doc: PMNode,
  from: number,
  to: number
): { text: string; positions: number[] } {
  let text = ''
  const positions: number[] = []
  doc.nodesBetween(from, to, (node, pos) => {
    if (node.isText) {
      const start = Math.max(from, pos)
      const end = Math.min(to, pos + node.nodeSize)
      let offset = start - pos
      for (const char of (node.text ?? '').slice(start - pos, end - pos)) {
        text += char
        positions.push(pos + offset)
        offset += char.length
      }
      return false
    }
    if (node.isInline && node.isLeaf) {
      if (pos >= from && pos < to) {
        text += node.type.name === 'hardBreak' ? '\n' : OBJECT_CHAR
        positions.push(pos)
      }
      return false
    }
    return true
  })
  return { text, positions }
}

/** The text of inline content (as `textBetween` counts it), for the diff's "after" side. */
export function fragmentText(fragment: Fragment): string {
  let text = ''
  fragment.descendants((node) => {
    if (node.isText) text += node.text
    else if (node.isInline && node.isLeaf)
      text += node.type.name === 'hardBreak' ? '\n' : OBJECT_CHAR
    return true
  })
  return text
}

/** Inline tags a model may answer with; anything else is replaced by its text. */
const ALLOWED = new Set([
  'STRONG',
  'B',
  'EM',
  'I',
  'U',
  'S',
  'DEL',
  'CODE',
  'A',
  'SUB',
  'SUP',
  'BR',
  'SPAN'
])
/** Dropped with their content. */
const DROPPED = new Set([
  'SCRIPT',
  'STYLE',
  'IFRAME',
  'OBJECT',
  'EMBED',
  'TEMPLATE',
  'NOSCRIPT',
  'SVG',
  'MATH'
])

/**
 * A model's HTML made safe and inline: allowed tags kept without attributes (a link keeps a safe `href`), block tags
 * and unknown ones unwrapped, scripts and the like dropped. Parsed by the browser into an inert document (nothing
 * runs), never inserted as HTML.
 */
export function sanitizeInlineHTML(html: string): HTMLElement {
  const parsed = new DOMParser().parseFromString(`<body>${html}</body>`, 'text/html')
  const out = document.createElement('div')
  copyAllowed(parsed.body, out)
  return out
}

/** `source`'s children into `target`, keeping only allowed tags (see `sanitizeInlineHTML`). */
function copyAllowed(source: Node, target: Element): void {
  for (const child of source.childNodes) {
    if (child.nodeType === Node.TEXT_NODE) {
      target.append(document.createTextNode(child.textContent ?? ''))
    } else if (child instanceof Element) {
      const tag = child.tagName
      if (DROPPED.has(tag)) continue
      if (!ALLOWED.has(tag)) {
        copyAllowed(child, target)
        continue
      }
      const clean = document.createElement(tag.toLowerCase())
      if (tag === 'A') {
        const href = child.getAttribute('href')
        if (!href || !isSafeHref(href)) {
          copyAllowed(child, target)
          continue
        }
        clean.setAttribute('href', href)
      }
      copyAllowed(child, clean)
      target.append(clean)
    }
  }
}

/** A model's inline HTML as content for a paragraph of this schema (whatever doesn't fit is dropped), or null. */
export function parseInline(schema: Schema, html: string): Fragment | null {
  try {
    const paragraph = schema.nodes.paragraph
    if (!paragraph) return null
    return PMDOMParser.fromSchema(schema).parse(sanitizeInlineHTML(html), {
      topNode: paragraph.create()
    }).content
  } catch {
    return null
  }
}

/** Longest reply read (characters): a runaway answer isn't parsed. */
const MAX_REPLY = 200_000

/** The JSON object in a model's reply — fenced in ```json, or with text around it — or null. */
function replyObject(reply: string): Record<string, unknown> | null {
  if (reply.length > MAX_REPLY) return null
  const start = reply.indexOf('{')
  const end = reply.lastIndexOf('}')
  if (start < 0 || end <= start) return null
  try {
    const json: unknown = JSON.parse(reply.slice(start, end + 1))
    return json && typeof json === 'object' && !Array.isArray(json)
      ? (json as Record<string, unknown>)
      : null
  } catch {
    return null
  }
}

/** Most notes shown, and the longest one kept (characters). */
const MAX_NOTES = 10
const MAX_NOTE_TEXT = 4000

/**
 * What an edit's reply says to the user rather than to the page (`"notes": ["…"]`, Markdown each): answers, verdicts
 * of a check, explanations. Strings only, blank ones dropped, capped; none when absent or unreadable.
 */
export function parseEditNotes(reply: string): string[] {
  const notes = replyObject(reply)?.notes
  if (!Array.isArray(notes)) return []
  return notes
    .filter((note): note is string => typeof note === 'string' && note.trim() !== '')
    .map((note) => note.trim().slice(0, MAX_NOTE_TEXT))
    .slice(0, MAX_NOTES)
}

/**
 * Whether the reply hands the request to the chat (`{"handoff": {"reason": "…"}}`, the whole reply): the model judged
 * it more than an edit of the selection or a short answer. The reason is for logs only and isn't kept.
 */
export function isHandoff(reply: string): boolean {
  const json = replyObject(reply)
  if (!json || !('handoff' in json) || 'blocks' in json) return false
  const handoff = json.handoff
  return handoff === true || (!!handoff && typeof handoff === 'object' && !Array.isArray(handoff))
}

/**
 * The model's answer to an edit: `{"blocks": [{"id": …, "html": …}]}`, read tolerantly — fenced in ```json, with
 * text around it — and checked: only known keys, strings only. Null when there's nothing usable.
 */
export function parseEditReply(reply: string, keys: string[]): Map<string, string> | null {
  const blocks = replyObject(reply)?.blocks
  if (!Array.isArray(blocks)) return null
  const known = new Set(keys)
  const out = new Map<string, string>()
  for (const block of blocks) {
    const id = (block as { id?: unknown } | null)?.id
    const html = (block as { html?: unknown } | null)?.html
    if (typeof id === 'string' && typeof html === 'string' && known.has(id) && !out.has(id))
      out.set(id, html)
  }
  return out.size > 0 ? out : null
}

/** The kinds of block a model may add after the selection (`"added"`); anything else reads as a paragraph. */
export const ADDED_TYPES = [
  'paragraph',
  'heading1',
  'heading2',
  'heading3',
  'bullet',
  'numbered',
  'quote'
] as const
export type AddedType = (typeof ADDED_TYPES)[number]

/** A block the model adds after the selection: its kind in a word and its inline HTML (not yet sanitized). */
export type AIAddedBlock = { type: AddedType; html: string }

/** Most added blocks read; the rest of a runaway reply is dropped. */
const MAX_ADDED = 20

/**
 * The new blocks an edit's reply puts after the selection (`"added": [{"type": …, "html": …}]`, in reading order),
 * read tolerantly: unknown keys dropped, an unknown or missing type is a paragraph, blank ones left out, capped. None
 * when absent or unreadable. The HTML is sanitized later, as the blocks' is (`parseInline`).
 */
export function parseEditAdded(reply: string): AIAddedBlock[] {
  const added = replyObject(reply)?.added
  if (!Array.isArray(added)) return []
  const out: AIAddedBlock[] = []
  for (const block of added) {
    if (out.length >= MAX_ADDED) break
    if (!block || typeof block !== 'object' || Array.isArray(block)) continue
    const html = (block as { html?: unknown }).html
    if (typeof html !== 'string' || html.trim() === '') continue
    const type = (block as { type?: unknown }).type
    out.push({
      type: (ADDED_TYPES as readonly string[]).includes(type as string)
        ? (type as AddedType)
        : 'paragraph',
      html
    })
  }
  return out
}

const ASSET = /^hikki-editor:\/\/assets\/[^/\\?#]+$/u

/**
 * The file a block holds that AI can read, or null: a picture stored in the workspace (the Image block), or a PDF
 * attachment. Pictures on the web, video and audio are left out — nothing reads them on the device.
 */
export function mediaRef(node: PMNode): AIMediaRef | null {
  const src = typeof node.attrs.src === 'string' ? node.attrs.src.trim() : ''
  if (!ASSET.test(src)) return null
  const name = typeof node.attrs.name === 'string' ? node.attrs.name : null
  if (node.type.name === 'image')
    return { url: src, kind: 'image', name: name ?? (node.attrs.alt as string | null) ?? null }
  if (node.type.name === 'fileAttachment' && /\.pdf$/iu.test(name ?? src))
    return { url: src, kind: 'pdf', name }
  return null
}
