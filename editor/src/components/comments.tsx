import {
  ArrowUpIcon,
  AtIcon,
  ChatTeardropTextIcon,
  CheckIcon,
  DotsThreeIcon,
  LinkSimpleIcon,
  PencilSimpleIcon,
  TrashIcon,
  XIcon
} from '@phosphor-icons/react'
import type { Editor } from '@tiptap/core'
import { cn } from 'cn'
import i18n from 'i18next'
import { useEffect, useRef, useState, useSyncExternalStore } from 'react'
import { createRoot } from 'react-dom/client'

import { Button } from '@/components/ui/button'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger
} from '@/components/ui/dropdown-menu'
import {
  InputGroup,
  InputGroupAddon,
  InputGroupButton,
  InputGroupInput
} from '@/components/ui/input-group'

import { notify as toast, reportError } from '../core/errors'
import { t } from '../core/i18n'
import {
  commentRanges,
  commentsState,
  type CommentItem,
  type CommentsHost,
  type ThreadItem
} from '../extensions/comments'
import { pageMentionItems } from '../extensions/page-mention'
import {
  bodyFromDraft,
  commentParts,
  draftFromBody,
  mentionQuery,
  type DraftMention
} from '../lib/comment-text'
import { CommandList, handleListKey } from './command-list'

/** Card width in the margin, and the room the margin needs beside the text to hold one. */
const CARD = 300
const GAP = 40
/** The room the outline rail's hover strip keeps at the window's right edge (`editor/src/page/outline.tsx`). */
const RAIL = 64

/** A thread anchored in the page, measured against the text column (the layer's box). */
type Anchor = {
  thread: ThreadItem
  /** Top and bottom of the passage, and its first line's left edge, in the column's coordinates. */
  top: number
  bottom: number
  left: number
  /** The top-level block holding it (threads in one block share a badge). */
  block: number
  blockTop: number
}

type Layout = {
  wide: boolean
  /** Where margin cards start (wide) or badges sit (narrow), from the column's left edge. */
  marginLeft: number
  anchors: Anchor[]
  active: string | null
  draft: { id: string; top: number; bottom: number; left: number; quote: string } | null
}

/**
 * Draws comments in the page: in a wide window every open thread is a card in the right margin, level with its
 * passage (the open one raised, with its reply field; cards that would overlap push down); in a narrow one each
 * block with comments gets a count badge at its right edge and the open thread shows as a card under its passage.
 * A comment being started shows its composer the same way. Mounted inside the text column, so it scrolls with it.
 */
export function renderComments(editor: Editor, host: CommentsHost): () => void {
  const parent = editor.view.dom.parentElement
  if (!parent) return () => {}
  const element = document.createElement('div')
  element.className = 'hk-comments-layer'
  parent.append(element)
  const root = createRoot(element)
  root.render(<CommentsLayer editor={editor} host={host} column={parent} />)
  return () => {
    queueMicrotask(() => root.unmount())
    element.remove()
  }
}

/** The layout's inputs change with every transaction and with the window's size. */
function useLayout(editor: Editor, column: HTMLElement): Layout {
  const cache = useRef<{ key: string; layout: Layout } | null>(null)
  const subscribe = (notify: () => void) => {
    editor.on('transaction', notify)
    window.addEventListener('resize', notify)
    column.addEventListener('hk-relayout', notify)
    return () => {
      editor.off('transaction', notify)
      window.removeEventListener('resize', notify)
      column.removeEventListener('hk-relayout', notify)
    }
  }
  const get = () => {
    const layout = measure(editor, column)
    const key = JSON.stringify(layout, (k, v) =>
      k === 'thread' ? `${v.id}:${v.comments.length}:${v.resolved}` : v
    )
    if (cache.current?.key === key) return cache.current.layout
    cache.current = { key, layout }
    return layout
  }
  return useSyncExternalStore(subscribe, get, get)
}

/**
 * Where comments go beside text ending at `textRight` in a window `viewport` wide, never under the outline rail:
 * cards in the margin when one fits (`wide`), else a badge just right of the text, or just inside it when even that
 * has no room. `offset` is from the text's right edge.
 */
