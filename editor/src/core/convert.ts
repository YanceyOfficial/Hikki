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
      content = markdown.parse(text)
    } else if (format === 'html') {
      const parsed = new DOMParser().parseFromString(text, 'text/html')
      docTitle = parsed.title.trim()
      content = generateJSON(parsed.body.innerHTML, extensions)
    } else {
      content = textDocument(text)
    }
    PMNode.fromJSON(schema, content).check()
  } catch {
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
