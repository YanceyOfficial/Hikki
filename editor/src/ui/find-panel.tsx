import {
  ArrowDownIcon,
  ArrowUpIcon,
  ArrowsLeftRightIcon,
  TextAaIcon,
  TextTIcon,
  XIcon
} from '@phosphor-icons/react'
import type { Editor } from '@tiptap/core'
import { useEffect, useRef, useState, type ReactNode } from 'react'

import {
  InputGroup,
  InputGroupAddon,
  InputGroupButton,
  InputGroupInput,
  InputGroupText
} from '@/components/ui/input-group'
import { Kbd } from '@/components/ui/kbd'
import { Separator } from '@/components/ui/separator'
import { Toggle } from '@/components/ui/toggle'
import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip'
import { cn } from '@/lib/utils'

import { revealCurrentMatch } from '../extensions/find'
import { t } from '../i18n'
import { shortcutLabel } from '../shortcuts'
import { usePresence } from './floating'
import { useEditorSnapshot } from './use-editor-snapshot'

type Props = {
  editor: Editor
  open: boolean
  replace: boolean
  /** The search text to start with (the selection, or the current term). */
  initialText: string
  onReplaceToggle: () => void
  onClose: () => void
}

function snapshot(editor: Editor) {
  const s = editor.storage.findAndReplace
  return {
    replaceTerm: s.replaceTerm,
    caseSensitive: s.caseSensitive,
    wholeWord: s.wholeWord,
    useRegex: s.useRegex,
    count: s.results.length,
    current: s.currentIndex,
    /** Where the current match is: stepping or a new term moves it, and the page follows. */
    currentFrom: (s.results[s.currentIndex ?? 0]?.from as number | undefined) ?? null
  }
}

/** The compact controls that sit inside the field. */
const control = 'size-6 min-w-6 rounded-sm px-0 text-subtle-foreground [&_svg]:size-3.5'

/**
 * Find (and replace), top right under the toolbar: one field with its count and controls inside
 * (`0 / 0` ↑ ↓ | ⇄ ✕), and a "Replace by…" row under it with Replace all / Replace. Enter / ⇧Enter step
 * through matches, Esc closes and returns to the text.
 */
