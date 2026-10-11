import { type Editor, InputRule, wrappingInputRule } from '@tiptap/core'
import Blockquote from '@tiptap/extension-blockquote'
import { Details, DetailsContent, DetailsSummary } from '@tiptap/extension-details'

import { t } from '../i18n'

/**
 * Toggle list (Notion's "> " shortcut). Open/closed is view state, not content: it isn't stored, so
 * opening a toggle never counts as editing the page (toggles start closed, as in Notion).
 */
export const Toggle = Details.extend({
  addInputRules() {
    return [
      new InputRule({
        find: /^>\s$/u,
        handler: ({ range, chain }) => {
          chain().deleteRange(range).setDetails().run()
          // The rule's transaction is dispatched after this handler; open once it's in the DOM.
          const editor = this.editor
          setTimeout(() => openToggleAtSelection(editor))
        }
      })
    ]
  }
}).configure({
  persist: false,
  HTMLAttributes: { class: 'hk-toggle' },
  renderToggleButton: ({ element, isOpen }) => {
    if (!element.firstChild) element.append(caret())
    element.setAttribute('aria-label', isOpen ? t('toggle.collapse') : t('toggle.expand'))
    element.setAttribute('aria-expanded', String(isOpen))
  }
})

/**
 * A toggle just created opens (Notion), so Enter in its summary goes into the content. Open/closed lives in
 * the DOM (`persist: false`), so this clicks the node view's own button.
 */
export function openToggleAtSelection(editor: Editor): void {
  const { $from } = editor.state.selection
  for (let depth = $from.depth; depth > 0; depth--) {
    if ($from.node(depth).type.name !== 'details') continue
    const dom = editor.view.nodeDOM($from.before(depth))
    if (dom instanceof HTMLElement && !dom.classList.contains('is-open')) {
      dom.querySelector<HTMLButtonElement>(':scope > button')?.click()
    }
    return
  }
}

/** A small rounded triangle (rotated by CSS when open). Static markup, built with DOM APIs. */
function caret(): SVGSVGElement {
  const ns = 'http://www.w3.org/2000/svg'
  const svg = document.createElementNS(ns, 'svg')
  svg.setAttribute('viewBox', '0 0 16 16')
  svg.setAttribute('aria-hidden', 'true')
  const path = document.createElementNS(ns, 'path')
  path.setAttribute('d', 'M6 3.5 11.5 8 6 12.5Z')
  path.setAttribute('fill', 'currentColor')
  path.setAttribute('stroke', 'currentColor')
  path.setAttribute('stroke-linejoin', 'round')
  path.setAttribute('stroke-width', '1.5')
  svg.append(path)
  return svg
}

export const toggleExtensions = [Toggle, DetailsSummary, DetailsContent]

/** Quote moves to Notion's `" ` shortcut (straight or curly), leaving "> " to toggles. */
export const Quote = Blockquote.extend({
  addInputRules() {
    return [wrappingInputRule({ find: /^\s*["“”]\s$/u, type: this.type })]
  }
})
