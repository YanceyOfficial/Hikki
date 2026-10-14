import type { Fragment, Node as PMNode, Schema } from '@tiptap/pm/model'
import { DOMParser as PMDOMParser, DOMSerializer } from '@tiptap/pm/model'
import type { EditorState } from '@tiptap/pm/state'

import { isSafeHref } from '../core/links'

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
function copyAllowed(source: Node, target: Node): void {
  for (const child of source.childNodes) {
    if (child.nodeType === Node.TEXT_NODE) {
      target.appendChild(document.createTextNode(child.textContent ?? ''))
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
      target.appendChild(clean)
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

/**
 * The model's answer to an edit: `{"blocks": [{"id": …, "html": …}]}`, read tolerantly — fenced in ```json, with
 * text around it — and checked: only known keys, strings only. Null when there's nothing usable.
 */
export function parseEditReply(reply: string, keys: string[]): Map<string, string> | null {
  if (reply.length > MAX_REPLY) return null
  const start = reply.indexOf('{')
  const end = reply.lastIndexOf('}')
  if (start < 0 || end <= start) return null
  let json: unknown
  try {
    json = JSON.parse(reply.slice(start, end + 1))
  } catch {
    return null
  }
  const blocks = (json as { blocks?: unknown } | null)?.blocks
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
