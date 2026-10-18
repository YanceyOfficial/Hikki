import { Extension } from '@tiptap/core'
import { PluginKey } from '@tiptap/pm/state'
import Suggestion from '@tiptap/suggestion'

import i18n, { t } from '../core/i18n'
import {
  loadEmojiCategories,
  recentEmoji,
  rememberEmoji,
  searchEmoji,
  type EmojiCategory,
  type EmojiEntry
} from '../lib/emoji-data'
import { suggestionMenu } from './suggestion-menu'

export const EmojiSuggestionKey = new PluginKey('emojiSuggestion')

/** How many emoji the ":" menu lists. */
const MAX_ITEMS = 8

/** ":query" → emoji: recents for a bare ":", else the picker's search (labels in the app's language + English). */
export function emojiItems(
  categories: EmojiCategory[],
  query: string,
  recent: string[]
): EmojiEntry[] {
  if (query.trim()) return searchEmoji(categories, query, MAX_ITEMS)
  const all = categories.flatMap((c) => c.emojis)
  return recent
    .map((emoji) => all.find((e) => e.emoji === emoji))
    .filter((e): e is EmojiEntry => e !== undefined)
    .slice(0, MAX_ITEMS)
}

/**
 * ":" after a space or at a line's start suggests emoji (Notion's), on Tiptap's Suggestion utility with the icon
 * picker's localized emojibase data. The pick goes in as a plain character — not Tiptap's Emoji node, which rewrites
 * every emoji in a page into nodes (a format older Hikki can't open).
 */
export const EmojiSuggestion = Extension.create({
  name: 'emojiSuggestion',

  addProseMirrorPlugins() {
    return [
      Suggestion<EmojiEntry, EmojiEntry>({
        editor: this.editor,
        pluginKey: EmojiSuggestionKey,
        char: ':',
        allow: ({ state, range }) => !state.doc.resolve(range.from).parent.type.spec.code,
        items: async ({ query }) => {
          try {
            const categories = await loadEmojiCategories(
              i18n.language.startsWith('zh') ? 'zh' : 'en'
            )
            return emojiItems(categories, query, recentEmoji())
          } catch {
            return []
          }
        },
        command: ({ editor, range, props }) => {
          editor.chain().focus().insertContentAt(range, props.emoji).run()
          rememberEmoji(props.emoji)
        },
        render: suggestionMenu<EmojiEntry>(
          EmojiSuggestionKey,
          'hk-emoji-menu',
          (e) => ({ id: e.hexcode, title: e.label, icon: e.emoji }),
          () => t('emoji.empty'),
          { hideWhenEmpty: true }
        )
      })
    ]
  }
})