export function marginPlacement(
  viewport: number,
  textRight: number
): { wide: boolean; offset: number } {
  const room = viewport - textRight
  if (room >= CARD + GAP + RAIL) return { wide: true, offset: GAP }
  return { wide: false, offset: room >= 56 + RAIL ? 12 : -44 }
}

function measure(editor: Editor, column: HTMLElement): Layout {
  const empty: Layout = { wide: false, marginLeft: 0, anchors: [], active: null, draft: null }
  if (editor.isDestroyed) return empty
  const plugin = commentsState(editor.state)
  if (!plugin) return empty
  const view = editor.view
  const columnRect = column.getBoundingClientRect()
  const text = view.dom.getBoundingClientRect()
  const { wide, offset } = marginPlacement(window.innerWidth, text.right)
  const at = (pos: number) => {
    try {
      return view.coordsAtPos(Math.min(pos, editor.state.doc.content.size))
    } catch {
      return null
    }
  }
  const anchors: Anchor[] = []
  for (const [id, ranges] of commentRanges(editor.state.doc)) {
    const thread = plugin.threads.get(id)
    const first = ranges[0]
    if (!thread || thread.resolved || !first) continue
    const start = at(first.from)
    const end = at(ranges.at(-1)!.to)
    const $pos = editor.state.doc.resolve(first.from)
    const block = $pos.depth > 0 ? $pos.before(1) : 0
    const blockStart = at(block + 1)
    if (!start || !end || !blockStart) continue
    anchors.push({
      thread,
      top: start.top - columnRect.top,
      bottom: end.bottom - columnRect.top,
      left: start.left - columnRect.left,
      block,
      blockTop: blockStart.top - columnRect.top
    })
  }
  anchors.sort((a, b) => a.top - b.top)
  let draft: Layout['draft'] = null
  if (plugin.draft) {
    const start = at(plugin.draft.from)
    const end = at(plugin.draft.to)
    if (start && end)
      draft = {
        id: plugin.draft.id,
        top: start.top - columnRect.top,
        bottom: end.bottom - columnRect.top,
        left: start.left - columnRect.left,
        quote: editor.state.doc.textBetween(plugin.draft.from, plugin.draft.to, ' ').slice(0, 200)
      }
  }
  return {
    wide,
    // Narrow with no margin at all (a phone's slim one): the badge sits just inside the text's right edge.
    marginLeft: text.right - columnRect.left + offset,
    anchors,
    active: plugin.active,
    draft
  }
}

function CommentsLayer({
  editor,
  host,
  column
}: {
  editor: Editor
  host: CommentsHost
  column: HTMLElement
}) {
  const layout = useLayout(editor, column)
  // A page with open threads makes room for their cards: its column moves left where the window allows (style.css).
  const has = layout.anchors.length > 0 || layout.draft !== null
  useEffect(() => {
    // The whole page (header and body) moves; measured again once it has.
    ;(column.closest('#page') ?? column).toggleAttribute('data-comments', has)
    const frame = requestAnimationFrame(() => column.dispatchEvent(new Event('hk-relayout')))
    return () => cancelAnimationFrame(frame)
  }, [column, has])
  return layout.wide ? (
    <Margin editor={editor} host={host} layout={layout} />
  ) : (
    <Narrow editor={editor} host={host} layout={layout} />
  )
}

/** Wide: a card per thread beside its passage, pushed down where they'd overlap. */
function Margin({ editor, host, layout }: { editor: Editor; host: CommentsHost; layout: Layout }) {
  // Card heights, kept by a ResizeObserver (so stacking knows where each card ends).
  const [heights, setHeights] = useState<Record<string, number>>({})
  const [observer] = useState(
    () =>
      new ResizeObserver((entries) =>
        setHeights((current) => {
          const next = { ...current }
          for (const entry of entries) {
            const id = (entry.target as HTMLElement).dataset.thread
            if (id) next[id] = (entry.target as HTMLElement).offsetHeight
          }
          return next
        })
      )
  )
  useEffect(() => () => observer.disconnect(), [observer])
  const items: { id: string; top: number; node: React.ReactNode }[] = []
  const entries = [
    ...layout.anchors.map((a) => ({ id: a.thread.id, top: a.top, anchor: a })),
    ...(layout.draft ? [{ id: layout.draft.id, top: layout.draft.top, anchor: null }] : [])
  ].toSorted((a, b) => a.top - b.top)
  let bottom = -Infinity
  for (const entry of entries) {
    const top = Math.max(entry.top - 6, bottom + 8)
    bottom = top + (heights[entry.id] ?? 80)
    const active = entry.id === layout.active
    items.push({
      id: entry.id,
      top,
      node: entry.anchor ? (
        <ThreadCard
          editor={editor}
          host={host}
          thread={entry.anchor.thread}
          active={active}
          quote={false}
        />
      ) : (
        <Composer editor={editor} host={host} quote={null} />
      )
    })
  }
  return (
    <>
      {items.map((item) => (
        <div
          key={item.id}
          data-thread={item.id}
          ref={(element) => {
            if (!element) return
            observer.observe(element)
            return () => observer.unobserve(element)
          }}
          className="absolute"
          style={{ left: layout.marginLeft, top: item.top, width: CARD }}
        >
          {item.node}
        </div>
      ))}
    </>
  )
}

