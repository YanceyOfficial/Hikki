import { ArrowDown, ArrowsLeftRight, ArrowUp, TextAa, TextT, X } from '@phosphor-icons/react'
import type { Editor } from '@tiptap/core'
import { useEffect, useRef, useState, type ReactNode } from 'react'

import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip'

import { t } from '../i18n'
import { shortcutLabel } from '../shortcuts'
import { cn } from './cn'
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
    current: s.currentIndex
  }
}

/**
 * Find (and replace) panel, top right under the toolbar. Opened from the keyboard, so it appears without
 * animation. Enter / ⇧Enter step through matches, Esc closes and returns to the text.
 */
export function FindPanel({ editor, open, replace, initialText, onReplaceToggle, onClose }: Props) {
  const state = useEditorSnapshot(editor, snapshot)
  const searchRef = useRef<HTMLInputElement>(null)
  const panelRef = useRef<HTMLDivElement>(null)
  const present = usePresence(open, panelRef)
  // The field owns its text: the extension applies the term after a short debounce, so its storage lags
  // behind typing. The panel is remounted per Find request (keyed), so this starts from the prefill.
  const [text, setText] = useState(initialText)

  useEffect(() => {
    if (!open) return
    // After the value is in, so select() covers it.
    requestAnimationFrame(() => {
      searchRef.current?.focus()
      searchRef.current?.select()
    })
  }, [open])

  if (!present) return null
  const label =
    text === ''
      ? ''
      : state.count === 0
        ? t('find.noResults')
        : t('find.count', { current: (state.current ?? 0) + 1, total: state.count })

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
      className="hk-pop fixed right-4 left-4 z-40 flex flex-col gap-1.5 rounded-xl bg-popover p-1.5 text-popover-foreground shadow-popover [--hk-pop-origin:top_right] sm:left-auto sm:w-[380px]"
      style={{ top: 'calc(var(--hk-inset-top, 0px) + 8px)' }}
    >
      <div className="flex items-center gap-1">
        <input
          ref={searchRef}
          className={field}
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
        <span
          className="min-w-14 text-right text-xs text-muted-foreground tabular-nums"
          aria-live="polite"
        >
          {label}
        </span>
        <IconButton
          label={t('find.previous')}
          keys={shortcutLabel('findPrevious')}
          onClick={() => editor.commands.goToPreviousResult()}
        >
          <ArrowUp size={14} aria-hidden />
        </IconButton>
        <IconButton
          label={t('find.next')}
          keys={shortcutLabel('findNext')}
          onClick={() => editor.commands.goToNextResult()}
        >
          <ArrowDown size={14} aria-hidden />
        </IconButton>
        <IconButton label={t('find.close')} keys="esc" onClick={onClose}>
          <X size={14} aria-hidden />
        </IconButton>
      </div>
      <div className="flex items-center gap-0.5 px-0.5">
        <Toggle
          label={t('find.matchCase')}
          pressed={state.caseSensitive}
          onClick={() => editor.commands.setCaseSensitive(!state.caseSensitive)}
        >
          <TextAa size={14} aria-hidden />
        </Toggle>
        <Toggle
          label={t('find.wholeWord')}
          pressed={state.wholeWord}
          onClick={() => editor.commands.setWholeWord(!state.wholeWord)}
        >
          <TextT size={14} aria-hidden />
        </Toggle>
        <Toggle
          label={t('find.regex')}
          pressed={state.useRegex}
          onClick={() => editor.commands.setUseRegex(!state.useRegex)}
        >
          <span className="font-mono text-xs leading-none" aria-hidden>
            .*
          </span>
        </Toggle>
        <div className="flex-1" />
        <Toggle label={t('find.replaceToggle')} pressed={replace} onClick={onReplaceToggle}>
          <ArrowsLeftRight size={14} aria-hidden />
        </Toggle>
      </div>
      {replace && (
        <div className="flex items-center gap-1">
          <input
            className={field}
            placeholder={t('find.replacePlaceholder')}
            aria-label={t('find.replacePlaceholder')}
            value={state.replaceTerm}
            onChange={(e) => editor.commands.setReplaceTerm(e.target.value)}
            onKeyDown={(e) => keys(e, () => editor.commands.replace())}
          />
          <button
            type="button"
            className={textButton}
            disabled={state.count === 0}
            onClick={() => editor.commands.replace()}
          >
            {t('find.replace')}
          </button>
          <button
            type="button"
            className={textButton}
            disabled={state.count === 0}
            onClick={() => editor.commands.replaceAll()}
          >
            {t('find.replaceAll')}
          </button>
        </div>
      )}
    </div>
  )
}

const field =
  'h-8 min-w-0 flex-1 rounded-md border border-input bg-transparent px-2 text-sm outline-none placeholder:text-placeholder focus:border-ring focus:ring-3 focus:ring-ring/50'
const textButton =
  'inline-flex h-8 cursor-pointer items-center rounded-md px-2 text-xs whitespace-nowrap text-foreground hover:bg-accent disabled:cursor-default disabled:opacity-40'

function IconButton({
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
          <button
            type="button"
            aria-label={label}
            className="grid size-7 flex-none cursor-pointer place-items-center rounded-md text-subtle-foreground hover:bg-accent"
            onClick={onClick}
          />
        }
      >
        {children}
      </TooltipTrigger>
      <TooltipContent side="bottom">
        {label}
        {keys && <span className="text-background/60">{keys}</span>}
      </TooltipContent>
    </Tooltip>
  )
}

function Toggle({
  label,
  pressed,
  onClick,
  children
}: {
  label: string
  pressed: boolean
  onClick: () => void
  children: ReactNode
}) {
  return (
    <Tooltip>
      <TooltipTrigger
        render={
          <button
            type="button"
            aria-label={label}
            aria-pressed={pressed}
            className={cn(
              'grid h-6 min-w-6 cursor-pointer place-items-center rounded-md px-1 text-subtle-foreground hover:bg-accent',
              pressed && 'bg-accent text-accent-strong'
            )}
            onClick={onClick}
          />
        }
      >
        {children}
      </TooltipTrigger>
      <TooltipContent side="bottom">{label}</TooltipContent>
    </Tooltip>
  )
}
