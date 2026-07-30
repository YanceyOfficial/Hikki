import {
  Briefcase,
  ChevronRight,
  FileText,
  List,
  ListChecks,
  PenLine,
  RefreshCw,
  Smile,
  SlidersHorizontal,
  SpellCheck2,
  Table as TableIcon,
  X
} from 'lucide-react'
import { useEffect, useState, type ComponentProps } from 'react'

import { Button } from '#components/ui/button'
import { Input } from '#components/ui/input'
import { Popover, PopoverContent } from '#components/ui/popover'
import type { WritingToolAction } from '#lib/ai/prompts'

// The anchor Base UI's `Positioner` measures against - see popover.tsx's doc
// comment on `PopoverContent`'s `anchor` prop for why this is required here
// specifically. `editor.tsx` builds this from the live text selection
// (`window.getSelection()`) at the moment the popover opens, since the
// button that opens it (`WritingToolsButton`) is rendered by BlockNote's own
// floating formatting toolbar, not as a sibling `PopoverTrigger` of this
// component.
type WritingToolsAnchor = ComponentProps<typeof PopoverContent>['anchor']

interface WritingToolsPopoverProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  onActionSelected: (action: WritingToolAction) => void
  anchor?: WritingToolsAnchor
}

const TONES = [
  { tone: 'friendly', label: 'Friendly', icon: Smile },
  { tone: 'professional', label: 'Professional', icon: Briefcase },
  { tone: 'concise', label: 'Concise', icon: SlidersHorizontal }
] as const

const TRANSFORMS = [
  { transform: 'summary', label: 'Summary', icon: FileText },
  { transform: 'keyPoints', label: 'Key Points', icon: ListChecks },
  { transform: 'list', label: 'List', icon: List },
  { transform: 'table', label: 'Table', icon: TableIcon }
] as const

export function WritingToolsPopover({
  open,
  onOpenChange,
  onActionSelected,
  anchor
}: WritingToolsPopoverProps) {
  const [describeValue, setDescribeValue] = useState('')

  // Base UI's `Popover.Popup` stays mounted across a close/reopen cycle
  // (confirmed live: typing into the describe input, firing an action, then
  // reopening the popover showed the previous text still there) - reset on
  // every open so each invocation starts from a blank input rather than
  // carrying over whatever was typed last time.
  useEffect(() => {
    if (open) {
      setDescribeValue('')
    }
  }, [open])

  return (
    <Popover open={open} onOpenChange={onOpenChange}>
      <PopoverContent
        data-testid="writing-tools-popover"
        anchor={anchor}
        className="w-96 gap-3"
      >
        <div className="flex items-center justify-between">
          <span className="text-sm font-medium">Writing Tools</span>
          <Button
            variant="ghost"
            size="icon-sm"
            onClick={() => onOpenChange(false)}
            data-testid="writing-tools-close"
            aria-label="Close Writing Tools"
          >
            <X className="size-4" />
          </Button>
        </div>

        <Input
          placeholder="Describe your change"
          value={describeValue}
          onChange={(e) => setDescribeValue(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter' && describeValue.trim()) {
              onActionSelected({
                kind: 'custom',
                instruction: describeValue.trim()
              })
            }
          }}
          className="bg-muted h-9 rounded-full px-3.5"
          data-testid="writing-tools-describe-input"
        />

        <div className="flex gap-2">
          <Button
            variant="secondary"
            className="h-auto flex-1 flex-col gap-1 rounded-xl py-2.5"
            onClick={() => onActionSelected({ kind: 'proofread' })}
            data-testid="writing-tools-proofread"
          >
            <SpellCheck2 className="size-4" />
            Proofread
          </Button>
          <Button
            variant="secondary"
            className="h-auto flex-1 flex-col gap-1 rounded-xl py-2.5"
            onClick={() => onActionSelected({ kind: 'rewrite' })}
            data-testid="writing-tools-rewrite"
          >
            <RefreshCw className="size-4" />
            Rewrite
          </Button>
        </div>

        <div className="flex gap-2">
          {TONES.map(({ tone, label, icon: Icon }) => (
            <Button
              key={tone}
              variant="secondary"
              className="h-auto flex-1 flex-col gap-1 rounded-xl py-2"
              onClick={() => onActionSelected({ kind: 'tone', tone })}
              data-testid={`writing-tools-tone-${tone}`}
            >
              <Icon className="size-4" />
              <span className="text-xs">{label}</span>
            </Button>
          ))}
        </div>

        <div className="grid grid-cols-4 gap-2">
          {TRANSFORMS.map(({ transform, label, icon: Icon }) => (
            <Button
              key={transform}
              variant="secondary"
              className="h-auto flex-col gap-1 rounded-xl px-1 py-2.5"
              onClick={() => onActionSelected({ kind: 'transform', transform })}
              data-testid={`writing-tools-transform-${transform}`}
            >
              <Icon className="size-4" />
              <span className="text-xs">{label}</span>
            </Button>
          ))}
        </div>

        <Button
          variant="secondary"
          className="h-9 w-full justify-between rounded-full px-3.5"
          onClick={() =>
            onActionSelected({
              kind: 'compose',
              instruction: describeValue.trim()
            })
          }
          data-testid="writing-tools-compose"
        >
          <span className="flex items-center gap-2">
            <PenLine className="size-4" />
            Compose
          </span>
          <ChevronRight className="size-4" />
        </Button>
      </PopoverContent>
    </Popover>
  )
}
