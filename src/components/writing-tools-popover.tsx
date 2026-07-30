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
import { streamWritingTool } from '#lib/ai/client'
import type { AiProviderId } from '#lib/ai/models'
import type { WritingToolAction } from '#lib/ai/prompts'
import { backend } from '#lib/backend/index'

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
  // The plain text selected in the editor when the popover was opened
  // (`editor.getSelectedText()` at open-time, captured in `editor.tsx`) -
  // this is what gets sent to the AI as the text to proofread/rewrite/etc.
  selectedText: string
  // Applies the finished preview text back into the document via BlockNote's
  // own `editor.replaceBlocks`/`editor.insertBlocks` APIs (spec §14b - never
  // raw `Doc.blocks` mutation). Both close the popover on the `editor.tsx`
  // side once applied.
  onReplace: (text: string) => void
  onInsertBelow: (text: string) => void
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
  selectedText,
  onReplace,
  onInsertBelow,
  anchor
}: WritingToolsPopoverProps) {
  const [describeValue, setDescribeValue] = useState('')
  const [phase, setPhase] = useState<
    'idle' | 'streaming' | 'previewing' | 'error'
  >('idle')
  const [previewText, setPreviewText] = useState('')
  const [errorMessage, setErrorMessage] = useState('')

  // Base UI's `Popover.Popup` stays mounted across a close/reopen cycle
  // (confirmed live: typing into the describe input, firing an action, then
  // reopening the popover showed the previous text still there) - reset on
  // every open so each invocation starts from a blank input/idle state
  // rather than carrying over whatever was typed/streamed last time.
  useEffect(() => {
    if (open) {
      setDescribeValue('')
      setPhase('idle')
      setPreviewText('')
      setErrorMessage('')
    }
  }, [open])

  const runAction = async (action: WritingToolAction) => {
    setPhase('streaming')
    setPreviewText('')
    try {
      // Provider/model resolution: Task 8's saved defaults, via
      // backend.getAiSettings() - read them once when starting a stream
      // rather than holding them in component state that could go stale if
      // the user changes defaults in another window. Inside this try/catch
      // because it's a real IPC call in Tauri mode and can reject.
      const settings = await backend.getAiSettings()
      if (!settings.defaultAiProvider || !settings.defaultAiModel) {
        setPhase('error')
        setErrorMessage(
          'No default AI provider/model configured. Open AI Settings first.'
        )
        return
      }
      for await (const event of streamWritingTool(action, selectedText, {
        provider: settings.defaultAiProvider as AiProviderId,
        modelId: settings.defaultAiModel
      })) {
        if (event.type === 'delta') {
          setPreviewText((prev) => prev + event.text)
        } else if (event.type === 'error') {
          setPhase('error')
          setErrorMessage(event.message)
          return
        } else if (event.type === 'done') {
          setPhase('previewing')
        }
      }
    } catch (err) {
      // `streamWritingTool` already yields a clean `error` event for its own
      // internal failure cases (missing API key, model not found, IPC
      // rejection) - see client.ts. This catch backstops anything that can
      // still throw outside that generator's own handling: getAiSettings()
      // above rejecting, or a synchronous throw inside the generator body
      // before its first yield.
      setPhase('error')
      setErrorMessage(err instanceof Error ? err.message : String(err))
    }
  }

  const streaming = phase === 'streaming'

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
              runAction({
                kind: 'custom',
                instruction: describeValue.trim()
              })
            }
          }}
          disabled={streaming}
          className="bg-muted h-9 rounded-full px-3.5"
          data-testid="writing-tools-describe-input"
        />

        <div className="flex gap-2">
          <Button
            variant="secondary"
            className="h-auto flex-1 flex-col gap-1 rounded-xl py-2.5"
            onClick={() => runAction({ kind: 'proofread' })}
            disabled={streaming}
            data-testid="writing-tools-proofread"
          >
            <SpellCheck2 className="size-4" />
            Proofread
          </Button>
          <Button
            variant="secondary"
            className="h-auto flex-1 flex-col gap-1 rounded-xl py-2.5"
            onClick={() => runAction({ kind: 'rewrite' })}
            disabled={streaming}
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
              onClick={() => runAction({ kind: 'tone', tone })}
              disabled={streaming}
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
              onClick={() => runAction({ kind: 'transform', transform })}
              disabled={streaming}
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
            runAction({
              kind: 'compose',
              instruction: describeValue.trim()
            })
          }
          disabled={streaming}
          data-testid="writing-tools-compose"
        >
          <span className="flex items-center gap-2">
            <PenLine className="size-4" />
            Compose
          </span>
          <ChevronRight className="size-4" />
        </Button>

        {(phase === 'streaming' || phase === 'previewing') && (
          <div
            data-testid="writing-tools-preview"
            className="bg-muted max-h-48 overflow-y-auto rounded-xl px-3.5 py-2.5 text-sm whitespace-pre-wrap"
          >
            {previewText}
          </div>
        )}

        {phase === 'previewing' && (
          <div className="flex gap-2">
            <Button
              variant="default"
              className="flex-1 rounded-full"
              onClick={() => onReplace(previewText)}
              data-testid="writing-tools-replace"
            >
              Replace
            </Button>
            <Button
              variant="secondary"
              className="flex-1 rounded-full"
              onClick={() => onInsertBelow(previewText)}
              data-testid="writing-tools-insert-below"
            >
              Insert below
            </Button>
            <Button
              variant="ghost"
              className="rounded-full"
              onClick={() => setPhase('idle')}
              data-testid="writing-tools-discard"
            >
              Discard
            </Button>
          </div>
        )}

        {phase === 'error' && (
          <div
            data-testid="writing-tools-error"
            className="rounded-xl bg-red-50 px-3.5 py-2.5 text-sm text-red-700 dark:bg-red-950 dark:text-red-300"
          >
            <p>{errorMessage}</p>
            <Button
              variant="ghost"
              size="sm"
              className="mt-1 h-auto px-0 py-0 text-xs underline"
              onClick={() => setPhase('idle')}
              data-testid="writing-tools-error-dismiss"
            >
              Dismiss
            </Button>
          </div>
        )}
      </PopoverContent>
    </Popover>
  )
}