/** Narrow: a count badge per block; the open thread (or a new comment) as a card under its passage. */
function Narrow({ editor, host, layout }: { editor: Editor; host: CommentsHost; layout: Layout }) {
  const blocks = new Map<number, Anchor[]>()
  for (const anchor of layout.anchors)
    blocks.set(anchor.block, [...(blocks.get(anchor.block) ?? []), anchor])
  const open = layout.anchors.find((a) => a.thread.id === layout.active)
  const card = open ?? null
  return (
    <>
      {[...blocks.values()].map((anchors) => {
        const count = anchors.reduce((sum, a) => sum + a.thread.comments.length, 0)
        return (
          <Button
            key={anchors[0].block}
            variant="ghost"
            size="xs"
            className="absolute gap-1 bg-muted text-muted-foreground"
            style={{ left: layout.marginLeft, top: anchors[0].blockTop }}
            aria-label={t('comments.count', { count })}
            data-testid="comment-badge"
            onClick={() => editor.commands.commentOpen(anchors[0].thread.id)}
          >
            <ChatTeardropTextIcon className="size-3.5" aria-hidden />
            {count}
          </Button>
        )
      })}
      {card && (
        <div className="absolute z-30" style={popoverStyle(card.left, card.bottom)}>
          <ThreadCard editor={editor} host={host} thread={card.thread} active quote />
        </div>
      )}
      {layout.draft && (
        <div className="absolute z-30" style={popoverStyle(layout.draft.left, layout.draft.bottom)}>
          <Composer editor={editor} host={host} quote={layout.draft.quote} />
        </div>
      )}
    </>
  )
}

/** Under the passage, kept inside the window horizontally. */
function popoverStyle(left: number, bottom: number): React.CSSProperties {
  return {
    left: Math.max(0, Math.min(left - 16, window.innerWidth - 520)),
    top: bottom + 8,
    width: 'min(480px, calc(100vw - 32px))'
  }
}

function Avatar({ name }: { name: string | null }) {
  const letter = (name ?? '').trim().charAt(0).toUpperCase() || '·'
  return (
    <span
      aria-hidden
      className="grid size-7 shrink-0 place-items-center rounded-lg bg-primary text-xs font-bold text-primary-foreground"
    >
      {letter}
    </span>
  )
}

/** "Just now", "5 minutes ago", "yesterday"… in the page's language. */
function when(createdAt: number): string {
  const seconds = (createdAt - Date.now()) / 1000
  if (Math.abs(seconds) < 60) return t('comments.justNow')
  const format = new Intl.RelativeTimeFormat(i18n.language || undefined, { numeric: 'auto' })
  const units: [Intl.RelativeTimeFormatUnit, number][] = [
    ['minute', 60],
    ['hour', 3600],
    ['day', 86_400],
    ['week', 604_800],
    ['month', 2_592_000],
    ['year', 31_536_000]
  ]
  let unit = units[0]
  for (const candidate of units) if (Math.abs(seconds) >= candidate[1]) unit = candidate
  return format.format(Math.round(seconds / unit[1]), unit[0])
}

/** A comment's words, its page mentions drawn as chips (the page's current icon and title; the stored label when this
 * device doesn't know the page). */
