import { Button } from '@/components/ui/button'
import { Kbd } from '@/components/ui/kbd'

import { t } from '../core/i18n'
import type { AIChangeInput } from '../core/protocol'
import { keyLabel } from '../core/shortcuts'
import type { FloatingAnchor, FloatingLayer } from './floating'

export type AIChangeBarProps = {
  kind: AIChangeInput['kind']
  title: string
  why: string | null
  /** Which of the answer's changes this is ("2 of 6"). */
  position: number
  total: number
  onApprove: () => void
  onSkip: () => void
  onEdit: () => void
}

const KIND_LABELS: Record<AIChangeInput['kind'], () => string> = {
  rewrite: () => t('ai.change.kind.rewrite'),
  insert: () => t('ai.change.kind.insert'),
  move: () => t('ai.change.kind.move'),
  delete: () => t('ai.change.kind.delete')
}

/** Under a change Ask AI proposes, shown in the page: what and why, then Edit · Skip ⌫ · Approve ↵. */
export function AIChangeBar({
  kind,
  title,
  why,
  position,
  total,
  onApprove,
  onSkip,
  onEdit
}: AIChangeBarProps) {
  const kindLabel = KIND_LABELS[kind]()
  return (
    <div
      className="flex w-(--layout-panel-review) max-w-(--layout-viewport-max) flex-wrap items-center gap-2 rounded-xl bg-popover p-2 text-popover-foreground shadow-popover"
      data-testid="ai-change-bar"
      // The page keeps the caret (↵ / ⌫ go to it).
      onMouseDown={(e) => e.preventDefault()}
    >
      <div className="min-w-0 flex-1 px-1">
        <p className="m-0 truncate text-sm font-medium">{title || kindLabel}</p>
        <p className="m-0 truncate text-xs text-muted-foreground">
          {t('ai.change.position', { position, total })} · {kindLabel}
          {why ? ` · ${why}` : ''}
        </p>
      </div>
      <div className="flex items-center gap-1">
        <Button variant="ghost" size="sm" onClick={onEdit} data-testid="ai-change-edit">
          {t('ai.change.edit')}
        </Button>
        <Button variant="outline" size="sm" onClick={onSkip} data-testid="ai-change-skip">
          {t('ai.change.skip')}
          <Kbd>{keyLabel('delete')}</Kbd>
        </Button>
        <Button size="sm" onClick={onApprove} data-testid="ai-change-approve">
          {t('ai.change.approve')}
          <Kbd className="bg-primary-foreground/15 text-primary-foreground">
            {keyLabel('return')}
          </Kbd>
        </Button>
      </div>
    </div>
  )
}

export function renderAIChangeBar(
  layer: FloatingLayer,
  props: AIChangeBarProps,
  anchor: FloatingAnchor
): void {
  layer.render(<AIChangeBar {...props} />, anchor)
}
