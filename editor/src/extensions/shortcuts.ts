import { Extension } from '@tiptap/core'

import { BLOCK_TYPES } from '../core/blocks'
import { tiptapShortcut, type ShortcutId } from '../core/shortcuts'

/** Notion's block shortcuts (⌥⌘0–9): which catalog block each one turns the current block into. */
const BLOCK_SHORTCUTS: [ShortcutId, string][] = [
  ['text', 'paragraph'],
  ['heading1', 'heading1'],
  ['heading2', 'heading2'],
  ['heading3', 'heading3'],
  ['todoList', 'taskList'],
  ['bulletedList', 'bulletList'],
  ['numberedList', 'orderedList'],
  ['toggleList', 'toggle'],
  ['codeBlock', 'codeBlock'],
  ['quote', 'blockquote']
]

/**
 * Keyboard shortcuts from the registry (design/shortcuts.json) that turn the current block into another kind.
 * Ahead of StarterKit's own bindings (priority), so one press means one change.
 */
export const BlockShortcuts = Extension.create({
  name: 'blockShortcuts',
  priority: 1000,

  addKeyboardShortcuts() {
    return Object.fromEntries(
      BLOCK_SHORTCUTS.map(([shortcut, blockId]) => [
        tiptapShortcut(shortcut),
        () => {
          const block = BLOCK_TYPES.find((b) => b.id === blockId)
          if (!block?.turnInto) return false
          const done = block.turnInto(this.editor.chain().focus()).run()
          if (done) block.after?.(this.editor)
          return done
        }
      ])
    )
  }
})
