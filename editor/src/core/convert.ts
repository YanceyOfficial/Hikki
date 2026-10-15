import {
  generateJSON,
  getExtensionField,
  getHTMLFromFragment,
  getSchema,
  type AnyExtension,
  type JSONContent
} from '@tiptap/core'
import { MarkdownManager } from '@tiptap/markdown'
import { DOMSerializer, Node as PMNode, type Schema } from '@tiptap/pm/model'

import { editorExtensions } from './editor'
import { plainText, wordCount } from './extract'
import { normalizeBody } from './normalize'
import type { ExportFormat, ImportFormat, ImportedPage, PagePayload } from './protocol'

/**
 * Import and export of pages, in the editor's own schema: the native side reads and writes the files, this turns
 * them into page content and back. Markdown goes through Tiptap's official `@tiptap/markdown`; HTML through the
 * schema's own parse and render rules — so an imported page always fits the schema.
 */

let cached: { extensions: AnyExtension[]; schema: Schema; markdown: MarkdownManager } | null = null

/** The page editor's extensions and schema (no editor, no view), built once. */
function converter() {
  if (cached) return cached
  const base = editorExtensions()
  const schema = getSchema(base)
  // Blocks without a Markdown form of their own (callouts, toggles, columns, embeds, media…) still export: a
  // container as its blocks, anything else as the HTML the page would render — Markdown allows inline HTML.
  const extensions = base.map((extension) => {
    if (extension.type !== 'node' || getExtensionField(extension, 'renderMarkdown'))
      return extension
    return extension.extend({
      renderMarkdown: (
        node: JSONContent,
        helpers: { renderChildren: (n: JSONContent[], s?: string) => string }
      ) =>
        node.content?.length ? helpers.renderChildren(node.content, '\n\n') : nodeHTML(schema, node)
    })
  })
  cached = { extensions, schema, markdown: new MarkdownManager({ extensions }) }
  return cached
}

function nodeHTML(schema: Schema, json: JSONContent): string {
  try {
    const node = PMNode.fromJSON(schema, json)
    const wrapper = document.createElement('div')
    wrapper.append(DOMSerializer.fromSchema(schema).serializeNode(node))
    return wrapper.innerHTML
  } catch {
    return ''
  }
}

const emptyDoc = (): JSONContent => ({ type: 'doc', content: [{ type: 'paragraph' }] })

/** The page's body as stored, the title taken out of it (old pages carried it) — what the editor shows. */
function pageBody(page: Pick<PagePayload, 'title' | 'content'>): {
  title: string
  content: JSONContent
} {
  const { body, title } = normalizeBody(page.content, page.title ?? '')
  return { title: title.trim(), content: body }
}

/** A page as a Markdown or HTML document: the title as its first heading, then the body. */
export function exportPage(
  page: Pick<PagePayload, 'title' | 'content'>,
  format: ExportFormat
): string {
  const { title, content } = pageBody(page)
  const { schema, markdown } = converter()
  if (format === 'markdown') {
    const text = markdown.serialize(content).trim()
    return `${title ? `# ${title}\n\n` : ''}${text}\n`
  }
  let html: string
  try {
    html = getHTMLFromFragment(PMNode.fromJSON(schema, content).content, schema)
  } catch {
    // Content this build can't read (a newer Hikki): its text, rather than nothing.
    html = `<p>${escapeHTML(plainLines(content))}</p>`
  }
  const heading = title ? `<h1>${escapeHTML(title)}</h1>\n` : ''
  return `<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHTML(title)}</title>
<style>body{max-width:46rem;margin:2rem auto;padding:0 1rem;font-family:-apple-system,system-ui,sans-serif;line-height:1.6}img,video{max-width:100%}</style>
</head>
<body>
${heading}${html}
</body>
</html>
`
}

/**
 * A Markdown, HTML or plain-text file as a new page's title and body. A leading level-1 heading (or an HTML
 * `<title>`) becomes the title; otherwise `fallbackTitle` (the file's name). Whatever the file holds, the body fits
 * the schema: anything that doesn't parse falls back to the text, line by line.
 */
export function importDocument(
  text: string,
  format: ImportFormat,
  fallbackTitle: string
): ImportedPage {
  const { extensions, schema, markdown } = converter()
  let content: JSONContent
  let docTitle = ''
  try {
    if (format === 'markdown') {
      content = liftBlockMedia(markdown.parse(text))
    } else if (format === 'html') {
      const parsed = new DOMParser().parseFromString(text, 'text/html')
      docTitle = parsed.title.trim()
      content = generateJSON(parsed.body.innerHTML, extensions)
    } else {
      content = textDocument(text)
    }
    PMNode.fromJSON(schema, content).check()
  } catch (error) {
    // Into the native log (the reason only — never the file's text).
    console.warn(
      `import fell back to text: ${error instanceof Error ? error.message : String(error)}`
    )
    content = textDocument(text)
  }
  const blocks = [...(content.content ?? [])]
  const first = blocks[0]
  let title = docTitle
  if (first?.type === 'heading' && first.attrs?.level === 1) {
    const heading = textOf(first).trim()
    if (!title || heading === title) {
      title = heading
      blocks.shift()
    }
  }
  const pageTitle = (title || fallbackTitle).trim().slice(0, 500)
  const doc = blocks.length ? { type: 'doc', content: blocks } : emptyDoc()
  // Text and word count as a save computes them (the page is stored like any other).
  const plain = plainText(doc)
  return {
    title: pageTitle,
    content: doc,
    text: plain,
    wordCount: wordCount(`${pageTitle}\n${plain}`)
  }
}

