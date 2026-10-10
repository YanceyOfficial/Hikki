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
