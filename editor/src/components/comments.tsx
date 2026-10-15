import {
  ArrowUpIcon,
  ChatTeardropTextIcon,
  CheckCircleIcon,
  TrashIcon
} from '@phosphor-icons/react'
import type { Editor } from '@tiptap/core'
import { cn } from 'cn'
import i18n from 'i18next'
import { useEffect, useRef, useState, useSyncExternalStore } from 'react'
import { createRoot } from 'react-dom/client'

import { Button } from '@/components/ui/button'
import {
  InputGroup,
  InputGroupAddon,
  InputGroupButton,
  InputGroupInput
} from '@/components/ui/input-group'

import { t } from '../core/i18n'
import {
  commentRanges,
  commentsState,
  type CommentItem,
  type CommentsHost,
  type ThreadItem
} from '../extensions/comments'

/** Card width in the margin, and the room the margin needs beside the text to hold one. */
const CARD = 300
const GAP = 40

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

function measure(editor: Editor, column: HTMLElement): Layout {
  const empty: Layout = { wide: false, marginLeft: 0, anchors: [], active: null, draft: null }
  if (editor.isDestroyed) return empty
  const plugin = commentsState(editor.state)
  if (!plugin) return empty
  const view = editor.view
  const columnRect = column.getBoundingClientRect()
  const text = view.dom.getBoundingClientRect()
  const wide = window.innerWidth - text.right >= CARD + GAP + 16
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
    marginLeft:
      text.right - columnRect.left + (wide ? GAP : window.innerWidth - text.right >= 56 ? 12 : -44),
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
        <Composer editor={editor} quote={null} />
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
            <ChatTeardropTextIcon aria-hidden />
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
          <Composer editor={editor} quote={layout.draft.quote} />
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

function CommentRow({ comment, host }: { comment: CommentItem; host: CommentsHost }) {
  const other = comment.device && comment.device !== host.device()
  return (
    <div className="flex gap-2.5">
      <Avatar name={comment.author || t('comments.you')} />
      <div className="flex min-w-0 flex-1 flex-col gap-0.5">
        <div className="flex items-baseline gap-2 text-sm">
          <span className="font-semibold">{comment.author || t('comments.you')}</span>
          <span className="text-xs text-muted-foreground">
            {other
              ? t('comments.onDevice', { device: comment.device, when: when(comment.createdAt) })
              : when(comment.createdAt)}
          </span>
        </div>
        <p className="m-0 text-sm leading-relaxed whitespace-pre-wrap">{comment.body}</p>
      </div>
    </div>
  )
}

/** A thread: its comments; open, also resolve / delete and a reply field. Collapsed in the margin: its first comment. */
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
        if (!(e.target as HTMLElement).closest('input, button')) e.preventDefault()
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
      <div className="flex gap-1">
        <div className="flex min-w-0 flex-1 flex-col gap-3">
          {shown.map((comment) => (
            <CommentRow key={comment.id} comment={comment} host={host} />
          ))}
        </div>
        {active && (
          <div className="flex shrink-0 gap-0.5">
            <Button
              variant="ghost"
              size="icon-xs"
              aria-label={t('comments.resolve')}
              title={t('comments.resolve')}
              data-testid="comment-resolve"
              onClick={() => editor.commands.commentResolve(thread.id, true)}
            >
              <CheckCircleIcon />
            </Button>
            <Button
              variant="ghost"
              size="icon-xs"
              aria-label={t('comments.delete')}
              title={t('comments.delete')}
              onClick={() => editor.commands.commentDelete(thread.id)}
            >
              <TrashIcon />
            </Button>
          </div>
        )}
      </div>
      {!active && thread.comments.length > 1 && (
        <span className="text-xs text-muted-foreground">
          {t('comments.replies', { count: thread.comments.length - 1 })}
        </span>
      )}
      {active && <ReplyField editor={editor} placeholder={t('comments.reply')} />}
    </section>
  )
}

/** A new comment on the selection: what it is about, then the field. */
function Composer({ editor, quote }: { editor: Editor; quote: string | null }) {
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
      <ReplyField editor={editor} placeholder={t('comments.add')} autoFocus />
    </section>
  )
}

function ReplyField({
  editor,
  placeholder,
  autoFocus = false
}: {
  editor: Editor
  placeholder: string
  autoFocus?: boolean
}) {
  const [value, setValue] = useState('')
  const send = () => {
    if (value.trim() && editor.commands.commentSend(value)) setValue('')
  }
  return (
    <InputGroup className="h-9 shadow-none">
      <InputGroupInput
        // oxlint-disable-next-line jsx-a11y/no-autofocus -- a new comment opens to be typed
        autoFocus={autoFocus}
        className="md:text-sm"
        placeholder={placeholder}
        aria-label={placeholder}
        data-testid="comment-field"
        value={value}
        onChange={(e) => setValue(e.target.value)}
        onKeyDown={(e) => {
          if (e.nativeEvent.isComposing) return
          e.stopPropagation()
          if (e.key === 'Enter') {
            e.preventDefault()
            send()
          } else if (e.key === 'Escape') {
            e.preventDefault()
            editor.commands.commentOpen(null)
            editor.commands.focus()
          }
        }}
      />
      <InputGroupAddon align="inline-end">
        <InputGroupButton
          size="icon-xs"
          aria-label={t('comments.send')}
          disabled={!value.trim()}
          onClick={send}
        >
          <ArrowUpIcon aria-hidden />
        </InputGroupButton>
      </InputGroupAddon>
    </InputGroup>
  )
}
