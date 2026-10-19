import {
  ArrowClockwiseIcon,
  ArrowUpIcon,
  CheckIcon,
  CopyIcon,
  GlobeIcon,
  TextAlignLeftIcon
} from '@phosphor-icons/react'
import { useEffect, useLayoutEffect, useRef, useState } from 'react'

import { Button } from '@/components/ui/button'
import {
  InputGroup,
  InputGroupAddon,
  InputGroupButton,
  InputGroupInput
} from '@/components/ui/input-group'
import { Kbd } from '@/components/ui/kbd'

import { markdownDOM } from '../core/convert'
import { t } from '../core/i18n'
import type { AIReviewStyle } from '../extensions/ai-review'
import { DiffReview, type AIReviewLine } from './ai-review-styles'
import type { FloatingAnchor, FloatingLayer } from './floating'

export type AIReviewProps = {
  session: {
    status: 'thinking' | 'review' | 'answer' | 'error'
    answer: boolean
    reply: string
    searching: string | null
    citations: { url: string; title?: string | null }[]
    error: { code: string; provider?: string | null; message?: string | null } | null
    /** For edits: how many separate changes there are. */
    changes: number
    style: AIReviewStyle
    /** Each unit's diff (style B draws them in the bar). */
    lines: AIReviewLine[]
    /** What the model says to the user beside an edit (Markdown each), and which of them are in the page already. */
    notes: string[]
    inserted: number[]
    /** The edit was accepted; its notes stay open. */
    accepted: boolean
  }
  onAccept: () => void
  onDiscard: () => void
  onRetry: () => void
  onFollowUp: (instruction: string) => void
  onInsertBelow: () => void
  /** Puts note `index` into the page below the selection (the review stays open). */
  onInsertNote: (index: number) => void
  /** Copies `text`, or the answer. */
  onCopy: (text?: string) => void
}

/** The three dots of AI at work (the one loading shimmer's timing, `--motion-loop`). */
function Working({ label }: { label: string }) {
  return (
    <div className="flex min-w-0 items-center gap-2 text-sm text-muted-foreground" role="status">
      <span className="hk-ai-dots" aria-hidden>
        <span />
        <span />
        <span />
      </span>
      <span className="truncate">{label}</span>
    </div>
  )
}

/** The answer's Markdown, drawn with the page's own blocks (`markdownDOM`: built from the schema, never as HTML). */
function MarkdownAnswer({ text }: { text: string }) {
  const ref = useRef<HTMLDivElement>(null)
  useLayoutEffect(() => {
    ref.current?.replaceChildren(markdownDOM(text))
  }, [text])
  return (
    <div
      ref={ref}
      className="hk-ai-answer max-h-[min(360px,50vh)] overflow-y-auto overscroll-contain px-1 text-sm leading-relaxed"
      data-testid="ai-answer"
    />
  )
}

/** A note's "Copied" lasts this long. */
const COPIED_MS = 1500

/**
 * The edit's notes — what the model says rather than writes into the page (a verdict, an answer, an explanation) — in a
 * card of their own: each drawn as page blocks, with Copy and Insert below (the user may keep it as notes).
 */
function NotesCard({
  notes,
  inserted,
  onCopy,
  onInsert
}: {
  notes: string[]
  inserted: number[]
  onCopy: (text: string) => void
  onInsert: (index: number) => void
}) {
  const [copied, setCopied] = useState<number | null>(null)
  // "Copied" for a moment, as the code block's Copy says it.
  useEffect(() => {
    if (copied === null) return
    const timer = setTimeout(() => setCopied(null), COPIED_MS)
    return () => clearTimeout(timer)
  }, [copied])
  return (
    <section
      className="flex flex-col gap-1 rounded-lg border border-border bg-muted/40 p-1.5"
      aria-label={t('ai.notes')}
      data-testid="ai-notes"
    >
      {notes.map((note, index) => (
        <div
          key={index}
          className="flex flex-col gap-1 not-first:border-t not-first:border-border not-first:pt-1.5"
          data-testid="ai-note"
        >
          <MarkdownAnswer text={note} />
          <div className="flex items-center justify-end gap-1">
            <Button
              variant="ghost"
              size="xs"
              onClick={() => {
                onCopy(note)
                setCopied(index)
              }}
            >
              {copied === index ? <CheckIcon aria-hidden /> : <CopyIcon aria-hidden />}
              {copied === index ? t('ai.copied') : t('ai.copy')}
            </Button>
            <Button
              variant="ghost"
              size="xs"
              disabled={inserted.includes(index)}
              onClick={() => onInsert(index)}
              data-testid="ai-note-insert"
            >
              {inserted.includes(index) ? (
                <CheckIcon aria-hidden />
              ) : (
                <TextAlignLeftIcon aria-hidden />
              )}
              {inserted.includes(index) ? t('ai.inserted') : t('ai.insertBelow')}
            </Button>
          </div>
        </div>
      ))}
    </section>
  )
}

