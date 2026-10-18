import { Editor, type AnyExtension, type JSONContent } from '@tiptap/core'
import { TaskItem, TaskList } from '@tiptap/extension-list'
import Subscript from '@tiptap/extension-subscript'
import Superscript from '@tiptap/extension-superscript'
import Typography from '@tiptap/extension-typography'
import UniqueID from '@tiptap/extension-unique-id'
import { CharacterCount, Placeholder } from '@tiptap/extensions'
import StarterKit from '@tiptap/starter-kit'

import { AIChanges, type AIChangesHost } from '../extensions/ai-changes'
import { AIReview, type AIHost } from '../extensions/ai-review'
import { BlockControls } from '../extensions/block-controls'
import { Callout } from '../extensions/callout'
import { CodeBlock } from '../extensions/code-block'
import { Colors, ColorTextStyle } from '../extensions/colors'
import { Column, Columns, ColumnsKeymap } from '../extensions/columns'
import { Comments, type CommentsHost } from '../extensions/comments'
import { EdgeNavigation } from '../extensions/edge-navigation'
import { Embed } from '../extensions/embed'
import { EmojiSuggestion } from '../extensions/emoji-suggestion'
import { Find } from '../extensions/find'
import { ImageLoading } from '../extensions/image-loading'
import { mathExtension } from '../extensions/math'
import { mediaExtensions, type MediaHost } from '../extensions/media'
import { PageLinks, type PageLinksHost } from '../extensions/page-links'
import { PageMention } from '../extensions/page-mention'
import { Ruby, type RubyHost } from '../extensions/ruby'
import { SelectionMenuExtension } from '../extensions/selection-menu'
import { SelectionPaint } from '../extensions/selection-paint'
import { BlockShortcuts, ShortcutOverrides } from '../extensions/shortcuts'
import { SlashCommand } from '../extensions/slash-command'
import { SplitDrop, type SplitDropHost } from '../extensions/split-drop'
import { tableExtensions } from '../extensions/table'
import { TableOfContents } from '../extensions/toc'
import { Quote, toggleExtensions } from '../extensions/toggle'
import { bffURL } from '../lib/bff'
import type { LinkCard } from '../lib/embeds'
import { setMediaHost } from './blocks'
import { t } from './i18n'
import { isSafeHref } from './links'
import type { Command } from './protocol'
import { tiptapShortcut } from './shortcuts'

/** Page links without a host (the browser dev build, tests): titles unknown, clicks go nowhere. */
const noPageLinks: PageLinksHost = {
  pages: () => [],
  currentPageId: () => null,
  untitled: () => t('page.untitled'),
  open: () => {},
  openExternal: (href) => window.open(href, '_blank', 'noopener')
}

type EditorOptions = {
  onExitTop?: () => void
  /** The stored content doesn't fit the schema (corrupt, or from a newer Hikki). See EditorBridge. */
  onContentError?: (error: Error) => void
  /** WebKit's spell checker (system dictionaries, suggestions in the context menu); on by default. */
  spellcheck?: boolean
  /** Uploads and opening attachments (the bridge); without it, files can't be dropped or picked. */
  media?: MediaHost
  /** Page links: titles for links to other pages, and where clicks go. */
  pageLinks?: PageLinksHost
  /** Furigana reading suggestions (the native tokenizer). */
  ruby?: RubyHost
  /** A link card's details (title, description, icon), read natively; without it cards show the bare link. */
  linkPreview?: (url: string) => Promise<LinkCard | null>
  /** A page dropped on the right edge opens in split view; without it there is no such edge. */
  splitDrop?: SplitDropHost
  /** AI on the selection (the native AI service); without it the AI actions do nothing. */
  ai?: AIHost
  /** Changes Ask AI proposes to the page, reviewed in it. */
  aiChanges?: AIChangesHost
  /** Comments on passages (the native store); without it the threads stay empty and nothing is written. */
  comments?: CommentsHost
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
  'table',
  'columns',
  'image',
  'video',
  'audio',
  'fileAttachment',
  'embed'
]

/** The page body editor. `content` must already be normalized (see normalizeBody). */
const noComments: CommentsHost = {
  create: () => {},
  reply: () => {},
  resolve: () => {},
  remove: () => {},
  edit: () => {},
  device: () => null,
  pages: () => [],
  openPage: () => {},
  link: () => null
}

