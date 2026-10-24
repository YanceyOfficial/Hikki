import { Extension, type Editor } from '@tiptap/core'
import { Plugin, PluginKey } from '@tiptap/pm/state'

import { BLOCK_TYPES } from '../core/blocks'
import {
  DEFAULT_SHORTCUTS,
  isRebound,
  matchesKeys,
  shortcutFor,
  tiptapShortcut,
  type ShortcutId
} from '../core/shortcuts'
import { BLOCK_UNIT_ACTIONS } from './block-units'

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

function turnInto(editor: Editor, blockId: string): boolean {
  const block = BLOCK_TYPES.find((b) => b.id === blockId)
  if (!block?.turnInto) return false
  const done = block.turnInto(editor.chain().focus()).run()
  if (done) block.after?.(editor)
  return done
}

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
        () => turnInto(this.editor, blockId)
      ])
    )
  }
})

/**
 * What every page-handled shortcut does, by id — so a rebound one can run on its new keys. The keymaps (StarterKit's
 * marks, ours) stay bound to the defaults; find has its own keydown listener (main.tsx), which reads the live keys.
 */
export const EDITOR_ACTIONS: Partial<Record<ShortcutId, (editor: Editor) => boolean>> = {
  bold: (editor) => editor.commands.toggleBold(),
  italic: (editor) => editor.commands.toggleItalic(),
  underline: (editor) => editor.commands.toggleUnderline(),
  strikethrough: (editor) => editor.commands.toggleStrike(),
  inlineCode: (editor) => editor.commands.toggleCode(),
  superscript: (editor) => editor.commands.toggleSuperscript(),
  subscript: (editor) => editor.commands.toggleSubscript(),
  ruby: (editor) => editor.commands.editRuby(),
  ...Object.fromEntries(
    BLOCK_SHORTCUTS.map(([id, blockId]) => [id, (editor: Editor) => turnInto(editor, blockId)])
  ),
  ...BLOCK_UNIT_ACTIONS
}

/**
 * The user's rebindings (Settings → Shortcuts, `window.hikki.setShortcuts`), in front of every keymap: a rebound
 * shortcut runs on its new keys, and its old keys — unless another shortcut has them now — do nothing (StarterKit's
 * ⌘B would still bold). Without rebindings it stands aside.
 */
export const ShortcutOverrides = Extension.create({
  name: 'shortcutOverrides',
  priority: 10_000,

  addProseMirrorPlugins() {
    const editor = this.editor
    return [
      new Plugin({
        key: new PluginKey('shortcutOverrides'),
        props: {
          handleKeyDown: (_view, event) => handleRebound(editor, event)
        }
      })
    ]
  }
})

/** The keydown decision, exported for tests: true when it was ours (run or silenced). */
export function handleRebound(editor: Editor, event: KeyboardEvent): boolean {
  const ids = Object.keys(EDITOR_ACTIONS) as ShortcutId[]
  if (!ids.some(isRebound)) return false
  const owner = shortcutFor(event)
  if (owner) {
    const run = EDITOR_ACTIONS[owner]
    // Not rebound: its own keymap has these keys. An app shortcut: the native menu's.
    if (!run || !isRebound(owner)) return false
    run(editor)
    return true
  }
  return ids.some((id) => isRebound(id) && matchesKeys(event, DEFAULT_SHORTCUTS[id]))
}
