import { cn } from 'cn'

import { Button } from '@/components/ui/button'
import { Kbd } from '@/components/ui/kbd'

import { t } from '../core/i18n'
import { diffSide, type DiffSegment } from '../lib/ai-diff'

/** A line of the review: a selected block's diff, or (`added`) a block the model adds after the selection. */
export type AIReviewLine = { key: string; diff: DiffSegment[]; added?: boolean }

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
 * with the changed words marked, a block the model adds after the selection as a + line of its own. The page stays as
 * it is until Accept.
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
  const selected = lines.filter((line) => !line.added)
  const added = lines.length - selected.length
  const changed = selected.filter((line) => line.diff.some((s) => s.type !== 'same')).length
  return (
    <div className="flex flex-col gap-2" data-testid="ai-review-diff">
      <div className="max-h-(--layout-panel-height-answer) overflow-auto rounded-md border border-border font-mono text-xs leading-relaxed">
        {lines.map((line) =>
          line.added ? (
            <DiffRow
              key={line.key}
              sign="+"
              className="bg-wash-green"
              signClass="text-ink-green"
              data-testid="ai-review-added"
            >
              {diffSide(line.diff, 'after')}
            </DiffRow>
          ) : line.diff.every((s) => s.type === 'same') ? (
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
          {t('ai.changesInLines', { count: changes, changed, total: selected.length })}
          {added > 0 && <> · {t('ai.addedBlocks', { count: added })}</>}
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
  children,
  'data-testid': testID
}: {
  sign: string
  className?: string
  signClass?: string
  children: React.ReactNode
  'data-testid'?: string
}) {
  return (
    <div
      className={cn('grid grid-cols-[1.25rem_1fr] px-2 py-px whitespace-pre-wrap', className)}
      data-testid={testID}
    >
      <span className={cn('select-none', signClass ?? 'text-muted-foreground')} aria-hidden>
        {sign}
      </span>
      <span className="min-w-0 break-words">{children}</span>
    </div>
  )
}