/** "Ask for a change…": a follow-up instruction for the edit or the answer. */
function FollowUp({
  placeholder,
  onSubmit
}: {
  placeholder: string
  onSubmit: (text: string) => void
}) {
  const [value, setValue] = useState('')
  const submit = () => {
    const text = value.trim()
    if (text) onSubmit(text)
  }
  return (
    <InputGroup className="h-8 shadow-none">
      <InputGroupInput
        className="md:text-sm"
        placeholder={placeholder}
        aria-label={placeholder}
        value={value}
        onChange={(e) => setValue(e.target.value)}
        onKeyDown={(e) => {
          if (e.nativeEvent.isComposing) return
          e.stopPropagation()
          if (e.key === 'Enter') {
            e.preventDefault()
            submit()
          }
        }}
      />
      <InputGroupAddon align="inline-end">
        <InputGroupButton
          size="icon-xs"
          aria-label={t('ai.send')}
          disabled={!value.trim()}
          onClick={submit}
        >
          <ArrowUpIcon aria-hidden />
        </InputGroupButton>
      </InputGroupAddon>
    </InputGroup>
  )
}

function errorText(error: NonNullable<AIReviewProps['session']['error']>): string {
  switch (error.code) {
    case 'missingKey':
      return t('ai.error.missingKey', { provider: error.provider ?? '' })
    case 'badBaseURL':
      return t('ai.error.badBaseURL', { provider: error.provider ?? '' })
    case 'unauthorized':
      return t('ai.error.unauthorized')
    case 'rateLimited':
      return t('ai.error.rateLimited')
    case 'unavailable':
      return t('ai.error.unavailable')
    case 'offline':
      return t('ai.error.offline')
    case 'rejected':
      return error.message
        ? t('ai.error.rejectedWith', { message: error.message })
        : t('ai.error.rejected')
    case 'mediaUnreadable':
      return t('ai.error.mediaUnreadable')
    default:
      return t('ai.error.invalidResponse')
  }
}

/**
 * Under the selection while AI works on it: a working line, then — for an edit — the change count, a follow-up field
 * and Retry / Discard / Accept (style A draws the edit in the page, style B as − / + lines here), and the model's notes
 * in a card below; for an answer, a card with the text as it streams in, its sources, and Insert below / Copy / Close.
 * Errors say what to do.
 */
