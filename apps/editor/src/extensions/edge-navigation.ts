import { Extension } from '@tiptap/core'

/**
 * Lets the caret leave the body upwards into the page title (which lives outside the editor):
 * ArrowUp on the first line, or Backspace at the very start of the document.
 */
export const EdgeNavigation = Extension.create<{ onExitTop: () => void }>({
  name: 'edgeNavigation',

  addOptions() {
    return { onExitTop: () => {} }
  },

  addKeyboardShortcuts() {
    const atDocStart = () => {
      const { selection } = this.editor.state
      return selection.empty && selection.from <= 1
    }
    const exit = () => {
      this.options.onExitTop()
      return true
    }
    return {
      ArrowUp: () => {
        if (!atDocStart() && !this.editor.view.endOfTextblock('up')) return false
        const { $from } = this.editor.state.selection
        // Only from the first top-level block.
        if ($from.index(0) !== 0) return false
        return exit()
      },
      Backspace: () => (atDocStart() ? exit() : false)
    }
  }
})

/**
 * Tab and ⇧Tab stay in the page. Lists, tables and code blocks bind them first (their own keymaps, higher priority);
 * anywhere else the browser would move focus out of the editor — to the next focusable element, scrolling the page
 * back to its top.
 */
export const TabStaysInPage = Extension.create({
  name: 'tabStaysInPage',
  priority: 1,

  addKeyboardShortcuts() {
    return { Tab: () => true, 'Shift-Tab': () => true }
  }
})