export function createEditor(
  element: HTMLElement,
  content: JSONContent | null,
  options: EditorOptions = {}
): Editor {
  setMediaHost(options.media ?? null)
  return new Editor({
    element,
    content: content ?? { type: 'doc', content: [{ type: 'paragraph' }] },
    // Invalid content (unknown nodes, wrong nesting) raises contentError instead of loading silently
    // stripped: saving that stripped copy would delete what this build can't show.
    enableContentCheck: true,
    editorProps: {
      attributes: {
        spellcheck: String(options.spellcheck ?? true),
        'aria-label': t('editor.contentLabel')
      }
    },
    onContentError: ({ error }) => options.onContentError?.(error),
    extensions: editorExtensions(options)
  })
}

/**
 * Every extension of the page editor — the schema pages are stored in. Import and export (convert.ts) build the
 * same schema from it without an editor.
 */
export function editorExtensions(options: EditorOptions = {}): AnyExtension[] {
  return [
    StarterKit.configure({
      // Only allowlisted targets are stored or rendered (links.ts); hikki:// links open pages.
      link: { openOnClick: false, protocols: ['hikki'], isAllowedUri: (url) => isSafeHref(url) },
      codeBlock: false,
      blockquote: false,
      // Hidden while a block is dragged to another block's side (columns.ts draws a vertical line).
      dropcursor: { class: 'hk-dropcursor', width: 2 }
    }),
    CodeBlock,
    Quote,
    // The original page opens where page links send other links.
    Embed.configure({
      host: {
        openExternal: (href) => (options.pageLinks ?? noPageLinks).openExternal(href),
        bff: bffURL(),
        linkPreview: options.linkPreview ?? (async () => null)
      }
    }),
    ...toggleExtensions,
    Callout,
    mathExtension(),
    ...tableExtensions,
    Columns,
    Column,
    ColumnsKeymap,
    Find,
    TableOfContents,
    ...mediaExtensions(options.media ?? null),
    PageLinks(options.pageLinks ?? noPageLinks),
    // "@" mentions a page; ":" suggests emoji.
    PageMention(options.pageLinks ?? noPageLinks),
    SplitDrop(options.splitDrop ?? { mode: () => 'off', open: () => {}, hover: () => {} }),
    AIReview(options.ai ?? { request: () => {}, cancel: () => {}, title: () => '' }),
    AIChanges(options.aiChanges ?? { report: () => {}, focused: () => {} }),
    Comments(options.comments ?? noComments),
    EmojiSuggestion,
    // "--" → —, "..." → …, "->" → →, "(c)" → ©… Quotes stay straight and fractions stay typed (notes, code-ish text, CJK).
    Typography.configure({
      openDoubleQuote: false,
      closeDoubleQuote: false,
      openSingleQuote: false,
      closeSingleQuote: false,
      laquo: false,
      raquo: false,
      oneHalf: false,
      oneQuarter: false,
      threeQuarters: false,
      multiplication: false,
      superscriptTwo: false,
      superscriptThree: false,
      plusMinus: false,
      servicemark: false
    }),
    Ruby(options.ruby ?? null),
    TaskList,
    TaskItem.configure({ nested: true }),
    ColorTextStyle,
    Colors,
    // Keys from the registry: Tiptap's own ⌘, for subscript is Settings on iPad.
    Subscript.extend({
      addKeyboardShortcuts() {
        return { [tiptapShortcut('subscript')]: () => this.editor.commands.toggleSubscript() }
      }
    }),
    Superscript.extend({
      addKeyboardShortcuts() {
        return { [tiptapShortcut('superscript')]: () => this.editor.commands.toggleSuperscript() }
      }
    }),
    BlockShortcuts,
    // Settings → Shortcuts: rebound keys, ahead of every keymap.
    ShortcutOverrides,
    // Words and characters for the inspector (`pageInfo`).
    ImageLoading,
    CharacterCount,
    Placeholder.configure({
      includeChildren: false,
      placeholder: ({ node }) => (node.type.name === 'paragraph' ? t('editor.bodyPlaceholder') : '')
    }),
    EdgeNavigation.configure({ onExitTop: options.onExitTop ?? (() => {}) }),
    SlashCommand,
    SelectionMenuExtension,
    SelectionPaint,
    UniqueID.configure({ types: BLOCK_ID_TYPES }),
    BlockControls
  ]
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