export function FindPanel({ editor, open, replace, initialText, onReplaceToggle, onClose }: Props) {
  const state = useEditorSnapshot(editor, snapshot)
  const searchRef = useRef<HTMLInputElement>(null)
  const panelRef = useRef<HTMLDivElement>(null)
  const present = usePresence(open, panelRef)
  // The field owns its text: the extension applies the term after a short debounce, so its storage lags
  // behind typing. The panel is remounted per Find request (keyed), so this starts from the prefill.
  const [text, setText] = useState(initialText)

  // The page follows the current match whenever it moves (stepping, or a new term's first match).
  const revealed = useRef<number | null>(null)
  useEffect(() => {
    if (
      !open ||
      text === '' ||
      state.currentFrom === null ||
      state.currentFrom === revealed.current
    )
      return
    revealed.current = state.currentFrom
    revealCurrentMatch(editor)
  }, [open, text, state.currentFrom, editor])

  useEffect(() => {
    if (!open) return
    // After the value is in, so select() covers it.
    requestAnimationFrame(() => {
      searchRef.current?.focus()
      searchRef.current?.select()
    })
  }, [open])

  if (!present) return null
  const current = state.count === 0 ? 0 : (state.current ?? 0) + 1
  const count = t('find.count', { current, total: state.count })

  const keys = (event: React.KeyboardEvent, onEnter: (shift: boolean) => void) => {
    if (event.nativeEvent.isComposing) return
    if (event.key === 'Escape') {
      event.preventDefault()
      onClose()
    } else if (event.key === 'Enter') {
      event.preventDefault()
      onEnter(event.shiftKey)
    }
  }

  return (
    <div
      role="search"
      aria-label={t('find.label')}
      ref={panelRef}
      data-testid="find-panel"
      className="hk-pop fixed right-4 left-4 z-40 rounded-xl bg-popover text-popover-foreground shadow-popover [--hk-pop-origin:top_right] sm:left-auto sm:w-[440px]"
      // The same distance from the toolbar as from the window's edge (right-4).
      style={{ top: 'calc(var(--hk-inset-top, 0px) + 16px)' }}
    >
      <InputGroup className={cn('h-10 rounded-xl shadow-none', replace && 'rounded-b-none')}>
        <InputGroupInput
          ref={searchRef}
          placeholder={t('find.placeholder')}
          aria-label={t('find.placeholder')}
          value={text}
          onChange={(e) => {
            setText(e.target.value)
            editor.commands.setSearchTerm(e.target.value)
          }}
          onKeyDown={(e) =>
            keys(e, (shift) =>
              shift ? editor.commands.goToPreviousResult() : editor.commands.goToNextResult()
            )
          }
        />
        <InputGroupAddon align="inline-end" className="gap-0.5 pr-1.5">
          <Option
            label={t('find.matchCase')}
            pressed={state.caseSensitive}
            onChange={(on) => editor.commands.setCaseSensitive(on)}
          >
            <TextAaIcon aria-hidden />
          </Option>
          <Option
            label={t('find.wholeWord')}
            pressed={state.wholeWord}
            onChange={(on) => editor.commands.setWholeWord(on)}
          >
            <TextTIcon aria-hidden />
          </Option>
          <Option
            label={t('find.regex')}
            pressed={state.useRegex}
            onChange={(on) => editor.commands.setUseRegex(on)}
          >
            <span className="font-mono text-xs leading-none" aria-hidden>
              .*
            </span>
          </Option>
          <InputGroupText className="min-w-10 justify-end px-1 tabular-nums" aria-live="polite">
            {count}
          </InputGroupText>
          <Action
            label={t('find.previous')}
            keys={shortcutLabel('findPrevious')}
            onClick={() => editor.commands.goToPreviousResult()}
          >
            <ArrowUpIcon aria-hidden />
          </Action>
          <Action
            label={t('find.next')}
            keys={shortcutLabel('findNext')}
            onClick={() => editor.commands.goToNextResult()}
          >
            <ArrowDownIcon aria-hidden />
          </Action>
          <Separator orientation="vertical" className="mx-1 data-[orientation=vertical]:h-4" />
          <Option
            label={t('find.replaceToggle')}
            pressed={replace}
            onChange={onReplaceToggle}
            className="aria-pressed:bg-primary/10 aria-pressed:text-primary"
          >
            <ArrowsLeftRightIcon aria-hidden />
          </Option>
          <Action label={t('find.close')} keys="esc" onClick={onClose}>
            <XIcon aria-hidden />
          </Action>
        </InputGroupAddon>
      </InputGroup>
      {replace && (
        <InputGroup className="-mt-px h-10 rounded-xl rounded-t-none shadow-none">
          <InputGroupInput
            placeholder={t('find.replacePlaceholder')}
            aria-label={t('find.replacePlaceholder')}
            value={state.replaceTerm}
            onChange={(e) => editor.commands.setReplaceTerm(e.target.value)}
            onKeyDown={(e) => keys(e, () => editor.commands.replace())}
          />
          <InputGroupAddon align="inline-end" className="gap-0.5 pr-1.5">
            <InputGroupButton
              size="xs"
              className="text-subtle-foreground"
              disabled={state.count === 0}
              onClick={() => editor.commands.replaceAll()}
            >
              {t('find.replaceAll')}
            </InputGroupButton>
            <InputGroupButton
              size="xs"
              className="text-subtle-foreground"
              disabled={state.count === 0}
              onClick={() => editor.commands.replace()}
            >
              {t('find.replace')}
            </InputGroupButton>
          </InputGroupAddon>
        </InputGroup>
      )}
    </div>
  )
}

/** An icon button inside the field, with its name (and key) in a tooltip. */
function Action({
  label,
  keys,
  onClick,
  children
}: {
  label: string
  keys?: string
  onClick: () => void
  children: ReactNode
}) {
  return (
    <Tooltip>
      <TooltipTrigger
        render={
          <InputGroupButton
            size="icon-xs"
            className={control}
            aria-label={label}
            onClick={onClick}
          />
        }
      >
        {children}
      </TooltipTrigger>
      <TooltipContent side="bottom">
        {label}
        {keys && <Kbd>{keys}</Kbd>}
      </TooltipContent>
    </Tooltip>
  )
}

/** A search option (match case, whole word, regex) or the replace switch: a toggle inside the field. */
function Option({
  label,
  pressed,
  onChange,
  className,
  children
}: {
  label: string
  pressed: boolean
  onChange: (pressed: boolean) => void
  className?: string
  children: ReactNode
}) {
  return (
    <Tooltip>
      <TooltipTrigger
        render={
          <Toggle
            size="sm"
            className={cn(
              control,
              'aria-pressed:bg-accent aria-pressed:text-foreground',
              className
            )}
            aria-label={label}
            pressed={pressed}
            onPressedChange={onChange}
          />
        }
      >
        {children}
      </TooltipTrigger>
      <TooltipContent side="bottom">{label}</TooltipContent>
    </Tooltip>
  )
}