function CommentBody({ body, host }: { body: string; host: CommentsHost }) {
  const pages = host.pages()
  return (
    <p className="m-0 text-sm leading-relaxed break-words whitespace-pre-wrap">
      {commentParts(body).map((part, index) => {
        if ('text' in part) return <span key={index}>{part.text}</span>
        const page = pages.find((p) => p.id === part.pageId)
        return (
          <Button
            key={index}
            variant="ghost"
            className="inline h-auto gap-0 rounded-sm px-0.5 py-0 align-baseline text-sm font-medium text-foreground data-[missing=true]:text-muted-foreground"
            data-missing={!page}
            data-testid="comment-mention"
            onClick={(e) => {
              e.stopPropagation()
              if (page) host.openPage(part.pageId)
            }}
          >
            <span aria-hidden className="mr-0.5">
              {page?.icon ?? '📄'}
            </span>
            <span className="underline decoration-muted-foreground underline-offset-2">
              {page ? page.title || t('comments.untitled') : part.label}
            </span>
          </Button>
        )
      })}
    </p>
  )
}

/** One comment: who and when, its words (or, editing, a field), and — on hover in an open thread — its actions:
 * the thread's ✓ on the first comment, then ⋯ (Edit, Copy link to discussion, Delete). */
function CommentRow({
  editor,
  host,
  thread,
  comment,
  first,
  active
}: {
  editor: Editor
  host: CommentsHost
  thread: ThreadItem
  comment: CommentItem
  first: boolean
  active: boolean
}) {
  const [editing, setEditing] = useState(false)
  const [menuOpen, setMenuOpen] = useState(false)
  const other = comment.device && comment.device !== host.device()
  const time = other
    ? t('comments.onDevice', { device: comment.device, when: when(comment.createdAt) })
    : when(comment.createdAt)
  return (
    <div className="group/comment relative flex gap-2.5" data-testid="comment-row">
      <Avatar name={comment.author || t('comments.you')} />
      <div className="flex min-w-0 flex-1 flex-col gap-0.5">
        <div className="flex items-baseline gap-2 pr-16 text-sm">
          <span className="font-semibold">{comment.author || t('comments.you')}</span>
          <span className="text-xs text-muted-foreground">
            {time}
            {comment.editedAt ? ` · ${t('comments.edited')}` : ''}
          </span>
        </div>
        {editing ? (
          <CommentField
            host={host}
            placeholder={t('comments.editPlaceholder')}
            initial={comment.body}
            autoFocus
            onSubmit={(body) => {
              if (body !== comment.body) editor.commands.commentEdit(thread.id, comment.id, body)
              setEditing(false)
            }}
            onCancel={() => setEditing(false)}
          />
        ) : (
          <CommentBody body={comment.body} host={host} />
        )}
      </div>
      {active && !editing && (
        <div
          className={cn(
            'absolute -top-1 right-0 flex gap-0.5 rounded-lg border border-border bg-popover p-0.5 opacity-0 shadow-sm transition-opacity duration-(--motion-pop-in) group-hover/comment:opacity-100 focus-within:opacity-100',
            menuOpen && 'opacity-100'
          )}
        >
          {first && (
            <Button
              variant="ghost"
              size="icon-sm"
              aria-label={t('comments.resolve')}
              title={t('comments.resolve')}
              data-testid="comment-resolve"
              onClick={() => editor.commands.commentResolve(thread.id, true)}
            >
              <CheckIcon className="size-4.5" />
            </Button>
          )}
          <DropdownMenu open={menuOpen} onOpenChange={setMenuOpen}>
            <DropdownMenuTrigger
              render={
                <Button
                  variant="ghost"
                  size="icon-sm"
                  aria-label={t('comments.more')}
                  title={t('comments.more')}
                  data-testid="comment-more"
                />
              }
            >
              <DotsThreeIcon className="size-4.5" weight="bold" />
            </DropdownMenuTrigger>
            <DropdownMenuContent side="bottom" align="end" className="w-56">
              <DropdownMenuItem data-testid="comment-edit" onClick={() => setEditing(true)}>
                <PencilSimpleIcon aria-hidden />
                {t('comments.edit')}
              </DropdownMenuItem>
              <DropdownMenuItem
                onClick={() => {
                  const link = host.link(thread.id)
                  if (!link) return
                  void navigator.clipboard
                    ?.writeText(link)
                    .then(() => toast('success', t('comments.linkCopied')))
                    .catch((error: unknown) => reportError('copyFailed', error))
                }}
              >
                <LinkSimpleIcon aria-hidden />
                {t('comments.copyLink')}
              </DropdownMenuItem>
              <DropdownMenuSeparator />
              <DropdownMenuItem
                variant="destructive"
                data-testid="comment-delete"
                onClick={() =>
                  first
                    ? editor.commands.commentDelete(thread.id)
                    : editor.commands.commentDeleteReply(thread.id, comment.id)
                }
              >
                <TrashIcon aria-hidden />
                {first ? t('comments.deleteThread') : t('comments.delete')}
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        </div>
      )}
    </div>
  )
}

