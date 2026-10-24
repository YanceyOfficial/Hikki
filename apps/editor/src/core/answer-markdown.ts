import type { Editor, JSONContent } from '@tiptap/core'
import { MarkdownManager } from '@tiptap/markdown'
import { DOMSerializer, Node as PMNode, type Schema } from '@tiptap/pm/model'

import { fitMarks, textDocument } from './content-fit'
import { isWebURL } from './links'

/**
 * AI answers (untrusted Markdown) as the page's own blocks, read with the open editor's schema and extensions —
 * so the AI review (an extension of that editor) needs neither convert.ts nor a second copy of the schema.
 */
type Source = Pick<Editor, 'schema' | 'extensionManager'>

const managers = new WeakMap<Schema, MarkdownManager>()

function markdownFor(source: Source): MarkdownManager {
  let manager = managers.get(source.schema)
  if (!manager) {
    manager = new MarkdownManager({ extensions: source.extensionManager.extensions })
    managers.set(source.schema, manager)
  }
  return manager
}

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
  const marks = node.marks?.filter((mark) => mark.type !== 'link' || isWebURL(mark.attrs?.href))
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
export function answerBlocks(source: Source, text: string): JSONContent[] {
  const { schema } = source
  try {
    const answer = answerNode(markdownFor(source).parse(text))
    if (!answer) throw new Error('no content')
    const content = fitMarks(answer, schema)
    PMNode.fromJSON(schema, content).check()
    return content.content ?? []
  } catch {
    return textDocument(text).content ?? []
  }
}

/** The same blocks drawn for the answer card: built node by node from the schema, never parsed from a string. */
export function answerDOM(source: Source, text: string): DocumentFragment {
  const { schema } = source
  const fragment = document.createDocumentFragment()
  try {
    const doc = PMNode.fromJSON(schema, { type: 'doc', content: answerBlocks(source, text) })
    fragment.append(DOMSerializer.fromSchema(schema).serializeFragment(doc.content))
  } catch {
    fragment.append(document.createTextNode(text))
  }
  return fragment
}
