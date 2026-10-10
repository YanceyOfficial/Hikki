import { Editor, type JSONContent } from '@tiptap/core'
import { TaskItem, TaskList } from '@tiptap/extension-list'
import { Placeholder } from '@tiptap/extensions'
import StarterKit from '@tiptap/starter-kit'

import { blockHandleExtensions } from './extensions/block-handle'
import { EdgeNavigation } from './extensions/edge-navigation'
import { SlashCommand } from './extensions/slash-command'
import { t } from './i18n'
import type { Command } from './protocol'

type EditorOptions = { onExitTop?: () => void }

/** The page body editor. `content` must already be normalized (see normalizeBody). */
export function createEditor(
  element: HTMLElement,
  content: JSONContent | null,
  options: EditorOptions = {}
): Editor {
  return new Editor({
    element,
    content: content ?? { type: 'doc', content: [{ type: 'paragraph' }] },
    extensions: [
      StarterKit.configure({ link: { openOnClick: false } }),
      TaskList,
      TaskItem.configure({ nested: true }),
      Placeholder.configure({
        includeChildren: false,
        placeholder: ({ node }) =>
          node.type.name === 'paragraph' ? t('editor.bodyPlaceholder') : ''
      }),
      EdgeNavigation.configure({ onExitTop: options.onExitTop ?? (() => {}) }),
      SlashCommand,
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
