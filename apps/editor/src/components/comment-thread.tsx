import type { Editor } from '@tiptap/core'
import { cn } from 'cn'
import i18n from 'i18next'
import { useState } from 'react'

import { Button } from '@/components/ui/button'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger
} from '@/components/ui/dropdown-menu'

import { notify as toast, reportError } from '../core/errors'
import { t } from '../core/i18n'
import { type CommentItem, type CommentsHost, type ThreadItem } from '../extensions/comments'
import {
  CheckIcon,
  DotsThreeIcon,
  LinkSimpleIcon,
  PencilSimpleIcon,
  TrashIcon
} from '../generated/icons'
import { commentParts } from '../lib/comment-text'
import { CommentField } from './comment-field'

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
  active,
  sheet = false
}: {
  editor: Editor
  host: CommentsHost
  thread: ThreadItem
  comment: CommentItem
  first: boolean
  active: boolean
  /** In a phone's sheet: no hover there, so the actions always show. */
  sheet?: boolean
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
            'absolute right-0 flex gap-0.5',
            sheet
              ? '-top-1.5 text-muted-foreground'
              : '-top-1 rounded-lg border border-border bg-popover p-0.5 opacity-0 shadow-sm transition-opacity duration-(--motion-pop-in) group-hover/comment:opacity-100 focus-within:opacity-100',
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
export function ThreadCard({
  editor,
  host,
  thread,
  active,
  quote,
  onClose,
  sheet = false
}: {
  editor: Editor
  host: CommentsHost
  thread: ThreadItem
  active: boolean
  quote: boolean
  /** Escape in the reply field: by default the thread closes and the page takes the caret back. */
  onClose?: () => void
  /** In a phone's sheet: the quote, the comments scrolling under it, the reply field at the foot. */
  sheet?: boolean
}) {
  const shown = active ? thread.comments : thread.comments.slice(0, 1)
  const close =
    onClose ??
    (() => {
      editor.commands.commentOpen(null)
      editor.commands.focus()
    })
  if (sheet)
    return (
      <section className="flex min-h-0 flex-1 flex-col" data-testid="comment-thread">
        {quote && thread.quote && (
          <span className="mx-4 mt-2 line-clamp-3 shrink-0 border-l-2 border-ink-yellow pl-2.5 text-sm text-muted-foreground">
            {thread.quote}
          </span>
        )}
        <div className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto overscroll-contain px-4 py-4">
          {thread.comments.map((comment, index) => (
            <CommentRow
              key={comment.id}
              editor={editor}
              host={host}
              thread={thread}
              comment={comment}
              first={index === 0}
              active
              sheet
            />
          ))}
        </div>
        <div className="shrink-0 border-t border-border px-4 pt-3">
          <CommentField
            host={host}
            placeholder={t('comments.reply')}
            onSubmit={(body) => editor.commands.commentSend(body)}
            onCancel={close}
            listAbove
          />
        </div>
      </section>
    )
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
          onCancel={close}
        />
      )}
    </section>
  )
}

/** A new comment on the selection: what it is about, then the field. */
export function Composer({
  editor,
  host,
  quote,
  onClose,
  sheet = false
}: {
  editor: Editor
  host: CommentsHost
  quote: string | null
  /** Escape: by default the draft is dropped and the page takes the caret back. */
  onClose?: () => void
  /** In a phone's sheet: no card of its own. */
  sheet?: boolean
}) {
  return (
    <section
      className={cn(
        'flex flex-col gap-2.5 text-popover-foreground',
        sheet ? 'px-4 pt-2' : 'hk-pop rounded-xl border border-border bg-popover p-3 shadow-popover'
      )}
      data-testid="comment-composer"
    >
      {quote && (
        <span
          className={cn(
            'border-l-2 border-primary pl-2.5 text-muted-foreground',
            sheet ? 'line-clamp-3 text-sm' : 'text-xs'
          )}
        >
          {quote}
        </span>
      )}
      <CommentField
        host={host}
        placeholder={t('comments.add')}
        autoFocus
        onSubmit={(body) => editor.commands.commentSend(body)}
        onCancel={
          onClose ??
          (() => {
            editor.commands.commentOpen(null)
            editor.commands.focus()
          })
        }
        listAbove={sheet}
      />
    </section>
  )
}
