import { mergeAttributes } from '@tiptap/core'
import Mention from '@tiptap/extension-mention'
import { PluginKey } from '@tiptap/pm/state'
import { findSuggestionMatch } from '@tiptap/suggestion'

import { dateMenuIcon } from '../components/date-chip'
import { t } from '../core/i18n'
import {
  dateLabel,
  dateLong,
  datePrefix,
  parseDateQuery,
  remindLabel,
  type DateValue
} from '../lib/dates'
import { pageLinkHref, type PageIndexEntry, type PageLinksHost } from './page-links'
import { suggestionMenu } from './suggestion-menu'

export const PageMentionKey = new PluginKey('pageMention')

/** How many pages the "@" menu lists. */
const MAX_ITEMS = 8

/** Pages for "@query": title prefix matches first, then anywhere in the title; index order within each. */
export function pageMentionItems(
  pages: PageIndexEntry[],
  query: string,
  untitled: string
): PageIndexEntry[] {
  const q = query.trim().toLowerCase()
  if (!q) return pages.slice(0, MAX_ITEMS)
  const title = (p: PageIndexEntry) => (p.title || untitled).toLowerCase()
  const prefix = pages.filter((p) => title(p).startsWith(q))
  const rest = pages.filter((p) => !title(p).startsWith(q) && title(p).includes(q))
  return [...prefix, ...rest].slice(0, MAX_ITEMS)
}

/** A row of the "@" menu: a date (with a reminder, or not), or a page. */
export type MentionItem =
  | { kind: 'date'; id: string; value: DateValue; remind: boolean }
  | { kind: 'page'; id: string; page: PageIndexEntry }

const dateItem = (value: DateValue, remind: boolean): MentionItem => ({
  kind: 'date',
  id: `date-${remind ? 'remind' : 'day'}-${value.date}-${value.time ?? ''}`,
  value,
  remind
})

/**
 * The dates "@query" offers above the pages: with nothing typed, Today, Tomorrow and a reminder tomorrow; else the
 * date the words read as ("fri 3pm", "明天", "来週の金曜") and a reminder on it — none when they aren't a date.
 */
export function dateMentionItems(query: string, now = new Date()): MentionItem[] {
  const q = query.trim()
  if (!q) {
    const today = parseDateQuery('today', now)!
    const tomorrow = parseDateQuery('tomorrow', now)!
    return [dateItem(today, false), dateItem(tomorrow, false), dateItem(tomorrow, true)]
  }
  const value = parseDateQuery(q, now)
  if (!value) return []
  return [dateItem(value, false), dateItem(value, true)]
}

/** Mention chips redraw when the sidebar's pages change (a rename, a new icon, a deletion). */
const pageIndexChanged = new EventTarget()
export function notifyPageIndexChanged(): void {
  pageIndexChanged.dispatchEvent(new Event('change'))
}

/**
 * "@" mentions a page (Tiptap's Mention): an inline chip with the page's icon and current title — the stored label is
 * only the fallback for a page this device doesn't know (deleted, or not synced yet) and for plain text. The chip is a
 * `hikki://page/<id>` link, so page links' click handling opens it; copied out, it's that link.
 */
export function PageMention(host: PageLinksHost) {
  const entry = (id: string | null) => host.pages().find((p) => p.id === id) ?? null
  const titleOf = (p: PageIndexEntry) => p.title || host.untitled()

  return Mention.extend({
    // Our own copies (`<a data-type="mention">`, ahead of the link mark's `a[href]`) and Tiptap's `<span>`.
    parseHTML() {
      return [
        { tag: 'a[data-type="mention"]', priority: 100 },
        { tag: 'span[data-type="mention"]' }
      ]
    },

    addNodeView() {
      return ({ node: initial, HTMLAttributes }) => {
        let node = initial
        const dom = document.createElement('a')
        for (const [name, value] of Object.entries(
          mergeAttributes(HTMLAttributes, { class: 'hk-mention', contenteditable: 'false' })
        )) {
          if (value !== null && value !== undefined) dom.setAttribute(name, String(value))
        }
        const icon = document.createElement('span')
        icon.className = 'hk-mention-icon'
        icon.setAttribute('aria-hidden', 'true')
        const title = document.createElement('span')
        title.className = 'hk-mention-title'
        dom.append(icon, title)

        const draw = () => {
          const page = entry(node.attrs.id)
          dom.setAttribute('href', pageLinkHref(node.attrs.id ?? ''))
          dom.dataset.missing = page ? 'false' : 'true'
          icon.textContent = page?.icon ?? '📄'
          title.textContent = page ? titleOf(page) : (node.attrs.label ?? host.untitled())
        }
        draw()
        pageIndexChanged.addEventListener('change', draw)

        return {
          dom,
          update: (next) => {
            if (next.type !== node.type) return false
            node = next
            draw()
            return true
          },
          ignoreMutation: () => true,
          destroy: () => pageIndexChanged.removeEventListener('change', draw)
        }
      }
    }
  }).configure({
    renderText: ({ node }) =>
      `@${entry(node.attrs.id)?.title || node.attrs.label || host.untitled()}`,
    renderHTML: ({ options, node }) => [
      'a',
      mergeAttributes(options.HTMLAttributes, { href: pageLinkHref(node.attrs.id ?? '') }),
      `@${node.attrs.label ?? ''}`
    ],
    suggestion: {
      char: '@',
      pluginKey: PageMentionKey,
      allow: ({ state, range }) => {
        const $from = state.doc.resolve(range.from)
        return (
          !$from.parent.type.spec.code &&
          !!$from.parent.type.contentMatch.matchType(state.schema.nodes.mention)
        )
      },
      // A space may stay in what's typed while it still reads as a date ("@next fri 3pm").
      findSuggestionMatch: (config) => {
        const wide = findSuggestionMatch({ ...config, allowSpaces: true })
        if (wide && /\s/u.test(wide.query.trim()) && datePrefix(wide.query)) return wide
        return findSuggestionMatch({ ...config, allowSpaces: false })
      },
      items: ({ query }): MentionItem[] => [
        ...dateMentionItems(query),
        ...pageMentionItems(host.pages(), query, host.untitled()).map((page): MentionItem => ({
          kind: 'page',
          id: page.id,
          page
        }))
      ],
      command: ({ editor, range, props }) => {
        const item = props as unknown as MentionItem
        if (item.kind === 'date') {
          editor.commands.insertDateMention(range, {
            ...item.value,
            remind: item.remind ? 0 : null
          })
          return
        }
        const { page } = item
        editor
          .chain()
          .focus()
          .insertContentAt(range, [
            {
              type: 'mention',
              attrs: { id: page.id, label: titleOf(page), mentionSuggestionChar: '@' }
            },
            { type: 'text', text: ' ' }
          ])
          .run()
      },
      render: suggestionMenu<MentionItem>(
        PageMentionKey,
        'hk-mention-menu',
        (item) =>
          item.kind === 'page'
            ? {
                id: item.page.id,
                title: titleOf(item.page),
                icon: item.page.icon ?? '📄',
                group: t('mention.pages')
              }
            : {
                id: item.id,
                title: item.remind
                  ? t('date.remindMe', { when: dateLabel(item.value) })
                  : dateLabel(item.value),
                hint: item.remind ? remindLabel(0, item.value.time !== null) : dateLong(item.value),
                icon: dateMenuIcon(item.remind),
                group: t('date.group')
              },
        () => t('mention.empty')
      )
    }
  })
}