/** A thread: its comments and a reply field when open; collapsed in the margin, its first comment. */
function ThreadCard({
  editor,
  host,
  thread,
  active,
  quote
}: {
  editor: Editor
  host: CommentsHost
  thread: ThreadItem
  active: boolean
  quote: boolean
}) {
  const shown = active ? thread.comments : thread.comments.slice(0, 1)
  return (
    <section
      className={cn(
        'hk-pop flex flex-col gap-3 rounded-xl border p-3 text-popover-foreground',
        active
          ? 'border-border bg-popover shadow-popover'
          : 'cursor-pointer border-border/70 bg-transparent'
      )}
      data-testid="comment-thread"
      onMouseDown={(e) => {
        if (!(e.target as HTMLElement).closest('input, textarea, button, [role=menuitem]'))
          e.preventDefault()
      }}
      onClick={() => {
        if (!active) editor.commands.commentOpen(thread.id)
      }}
    >
      {quote && thread.quote && (
        <span className="border-l-2 border-ink-yellow pl-2.5 text-xs text-muted-foreground">
          {thread.quote}
        </span>
      )}
      <div className="flex flex-col gap-3">
        {shown.map((comment, index) => (
          <CommentRow
            key={comment.id}
            editor={editor}
            host={host}
            thread={thread}
            comment={comment}
            first={index === 0}
            active={active}
          />
        ))}
      </div>
      {!active && thread.comments.length > 1 && (
        <span className="text-xs text-muted-foreground">
          {t('comments.replies', { count: thread.comments.length - 1 })}
        </span>
      )}
      {active && (
        <CommentField
          host={host}
          placeholder={t('comments.reply')}
          onSubmit={(body) => editor.commands.commentSend(body)}
          onCancel={() => {
            editor.commands.commentOpen(null)
            editor.commands.focus()
          }}
        />
      )}
    </section>
  )
}

/** A new comment on the selection: what it is about, then the field. */
function Composer({
  editor,
  host,
  quote
}: {
  editor: Editor
  host: CommentsHost
  quote: string | null
}) {
  return (
    <section
      className="hk-pop flex flex-col gap-2.5 rounded-xl border border-border bg-popover p-3 text-popover-foreground shadow-popover"
      data-testid="comment-composer"
    >
      {quote && (
        <span className="border-l-2 border-primary pl-2.5 text-xs text-muted-foreground">
          {quote}
        </span>
      )}
      <CommentField
        host={host}
        placeholder={t('comments.add')}
        autoFocus
        onSubmit={(body) => editor.commands.commentSend(body)}
        onCancel={() => {
          editor.commands.commentOpen(null)
          editor.commands.focus()
        }}
      />
    </section>
  )
}

/**
 * The comment field (new comment, reply, edit): Return sends, Escape cancels; "@" (typed, or the @ button) lists
 * pages, and a picked one goes in as "@Title" and is stored as a mention (`lib/comment-text.ts`). Editing, it ends
 * with cancel / save instead of send.
 */
function CommentField({
  host,
  placeholder,
  initial,
  autoFocus = false,
  onSubmit,
  onCancel
}: {
  host: CommentsHost
  placeholder: string
  /** A stored comment being edited. */
  initial?: string
  autoFocus?: boolean
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
          className="hk-pop absolute top-full left-0 z-40 mt-1 max-h-72 w-72 overflow-y-auto rounded-xl bg-popover shadow-popover"
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
