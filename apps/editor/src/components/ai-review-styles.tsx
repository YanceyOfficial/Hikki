import { cn } from 'cn'

import { Button } from '@/components/ui/button'
import { Kbd } from '@/components/ui/kbd'

import { t } from '../core/i18n'
import { diffSide, type DiffSegment } from '../lib/ai-diff'

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