/** Media nodes that are blocks in the page's schema. */
const BLOCK_MEDIA = new Set(['image', 'video', 'audio', 'fileAttachment'])

/**
 * Markdown puts a picture inside a paragraph (`Text ![x](a.png) more`); the page's pictures are blocks of their own.
 * Each one is lifted out where it stands — the paragraph split around it, empty halves dropped.
 */
export function liftBlockMedia(node: JSONContent): JSONContent {
  if (!node.content) return node
  const content: JSONContent[] = []
  for (const child of node.content.map(liftBlockMedia)) {
    if (child.type !== 'paragraph' || !child.content?.some((c) => BLOCK_MEDIA.has(c.type ?? ''))) {
      content.push(child)
      continue
    }
    let run: JSONContent[] = []
    const flush = () => {
      const trimmed = trimRun(run)
      if (trimmed.length > 0) content.push({ ...child, content: trimmed })
      run = []
    }
    for (const inline of child.content) {
      if (BLOCK_MEDIA.has(inline.type ?? '')) {
        flush()
        content.push(inline)
      } else run.push(inline)
    }
    flush()
  }
  return { ...node, content }
}

/** A paragraph's piece without the spaces and line breaks left at its edges by the lifted picture. */
function trimRun(run: JSONContent[]): JSONContent[] {
  const out = [...run]
  while (out[0]?.type === 'hardBreak') out.shift()
  while (out.at(-1)?.type === 'hardBreak') out.pop()
  if (out[0]?.type === 'text')
    out[0] = { ...out[0], text: (out[0].text ?? '').replace(/^\s+/u, '') }
  const last = out.at(-1)
  if (last?.type === 'text')
    out[out.length - 1] = { ...last, text: (last.text ?? '').replace(/\s+$/u, '') }
  return out.filter((n) => n.type !== 'text' || (n.text ?? '') !== '')
}

/** Plain text: a paragraph per run of lines, blank lines between them; lines inside one keep their breaks. */
function textDocument(text: string): JSONContent {
  const paragraphs = text
    .replaceAll(/\r\n?/gu, '\n')
    .split(/\n{2,}/u)
    .map((chunk) => chunk.replaceAll(/^\n+|\n+$/gu, ''))
    .filter((chunk) => chunk.trim() !== '')
  if (paragraphs.length === 0) return emptyDoc()
  return {
    type: 'doc',
    content: paragraphs.map((chunk) => ({
      type: 'paragraph',
      content: chunk
        .split('\n')
        .flatMap((line, index): JSONContent[] => [
          ...(index > 0 ? [{ type: 'hardBreak' }] : []),
          ...(line ? [{ type: 'text', text: line }] : [])
        ])
    }))
  }
}

const textOf = (node: JSONContent): string =>
  node.type === 'text' ? (node.text ?? '') : (node.content ?? []).map(textOf).join('')

const plainLines = (node: JSONContent): string =>
  (node.content ?? []).map(textOf).filter(Boolean).join('\n')

const escapeHTML = (text: string) =>
  text
    .replaceAll(/&/gu, '&amp;')
    .replaceAll(/</gu, '&lt;')
    .replaceAll(/>/gu, '&gt;')
    .replaceAll(/"/gu, '&quot;')

/** What an AI answer may hold: text, lists, quotes, code and tables — no media or embeds (a remote picture in an
 * answer would load from wherever the model pointed). */
const ANSWER_NODES = new Set([
  'doc',
  'paragraph',
  'text',
  'hardBreak',
  'heading',
  'bulletList',
  'orderedList',
  'listItem',
  'taskList',
  'taskItem',
  'blockquote',
  'codeBlock',
  'horizontalRule',
  'table',
  'tableRow',
  'tableHeader',
  'tableCell'
])

/** Only web links stay links; other marks stay as they are. */
function answerNode(node: JSONContent): JSONContent | null {
  if (!node.type || !ANSWER_NODES.has(node.type)) return null
  const marks = node.marks?.filter((mark) => {
    if (mark.type !== 'link') return true
    const href = mark.attrs?.href
    return typeof href === 'string' && /^https?:\/\//iu.test(href)
  })
  const content = node.content?.map(answerNode).filter((n): n is JSONContent => n !== null)
  return {
    ...node,
    ...(marks ? { marks } : {}),
    ...(content ? { content } : {})
  }
}

/**
 * An AI answer's Markdown (untrusted) as blocks of the page's schema — media and embeds left out, non-web links
 * unlinked — or its text as paragraphs when it doesn't parse into something the schema takes.
 */
export function markdownBlocks(text: string): JSONContent[] {
  const { schema, markdown } = converter()
  try {
    const content = answerNode(markdown.parse(text))
    if (!content) throw new Error('no content')
    PMNode.fromJSON(schema, content).check()
    return content.content ?? []
  } catch {
    return textDocument(text).content ?? []
  }
}

/** The same blocks drawn for the answer card: built node by node from the schema, never parsed from a string. */
export function markdownDOM(text: string): DocumentFragment {
  const { schema } = converter()
  try {
    const doc = PMNode.fromJSON(schema, { type: 'doc', content: markdownBlocks(text) })
    const fragment = document.createDocumentFragment()
    fragment.append(DOMSerializer.fromSchema(schema).serializeFragment(doc.content))
    return fragment
  } catch {
    const fragment = document.createDocumentFragment()
    fragment.append(document.createTextNode(text))
    return fragment
  }
}
