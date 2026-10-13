import { mergeAttributes, Node, type Editor } from '@tiptap/core'
import type { NodeView } from '@tiptap/pm/view'

import { collectHeadings } from '../core/headings'
import { t } from '../core/i18n'

/**
 * Table of contents block (Notion): lists the page's headings, indented by level, and jumps to one on click.
 * Stores nothing but its presence; the list is derived from the document as it changes.
 */
export const TableOfContents = Node.create({
  name: 'tableOfContents',
  group: 'block',
  atom: true,
  selectable: true,
  draggable: true,

  parseHTML() {
    return [{ tag: 'nav[data-type="table-of-contents"]' }]
  },

  renderHTML({ HTMLAttributes }) {
    return ['nav', mergeAttributes(HTMLAttributes, { 'data-type': 'table-of-contents' })]
  },

  addNodeView() {
    return ({ editor }) => new TableOfContentsView(editor)
  }
})

class TableOfContentsView implements NodeView {
  dom: HTMLElement
  private key = ''

  constructor(private readonly editor: Editor) {
    this.dom = document.createElement('nav')
    this.dom.dataset.type = 'table-of-contents'
    this.dom.className = 'hk-toc'
    this.dom.contentEditable = 'false'
    this.dom.setAttribute('aria-label', t('toc.label'))
    this.render()
    editor.on('update', this.render)
  }

  /** Rebuilt only when the headings change (text, level or order). */
  private render = () => {
    const headings = collectHeadings(this.editor)
    const key = headings.map((h) => `${h.level}:${h.text}`).join('\n')
    if (key === this.key && this.dom.childElementCount > 0) return
    this.key = key
    this.dom.replaceChildren()
    if (headings.length === 0) {
      const empty = document.createElement('p')
      empty.className = 'hk-toc-empty'
      empty.textContent = t('toc.empty')
      this.dom.append(empty)
      return
    }
    const minLevel = Math.min(...headings.map((h) => h.level))
    for (const heading of headings) {
      const link = document.createElement('button')
      link.type = 'button'
      link.className = 'hk-toc-item'
      link.style.paddingLeft = `${(heading.level - minLevel) * 1.25}rem`
      link.textContent = heading.text
      link.addEventListener('click', () => this.jump(heading.text, heading.level))
      this.dom.append(link)
    }
  }

  /** Scrolls to the heading (looked up again: positions move as the page is edited). */
  private jump(text: string, level: number) {
    const target = collectHeadings(this.editor).find((h) => h.text === text && h.level === level)
    if (!target) return
    const dom = this.editor.view.nodeDOM(target.pos)
    if (dom instanceof HTMLElement) dom.scrollIntoView({ behavior: 'smooth', block: 'start' })
    this.editor.commands.setTextSelection(target.pos + 1)
  }

  stopEvent(event: Event) {
    return event.type === 'click' || event.type === 'mousedown'
  }

  ignoreMutation() {
    return true
  }

  destroy() {
    this.editor.off('update', this.render)
  }
}
