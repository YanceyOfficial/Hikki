import type { Editor } from '@tiptap/core'
import CodeBlockLowlight from '@tiptap/extension-code-block-lowlight'
import type { Node as PMNode } from '@tiptap/pm/model'
import type { NodeView } from '@tiptap/pm/view'
import { common, createLowlight } from 'lowlight'
import { createRoot, type Root } from 'react-dom/client'

import { CodeBlockHeader } from '../ui/CodeBlockHeader'
import { IconProvider } from '../ui/icons'
import { findLanguage, lastCodeLanguage, rememberCodeLanguage } from './code-languages'

const lowlight = createLowlight(common)

/**
 * Code block: lowlight highlighting (Xcode colors, style.css), a language picker and a copy button.
 * New blocks start in the last picked language; nothing is auto-detected (slow on long code, and wrong
 * often enough to be distracting).
 */
export const CodeBlock = CodeBlockLowlight.extend({
  addOptions() {
    return {
      ...this.parent!(),
      lowlight,
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

export { lastCodeLanguage }

class CodeBlockView implements NodeView {
  dom: HTMLElement
  contentDOM: HTMLElement
  private header: HTMLElement
  private root: Root
  private node: PMNode

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
  }

  private render() {
    const language = codeLanguageId(this.node.attrs.language as string | null)
    this.contentDOM.className = `language-${language}`
    this.root.render(
      <IconProvider>
        <CodeBlockHeader
          language={language}
          editable={this.editor.isEditable}
          onLanguage={(id) => this.setLanguage(id)}
          getText={() => this.node.textContent}
        />
      </IconProvider>
    )
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

  update(node: PMNode) {
    if (node.type !== this.node.type) return false
    const changed = node.attrs.language !== this.node.attrs.language
    this.node = node
    if (changed) this.render()
    return true
  }

  /** The header is React's, not ProseMirror's. */
  stopEvent(event: Event) {
    return this.header.contains(event.target as Node)
  }

  ignoreMutation(mutation: MutationRecord | { type: 'selection'; target: Node }) {
    return this.header.contains(mutation.target)
  }

  destroy() {
    const root = this.root
    // Not synchronously: destroy can run while React is rendering.
    queueMicrotask(() => root.unmount())
  }
}
