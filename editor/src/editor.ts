import { Editor, type JSONContent } from '@tiptap/core'
import { TaskItem, TaskList } from '@tiptap/extension-list'
import Subscript from '@tiptap/extension-subscript'
import Superscript from '@tiptap/extension-superscript'
import UniqueID from '@tiptap/extension-unique-id'
import { Placeholder } from '@tiptap/extensions'
import StarterKit from '@tiptap/starter-kit'

import { blockHandleExtensions } from './extensions/block-handle'
import { Callout } from './extensions/callout'
import { CodeBlock } from './extensions/code-block'
import { Colors, ColorTextStyle } from './extensions/colors'
import { EdgeNavigation } from './extensions/edge-navigation'
import { mathExtension } from './extensions/math'
import { SelectionMenuExtension } from './extensions/selection-menu'
import { SlashCommand } from './extensions/slash-command'
import { tableExtensions } from './extensions/table'
import { Quote, toggleExtensions } from './extensions/toggle'
import { t } from './i18n'
import { isSafeHref } from './links'
import type { Command } from './protocol'

type EditorOptions = {
  onExitTop?: () => void
  /** The stored content doesn't fit the schema (corrupt, or from a newer Hikki). See EditorBridge. */
  onContentError?: (error: Error) => void
}

/**
 * Blocks that carry a stable `id` attribute: the anchor for version diffs, block links and, later,
 * comments and collaboration. Inline nodes and list wrappers don't need one.
 */
export const BLOCK_ID_TYPES = [
  'paragraph',
  'heading',
  'blockquote',
  'codeBlock',
  'horizontalRule',
  'listItem',
  'taskItem',
  'bulletList',
  'orderedList',
  'taskList',
  'details',
  'callout',
  'blockMath',
  'table'
]

/** The page body editor. `content` must already be normalized (see normalizeBody). */
export function createEditor(
  element: HTMLElement,
  content: JSONContent | null,
  options: EditorOptions = {}
): Editor {
  return new Editor({
    element,
    content: content ?? { type: 'doc', content: [{ type: 'paragraph' }] },
    // Invalid content (unknown nodes, wrong nesting) raises contentError instead of loading silently
    // stripped: saving that stripped copy would delete what this build can't show.
    enableContentCheck: true,
    onContentError: ({ error }) => options.onContentError?.(error),
    extensions: [
      StarterKit.configure({
        // Only allowlisted targets are stored or rendered (links.ts); hikki:// links open pages.
        link: { openOnClick: false, protocols: ['hikki'], isAllowedUri: (url) => isSafeHref(url) },
        codeBlock: false,
        blockquote: false
      }),
      CodeBlock,
      Quote,
      ...toggleExtensions,
      Callout,
      mathExtension(),
      ...tableExtensions,
      TaskList,
      TaskItem.configure({ nested: true }),
      ColorTextStyle,
      Colors,
      Subscript,
      Superscript,
      Placeholder.configure({
        includeChildren: false,
        placeholder: ({ node }) =>
          node.type.name === 'paragraph' ? t('editor.bodyPlaceholder') : ''
      }),
      EdgeNavigation.configure({ onExitTop: options.onExitTop ?? (() => {}) }),
      SlashCommand,
      SelectionMenuExtension,
      UniqueID.configure({ types: BLOCK_ID_TYPES }),
      ...blockHandleExtensions()
    ]
  })
}

export function runCommand(editor: Editor, command: Command): boolean {
  const chain = editor.chain().focus()
  switch (command) {
    case 'bold':
      return chain.toggleBold().run()
    case 'italic':
      return chain.toggleItalic().run()
    case 'strike':
      return chain.toggleStrike().run()
    case 'code':
      return chain.toggleCode().run()
    case 'heading1':
      return chain.toggleHeading({ level: 1 }).run()
    case 'heading2':
      return chain.toggleHeading({ level: 2 }).run()
    case 'heading3':
      return chain.toggleHeading({ level: 3 }).run()
    case 'paragraph':
      return chain.setParagraph().run()
    case 'bulletList':
      return chain.toggleBulletList().run()
    case 'orderedList':
      return chain.toggleOrderedList().run()
    case 'taskList':
      return chain.toggleTaskList().run()
    case 'blockquote':
      return chain.toggleBlockquote().run()
    case 'codeBlock':
      return chain.toggleCodeBlock().run()
    case 'undo':
      return chain.undo().run()
    case 'redo':
      return chain.redo().run()
  }
}

export function activeCommands(editor: Editor): Command[] {
  const checks: [Command, boolean][] = [
    ['bold', editor.isActive('bold')],
    ['italic', editor.isActive('italic')],
    ['strike', editor.isActive('strike')],
    ['code', editor.isActive('code')],
    ['heading1', editor.isActive('heading', { level: 1 })],
    ['heading2', editor.isActive('heading', { level: 2 })],
    ['heading3', editor.isActive('heading', { level: 3 })],
    ['bulletList', editor.isActive('bulletList')],
    ['orderedList', editor.isActive('orderedList')],
    ['taskList', editor.isActive('taskList')],
    ['blockquote', editor.isActive('blockquote')],
    ['codeBlock', editor.isActive('codeBlock')]
  ]
  return checks.filter(([, on]) => on).map(([c]) => c)
}
