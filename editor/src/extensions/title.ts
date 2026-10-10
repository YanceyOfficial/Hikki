import { Node, mergeAttributes } from '@tiptap/core'
import Document from '@tiptap/extension-document'

/**
 * Notion-style page title: always the first node, plain text only, rendered as the page's h1.
 * It is a dedicated node (not a heading) so block commands can't turn it into something else.
 */
export const Title = Node.create({
  name: 'title',
  content: 'text*',
  marks: '',
  defining: true,

  parseHTML() {
    return [{ tag: 'h1.hikki-title' }]
  },

  renderHTML({ HTMLAttributes }) {
    return ['h1', mergeAttributes(HTMLAttributes, { class: 'hikki-title' }), 0]
  },

  addKeyboardShortcuts() {
    return {
      // Enter in the title jumps into the body instead of splitting the title.
      Enter: ({ editor }) => {
        const { $from } = editor.state.selection
        if ($from.parent.type.name !== this.name) return false
        const afterTitle = $from.after()
        const next = editor.state.doc.nodeAt(afterTitle)
        if (next && next.type.name === 'paragraph' && next.content.size === 0) {
          return editor.commands.setTextSelection(afterTitle + 1)
        }
        return editor
          .chain()
          .insertContentAt(afterTitle, { type: 'paragraph' })
          .setTextSelection(afterTitle + 1)
          .run()
      },
    }
  },
})

/** Document whose first child is always the title. */
export const TitledDocument = Document.extend({
  content: 'title block+',
})
