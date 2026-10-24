import { cn } from 'cn'
import { useRef, useState } from 'react'

import {
  InputGroup,
  InputGroupAddon,
  InputGroupButton,
  InputGroupInput
} from '@/components/ui/input-group'

import { t } from '../core/i18n'
import { type CommentsHost } from '../extensions/comments'
import { pageMentionItems } from '../extensions/page-mention'
import { ArrowUpIcon, AtIcon, CheckIcon, XIcon } from '../generated/icons'
import { bodyFromDraft, draftFromBody, mentionQuery, type DraftMention } from '../lib/comment-text'
import { CommandList, handleListKey } from './command-list'

/**
 * The comment field (new comment, reply, edit): Return sends, Escape cancels; "@" (typed, or the @ button) lists
 * pages, and a picked one goes in as "@Title" and is stored as a mention (`lib/comment-text.ts`). Editing, it ends
 * with cancel / save instead of send.
 */
export function CommentField({
  host,
  placeholder,
  initial,
  autoFocus = false,
  onSubmit,
  onCancel,
  listAbove = false
}: {
  host: CommentsHost
  placeholder: string
  /** A stored comment being edited. */
  initial?: string
  autoFocus?: boolean
  /** The "@" page list opens above the field (at a sheet's foot there is no room below). */
  listAbove?: boolean
  /** Returns false to keep the text (nothing was sent). */
  onSubmit: (body: string) => boolean | void
  onCancel: () => void
}) {
  const start = initial === undefined ? { text: '', mentions: [] } : draftFromBody(initial)
  const [value, setValue] = useState(start.text)
  const [mentions, setMentions] = useState<DraftMention[]>(start.mentions)
  const [query, setQuery] = useState<{ start: number; query: string } | null>(null)
  const [selected, setSelected] = useState(0)
  const inputRef = useRef<HTMLInputElement>(null)
  const items = query
    ? pageMentionItems(host.pages(), query.query, t('comments.untitled')).map((p) => ({
        id: p.id,
        title: p.title || t('comments.untitled'),
        icon: p.icon ?? '📄'
      }))
    : []

  const readQuery = (text: string) => {
    const caret = inputRef.current?.selectionStart ?? text.length
    let next = mentionQuery(text, caret)
    // A page already picked there ("@Kyoto in spring ") is not a new query…
    if (next && mentions.some((m) => text.startsWith(`@${m.label}`, next!.start))) next = null
    // …and one that runs past a space without matching anything has ended.
    if (next && /\s/.test(next.query)) {
      const found = pageMentionItems(host.pages(), next.query, t('comments.untitled'))
      if (found.length === 0) next = null
    }
    setQuery(next)
    if (next?.query !== query?.query) setSelected(0)
  }
  const choose = (index: number) => {
    const item = items[index]
    if (!item || !query) return
    const caret = inputRef.current?.selectionStart ?? value.length
    const inserted = `@${item.title} `
    const text = value.slice(0, query.start) + inserted + value.slice(caret)
    setValue(text)
    setMentions((list) => [...list, { label: item.title, pageId: item.id }])
    setQuery(null)
    const at = query.start + inserted.length
    requestAnimationFrame(() => inputRef.current?.setSelectionRange(at, at))
  }
  const submit = () => {
    if (!value.trim()) return
    if (onSubmit(bodyFromDraft(value, mentions)) === false) return
    if (initial === undefined) {
      setValue('')
      setMentions([])
    }
  }
  const startMention = () => {
    const input = inputRef.current
    const caret = input?.selectionStart ?? value.length
    const gap = caret > 0 && !/\s/.test(value[caret - 1]) ? ' ' : ''
    const text = value.slice(0, caret) + gap + '@' + value.slice(caret)
    setValue(text)
    const at = caret + gap.length + 1
    setQuery({ start: at - 1, query: '' })
    setSelected(0)
    requestAnimationFrame(() => {
      input?.focus()
      input?.setSelectionRange(at, at)
    })
  }

  return (
    <div className="relative">
      <InputGroup className="h-9 shadow-none">
        <InputGroupInput
          ref={inputRef}
          // oxlint-disable-next-line jsx-a11y/no-autofocus -- a new comment (or an edit) opens to be typed
          autoFocus={autoFocus}
          className="md:text-sm"
          placeholder={placeholder}
          aria-label={placeholder}
          data-testid="comment-field"
          value={value}
          onChange={(e) => {
            setValue(e.target.value)
            readQuery(e.target.value)
          }}
          onBlur={() => setQuery(null)}
          onKeyDown={(e) => {
            if (e.nativeEvent.isComposing) return
            e.stopPropagation()
            if (
              query &&
              items.length > 0 &&
              handleListKey(e.key, items.length, selected, setSelected, choose)
            ) {
              e.preventDefault()
              return
            }
            if (e.key === 'Enter') {
              e.preventDefault()
              submit()
            } else if (e.key === 'Escape') {
              e.preventDefault()
              if (query) setQuery(null)
              else onCancel()
            }
          }}
        />
        <InputGroupAddon align="inline-end">
          <InputGroupButton
            size="icon-xs"
            aria-label={t('comments.mention')}
            title={t('comments.mention')}
            data-testid="comment-mention-button"
            onMouseDown={(e) => e.preventDefault()}
            onClick={startMention}
          >
            <AtIcon className="size-4" aria-hidden />
          </InputGroupButton>
          {initial === undefined ? (
            <InputGroupButton
              size="icon-xs"
              aria-label={t('comments.send')}
              disabled={!value.trim()}
              onClick={submit}
            >
              <ArrowUpIcon className="size-4" weight="bold" aria-hidden />
            </InputGroupButton>
          ) : (
            <>
              <InputGroupButton size="icon-xs" aria-label={t('comments.cancel')} onClick={onCancel}>
                <XIcon className="size-4" aria-hidden />
              </InputGroupButton>
              <InputGroupButton
                size="icon-xs"
                aria-label={t('comments.save')}
                data-testid="comment-save"
                disabled={!value.trim()}
                onClick={submit}
              >
                <CheckIcon className="size-4" weight="bold" aria-hidden />
              </InputGroupButton>
            </>
          )}
        </InputGroupAddon>
      </InputGroup>
      {query && (
        <div
          className={cn(
            'hk-pop absolute left-0 z-40 max-h-72 w-72 overflow-y-auto rounded-xl bg-popover shadow-popover',
            listAbove ? 'bottom-full mb-1' : 'top-full mt-1'
          )}
          data-above={listAbove || undefined}
          data-testid="comment-mention-list"
        >
          <CommandList
            items={items}
            selectedIndex={selected}
            emptyText={t('comments.noPages')}
            onSelect={choose}
            onHover={setSelected}
          />
        </div>
      )}
    </div>
  )
}
