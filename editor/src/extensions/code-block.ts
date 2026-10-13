import type { Editor } from '@tiptap/core'
import CodeBlockLowlight from '@tiptap/extension-code-block-lowlight'
import type { Node as PMNode } from '@tiptap/pm/model'
import type { NodeView } from '@tiptap/pm/view'
import { common, createLowlight } from 'lowlight'
import { createRoot, type Root } from 'react-dom/client'

import { renderCodeBlockHeader } from '../components/code-block-header'
import { detectLanguage as guessLanguage } from './code-detect'
import { findLanguage, lastCodeLanguage, rememberCodeLanguage } from './code-languages'

const lowlight = createLowlight(common)

/**
 * Code block: lowlight highlighting (Xcode colors, style.css), a language picker and a copy button.
 * New blocks start in the last picked language. "Auto-detect" leaves the guess to lowlight (Tiptap's
 * plugin already highlights an unknown language by guessing) and names the guess in the header.
 */
export const CodeBlock = CodeBlockLowlight.extend({
  addOptions() {
    return {
      ...this.parent!(),
      lowlight: guessingLowlight,
      defaultLanguage: 'plaintext',
      enableTabIndentation: true,
      tabSize: 2
    }
  },

  addNodeView() {
    return ({ node, editor, getPos }) =>
      new CodeBlockView(node, editor, getPos as () => number | undefined)
  }
})

/** ```lang fences and pasted code may name a language by alias ("ts"); store the catalog id. */
export function codeLanguageId(raw: string | null | undefined): string {
  return findLanguage(raw)?.id ?? 'plaintext'
}

const DETECT_DEBOUNCE_MS = 300
/** Longer than this isn't guessed (the signatures scan the whole text on every pause). */
const DETECT_MAX_LENGTH = 20_000

/** A guess for the block's text, or null: too long, or nothing stands out (code-detect.ts). */
export function detectLanguage(text: string): string | null {
  return text.length > DETECT_MAX_LENGTH ? null : guessLanguage(text)
}

/**
 * The lowlight Tiptap's plugin highlights with. Its guess for an unknown language ("auto") is ours, so the
 * colours and the header's label always agree; highlight.js's own guess ranks CSS, JavaScript and Python
 * alike on short snippets.
 */
const guessingLowlight = {
  ...lowlight,
  highlightAuto: (text: string) => lowlight.highlight(detectLanguage(text) ?? 'plaintext', text)
}

export { lastCodeLanguage }

class CodeBlockView implements NodeView {
  dom: HTMLElement
  contentDOM: HTMLElement
  private header: HTMLElement
  private root: Root
  private node: PMNode
  /** In "auto": what lowlight guessed last, for the header. */
  private detected: string | null = null
  private detectTimer: ReturnType<typeof setTimeout> | null = null

  constructor(
    node: PMNode,
    private readonly editor: Editor,
    private readonly getPos: () => number | undefined
  ) {
    this.node = node
    this.dom = document.createElement('div')
    this.dom.className = 'hk-code-block group/code relative'
    this.header = document.createElement('div')
    this.header.contentEditable = 'false'
    this.header.className = 'hk-code-header'
    const pre = document.createElement('pre')
    this.contentDOM = document.createElement('code')
    pre.append(this.contentDOM)
    this.dom.append(this.header, pre)
    this.root = createRoot(this.header)
    this.render()
    this.scheduleDetection()
  }

  private render() {
    const language = codeLanguageId(this.node.attrs.language as string | null)
    // Only when it changes: an attribute write on the content element, even with the same value, is a DOM
    // mutation ProseMirror would answer by rebuilding the node view (and forgetting the guess).
    const className = `language-${language}`
    if (this.contentDOM.className !== className) this.contentDOM.className = className
    renderCodeBlockHeader(this.root, {
      language,
      detected: language === 'auto' ? this.detected : null,
      editable: this.editor.isEditable,
      onLanguage: (id) => this.setLanguage(id),
      getText: () => this.node.textContent
    })
  }

  private setLanguage(id: string) {
    const pos = this.getPos()
    if (pos === undefined) return
    rememberCodeLanguage(id)
    this.editor
      .chain()
      .command(({ tr }) => {
        tr.setNodeMarkup(pos, undefined, { ...this.node.attrs, language: id })
        return true
      })
      .focus(pos + 1 + this.node.content.size)
      .run()
  }

  /** Guesses a little after typing stops; a changed guess re-renders the header. */
  private scheduleDetection() {
    if (this.detectTimer) clearTimeout(this.detectTimer)
    if (codeLanguageId(this.node.attrs.language as string | null) !== 'auto') {
      this.detected = null
      return
    }
    this.detectTimer = setTimeout(() => {
      this.detectTimer = null
      const guess = detectLanguage(this.node.textContent)
      if (guess === this.detected) return
      this.detected = guess
      this.render()
    }, DETECT_DEBOUNCE_MS)
  }

  update(node: PMNode) {
    if (node.type !== this.node.type) return false
    const changed = node.attrs.language !== this.node.attrs.language
    const retyped = node.textContent !== this.node.textContent
    this.node = node
    if (changed) this.render()
    if (changed || retyped) this.scheduleDetection()
    return true
  }

  /** The header is React's, not ProseMirror's. */
  stopEvent(event: Event) {
    return this.header.contains(event.target as Node)
  }

  ignoreMutation(mutation: MutationRecord | { type: 'selection'; target: Node }) {
    if (this.header.contains(mutation.target)) return true
    // The language class on the content element is ours, not the document's.
    return mutation.type === 'attributes' && mutation.target === this.contentDOM
  }

  destroy() {
    if (this.detectTimer) clearTimeout(this.detectTimer)
    const root = this.root
    // Not synchronously: destroy can run while React is rendering.
    queueMicrotask(() => root.unmount())
  }
}
