import caretSvg from '@phosphor-icons/core/assets/fill/caret-right-fill.svg?raw'
import { type Editor, InputRule, wrappingInputRule } from '@tiptap/core'
import Blockquote from '@tiptap/extension-blockquote'
import { Details, DetailsContent, DetailsSummary } from '@tiptap/extension-details'

import { t } from '../core/i18n'

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
    // Phosphor's filled caret (Notion's solid triangle), static markup from the icon package; rotated by CSS.
    if (!element.firstChild)
      element.innerHTML = caretSvg.replace('<svg ', '<svg aria-hidden="true" ')
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

/**
 * Opens every closed toggle around `pos`, so what is there can be seen, measured and scrolled to (a closed
 * toggle's content is `hidden`) — arriving by a search result, a link to a block, the outline or a comment.
 * Done as the node view's own toggle does it, minus its button's focus(): arriving must not focus the page (or
 * raise the keyboard), and a dispatch from inside a command would leave that command's transaction stale.
 */
export function openTogglesAround(editor: Editor, pos: number): void {
  const $pos = editor.state.doc.resolve(pos)
  for (let depth = $pos.depth; depth > 0; depth--) {
    if ($pos.node(depth).type.name !== 'details') continue
    const dom = editor.view.nodeDOM($pos.before(depth))
    if (!(dom instanceof HTMLElement) || dom.classList.contains('is-open')) continue
    dom.classList.add('is-open')
    const button = dom.querySelector<HTMLButtonElement>(':scope > button')
    if (button) {
      button.setAttribute('aria-label', t('toggle.collapse'))
      button.setAttribute('aria-expanded', 'true')
    }
    dom
      .querySelector(':scope > div > [data-type="detailsContent"]')
      ?.dispatchEvent(new Event('toggleDetailsContent'))
  }
}

export const SUMMARY_LEVELS = [1, 2, 3] as const

/**
 * A toggle's summary may be a heading (Notion's toggle headings): `level` 1–3, or null for plain text. `# `,
 * `## ` or `### ` at the start of a summary sets it; Backspace at its start clears it before it would unwrap the
 * toggle. Stored as an optional attribute (absent = plain), so pages from before load as they were.
 */
export const ToggleSummary = DetailsSummary.extend({
  // Ahead of Details' own Backspace (which unwraps the toggle at the summary's start).
  priority: 110,
  addAttributes() {
    return {
      ...this.parent?.(),
      level: {
        default: null,
        parseHTML: (el: HTMLElement) => {
          const level = Number(el.dataset.level)
          return (SUMMARY_LEVELS as readonly number[]).includes(level) ? level : null
        },
        renderHTML: (attrs: Record<string, unknown>) =>
          attrs.level ? { 'data-level': String(attrs.level) } : {}
      }
    }
  },
  addInputRules() {
    return [
      new InputRule({
        find: /^(#{1,3})\s$/u,
        handler: ({ state, range, match }) => {
          const { $from } = state.selection
          if ($from.parent.type !== this.type) return null
          state.tr.deleteRange(range.from, range.to).setNodeMarkup($from.before(), undefined, {
            ...$from.parent.attrs,
            level: match[1].length
          })
        }
      })
    ]
  },
  addKeyboardShortcuts() {
    return {
      Backspace: () => {
        const { selection } = this.editor.state
        const { $from, empty } = selection
        if (!empty || $from.parent.type !== this.type || $from.parentOffset !== 0) return false
        if (!$from.parent.attrs.level) return false
        return this.editor.commands.command(({ tr }) => {
          tr.setNodeMarkup($from.before(), undefined, { ...$from.parent.attrs, level: null })
          return true
        })
      }
    }
  }
})

export const toggleExtensions = [Toggle, ToggleSummary, DetailsContent]

/** Quote moves to Notion's `" ` shortcut (straight or curly), leaving "> " to toggles. */
export const Quote = Blockquote.extend({
  addInputRules() {
    return [wrappingInputRule({ find: /^\s*["“”]\s$/u, type: this.type })]
  }
})