export function AIReview({
  session,
  onAccept,
  onDiscard,
  onRetry,
  onFollowUp,
  onInsertBelow,
  onInsertNote,
  onCopy
}: AIReviewProps) {
  const {
    status,
    answer,
    reply,
    searching,
    citations,
    error,
    changes,
    style,
    lines,
    notes,
    inserted,
    accepted
  } = session
  const working =
    searching === null
      ? answer
        ? t('ai.thinking')
        : t('ai.editing')
      : searching
        ? t('ai.searchingFor', { query: searching })
        : t('ai.searching')

  return (
    <div
      className="flex w-[min(520px,calc(100vw-32px))] flex-col gap-2 rounded-xl bg-popover p-2 text-popover-foreground shadow-popover"
      data-testid="ai-review"
      onMouseDown={(e) => {
        if (!(e.target as HTMLElement).closest('input')) e.preventDefault()
      }}
    >
      {status === 'error' && error && (
        <div className="flex flex-wrap items-center gap-2">
          <p className="m-0 min-w-0 flex-1 px-1 text-sm text-destructive">{errorText(error)}</p>
          <Button variant="ghost" size="sm" onClick={onRetry}>
            <ArrowClockwiseIcon aria-hidden />
            {t('ai.retry')}
          </Button>
          <Button variant="outline" size="sm" onClick={onDiscard}>
            {t('ai.close')}
          </Button>
        </div>
      )}

      {answer && reply && <MarkdownAnswer text={reply} />}
      {citations.length > 0 && (
        <ol className="m-0 flex list-none flex-wrap gap-1 p-0 px-1" aria-label={t('ai.sources')}>
          {citations.map((c, index) => (
            <li key={c.url}>
              <a
                href={c.url}
                className="inline-flex max-w-56 items-center gap-1 truncate rounded-md bg-muted px-1.5 py-0.5 text-xs text-muted-foreground no-underline hover:text-foreground"
              >
                <GlobeIcon aria-hidden className="shrink-0" />
                <span className="truncate">
                  {index + 1}. {c.title || new URL(c.url).hostname}
                </span>
              </a>
            </li>
          ))}
        </ol>
      )}

      {(status === 'thinking' || (status === 'answer' && searching !== null)) && (
        <div className="flex items-center justify-between gap-2 px-1">
          <Working label={working} />
          <Button variant="ghost" size="sm" onClick={onDiscard}>
            {t('ai.stop')}
          </Button>
        </div>
      )}

      {status === 'review' && changes === 0 && notes.length === 0 && (
        <div className="flex items-center justify-between gap-2 px-1">
          <p className="m-0 text-sm text-muted-foreground">{t('ai.noChanges')}</p>
          <Button variant="outline" size="sm" onClick={onDiscard}>
            {t('ai.close')}
          </Button>
        </div>
      )}

      {status === 'review' && changes > 0 && style === 'diff' && (
        <DiffReview lines={lines} changes={changes} onAccept={onAccept} onDiscard={onDiscard} />
      )}
      {status === 'review' && changes > 0 && style === 'inline' && (
        <>
          <FollowUp placeholder={t('ai.followUp')} onSubmit={onFollowUp} />
          <div className="flex flex-wrap items-center gap-1.5">
            <span className="mr-auto px-1 text-xs text-muted-foreground tabular-nums">
              {t('ai.changes', { count: changes })}
            </span>
            <Button variant="ghost" size="sm" onClick={onRetry}>
              <ArrowClockwiseIcon aria-hidden />
              {t('ai.retry')}
            </Button>
            <Button variant="outline" size="sm" onClick={onDiscard} data-testid="ai-discard">
              {t('ai.discard')}
              <Kbd>esc</Kbd>
            </Button>
            <Button size="sm" onClick={onAccept} data-testid="ai-accept">
              {t('ai.accept')}
              <Kbd className="bg-primary-foreground/15 text-primary-foreground">↵</Kbd>
            </Button>
          </div>
        </>
      )}

      {status === 'review' && notes.length > 0 && (
        <>
          <NotesCard notes={notes} inserted={inserted} onCopy={onCopy} onInsert={onInsertNote} />
          {/* Nothing (left) to accept: the notes alone, closed from here. */}
          {changes === 0 && (
            <div className="flex flex-wrap items-center justify-end gap-1.5">
              {!accepted && (
                <Button variant="ghost" size="sm" onClick={onRetry}>
                  <ArrowClockwiseIcon aria-hidden />
                  {t('ai.retry')}
                </Button>
              )}
              <Button variant="outline" size="sm" onClick={onDiscard} data-testid="ai-close">
                {t('ai.close')}
                <Kbd>esc</Kbd>
              </Button>
            </div>
          )}
        </>
      )}

      {answer && status === 'answer' && searching === null && (
        <>
          <FollowUp placeholder={t('ai.askFollowUp')} onSubmit={onFollowUp} />
          <div className="flex flex-wrap items-center justify-end gap-1.5">
            <Button variant="ghost" size="sm" onClick={() => onCopy()}>
              <CopyIcon aria-hidden />
              {t('ai.copy')}
            </Button>
            <Button variant="outline" size="sm" onClick={onInsertBelow}>
              <TextAlignLeftIcon aria-hidden />
              {t('ai.insertBelow')}
            </Button>
            <Button variant="outline" size="sm" onClick={onDiscard}>
              {t('ai.close')}
            </Button>
          </div>
        </>
      )}
    </div>
  )
}

export function renderAIReview(
  layer: FloatingLayer,
  props: AIReviewProps,
  anchor: FloatingAnchor
): void {
  layer.render(<AIReview {...props} />, anchor)
}
