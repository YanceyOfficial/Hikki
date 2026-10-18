import { ArrowUpIcon, SparkleIcon } from '@phosphor-icons/react'
import { useState } from 'react'

import { Button } from '@/components/ui/button'
import {
  InputGroup,
  InputGroupAddon,
  InputGroupButton,
  InputGroupInput
} from '@/components/ui/input-group'

import { t } from '../core/i18n'
import type { AIAction } from '../extensions/ai-review'
import { AI_GROUPS } from './ai-panel'
import type { FloatingLayer } from './floating'
import { LinkPanel } from './selection-menu'

export type TouchDockProps =
  | { kind: 'ai'; onRun: (action: AIAction) => void; onClose: () => void }
  | {
      kind: 'link'
      href: string | null
      onApply: (href: string) => void
      onRemove: () => void
      onClose: () => void
    }

/** Presets offered as chips, in the selection menu's order (edits first, then asking). */
const CHIPS = AI_GROUPS.flatMap((group) => group.actions)

/**
 * The phone's fields that need typing, docked just above the keyboard bar (the keyboard stays up): Ask AI — the
 * presets as chips over an instruction field — or a link's address.
 */
export function TouchDock(props: TouchDockProps) {
  return (
    <div
      className="flex w-[calc(100vw-16px)] flex-col gap-1.5 rounded-xl bg-popover p-1.5 text-popover-foreground shadow-popover"
      data-testid={`touch-dock-${props.kind}`}
    >
      {props.kind === 'ai' ? (
        <AIComposer onRun={props.onRun} onCancel={props.onClose} />
      ) : (
        <LinkPanel
          href={props.href}
          onApply={props.onApply}
          onRemove={props.onRemove}
          onCancel={props.onClose}
        />
      )}
    </div>
  )
}

function AIComposer({
  onRun,
  onCancel
}: {
  onRun: (action: AIAction) => void
  onCancel: () => void
}) {
  const [value, setValue] = useState('')
  const submit = () => {
    const instruction = value.trim()
    if (instruction) onRun({ id: 'custom', instruction })
  }
  return (
    <>
      <div className="flex [scrollbar-width:none] gap-1.5 overflow-x-auto overscroll-contain">
        {CHIPS.map((action) => (
          <Button
            key={action.id}
            variant="outline"
            size="sm"
            className="shrink-0 rounded-full"
            data-testid={`touch-ai-${action.id}`}
            onClick={() => onRun({ id: action.id })}
          >
            {action.label()}
          </Button>
        ))}
      </div>
      <InputGroup className="h-10 rounded-full shadow-none">
        <InputGroupAddon>
          <SparkleIcon weight="fill" className="text-primary" aria-hidden />
        </InputGroupAddon>
        <InputGroupInput
          // oxlint-disable-next-line jsx-a11y/no-autofocus -- the composer opens to type an instruction
          autoFocus
          placeholder={t('ai.editPlaceholder')}
          aria-label={t('ai.editPlaceholder')}
          value={value}
          onChange={(e) => setValue(e.target.value)}
          onKeyDown={(e) => {
            if (e.nativeEvent.isComposing) return
            if (e.key === 'Enter') {
              e.preventDefault()
              submit()
            } else if (e.key === 'Escape') {
              e.preventDefault()
              onCancel()
            }
          }}
        />
        <InputGroupAddon align="inline-end">
          <InputGroupButton
            size="icon-xs"
            className="rounded-full"
            aria-label={t('ai.send')}
            disabled={!value.trim()}
            onClick={submit}
          >
            <ArrowUpIcon aria-hidden />
          </InputGroupButton>
        </InputGroupAddon>
      </InputGroup>
    </>
  )
}

/** Over the bottom of what the keyboard leaves visible (the layer flips above this line). */
function keyboardEdge(): DOMRect {
  const vv = window.visualViewport
  const bottom = vv ? vv.offsetTop + vv.height : window.innerHeight
  return new DOMRect(vv?.offsetLeft ?? 0, bottom, 0, 0)
}

export function renderTouchDock(layer: FloatingLayer, props: TouchDockProps): void {
  layer.render(<TouchDock {...props} />, keyboardEdge)
}
