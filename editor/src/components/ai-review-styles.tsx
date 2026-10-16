import { ArrowRight02Icon, Copy01Icon } from '@hugeicons/core-free-icons'
import { cn } from 'cn'

import { Button } from '@/components/ui/button'
import { Kbd } from '@/components/ui/kbd'

import { t } from '../core/i18n'
import type { AINote } from '../lib/ai-content'
import { changePairs, diffSide, type DiffSegment } from '../lib/ai-diff'
import { Icon } from './icons'

export type AIReviewLine = { key: string; diff: DiffSegment[] }

/** One side of a changed line, its changed words marked. */
function Side({ diff, side }: { diff: DiffSegment[]; side: 'before' | 'after' }) {
  const skip = side === 'before' ? 'add' : 'del'
  return (
    <>
      {diff
        .filter((segment) => segment.type !== skip)
        .map((segment, index) =>
          segment.type === 'same' ? (
            <span key={index}>{segment.text}</span>
          ) : (
            <mark
              key={index}
              className={cn(
                'rounded-xs text-inherit',
                side === 'before' ? 'bg-ink-red/25' : 'bg-ink-green/25'
              )}
            >
              {segment.text}
            </mark>
          )
        )}
    </>
  )
}

/**
 * Review style B: the selection's lines as a code diff — an unchanged line once, a changed one as − before and + after
 * with the changed words marked. The page stays as it is until Accept.
 */
export function DiffReview({
  lines,
  changes,
  onAccept,
  onDiscard
}: {
  lines: AIReviewLine[]
  changes: number
  onAccept: () => void
  onDiscard: () => void
}) {
  const changed = lines.filter((line) => line.diff.some((s) => s.type !== 'same')).length
  return (
    <div className="flex flex-col gap-2" data-testid="ai-review-diff">
      <div className="max-h-[min(360px,50vh)] overflow-auto rounded-md border border-border font-mono text-xs leading-relaxed">
        {lines.map((line) =>
          line.diff.every((s) => s.type === 'same') ? (
            <DiffRow key={line.key} sign=" ">
              {diffSide(line.diff, 'before')}
            </DiffRow>
          ) : (
            <div key={line.key}>
              <DiffRow sign="−" className="bg-wash-red" signClass="text-ink-red">
                <Side diff={line.diff} side="before" />
              </DiffRow>
              <DiffRow sign="+" className="bg-wash-green" signClass="text-ink-green">
                <Side diff={line.diff} side="after" />
              </DiffRow>
            </div>
          )
        )}
      </div>
      <div className="flex flex-wrap items-center gap-1.5">
        <span className="mr-auto px-1 text-xs text-muted-foreground tabular-nums">
          {t('ai.changesInLines', { count: changes, changed, total: lines.length })}
        </span>
        <Button variant="outline" size="sm" onClick={onDiscard} data-testid="ai-discard">
          {t('ai.discard')}
          <Kbd>esc</Kbd>
        </Button>
        <Button size="sm" onClick={onAccept} data-testid="ai-accept">
          {t('ai.accept')}
          <Kbd className="bg-primary-foreground/15 text-primary-foreground">↵</Kbd>
        </Button>
      </div>
    </div>
  )
}

function DiffRow({
  sign,
  className,
  signClass,
  children
}: {
  sign: string
  className?: string
  signClass?: string
  children: React.ReactNode
}) {
  return (
    <div className={cn('grid grid-cols-[1.25rem_1fr] px-2 py-px whitespace-pre-wrap', className)}>
      <span className={cn('select-none', signClass ?? 'text-muted-foreground')} aria-hidden>
        {sign}
      </span>
      <span className="min-w-0 break-words">{children}</span>
    </div>
  )
}

/**
 * Review style C: a card listing each change — what it replaced, with what, and why (the model's notes; without them,
 * the changes from the diff). The page is untouched until "Replace selection".
 */
export function BubbleReview({
  lines,
  notes,
  onAccept,
  onDiscard,
  onCopy
}: {
  lines: AIReviewLine[]
  notes: AINote[]
  onAccept: () => void
  onDiscard: () => void
  onCopy: (text: string) => void
}) {
  const items: AINote[] =
    notes.length > 0
      ? notes
      : lines.flatMap((line) => changePairs(line.diff).map((pair) => ({ ...pair, why: '' })))
  const result = lines.map((line) => diffSide(line.diff, 'after')).join('\n')
  return (
    <div className="flex flex-col gap-2" data-testid="ai-review-bubble">
      <ul className="m-0 flex max-h-[min(320px,45vh)] list-none flex-col gap-1.5 overflow-y-auto p-0 px-1 text-sm">
        {items.map((item, index) => (
          <li key={index} className="flex flex-wrap items-baseline gap-x-1.5">
            <span className="font-medium text-ink-red line-through decoration-1">
              {item.from || '∅'}
            </span>
            <Icon
              icon={ArrowRight02Icon}
              className="shrink-0 self-center text-placeholder"
              aria-hidden
            />
            <span className="font-medium text-ink-green">{item.to || t('ai.removed')}</span>
            {item.why && <span className="text-muted-foreground">· {item.why}</span>}
          </li>
        ))}
      </ul>
      <p className="m-0 px-1 text-xs text-muted-foreground">{t('ai.pageUntouched')}</p>
      <div className="flex flex-wrap items-center justify-end gap-1.5">
        <Button variant="ghost" size="sm" onClick={() => onCopy(result)}>
          <Icon icon={Copy01Icon} aria-hidden />
          {t('ai.copy')}
        </Button>
        <Button variant="outline" size="sm" onClick={onDiscard} data-testid="ai-discard">
          {t('ai.close')}
        </Button>
        <Button size="sm" onClick={onAccept} data-testid="ai-accept">
          {t('ai.replace')}
        </Button>
      </div>
    </div>
  )
}
