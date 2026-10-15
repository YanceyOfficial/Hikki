import { ArrowUpIcon } from '@phosphor-icons/react'
import { useState } from 'react'

import {
  InputGroup,
  InputGroupAddon,
  InputGroupButton,
  InputGroupInput
} from '@/components/ui/input-group'

import { t } from '../core/i18n'
import type { AIAction } from '../extensions/ai-review'
import { PanelTitle, rowClass } from './selection-menu'

/** The AI actions: what the user types, then presets (edits replace the selection after review; Ask explains it). */
const AI_GROUPS: { label: () => string; actions: { id: string; label: () => string }[] }[] = [
  {
    label: () => t('ai.group.edit'),
    actions: [
      { id: 'improve', label: () => t('ai.action.improve') },
      { id: 'fix', label: () => t('ai.action.fix') },
      { id: 'shorter', label: () => t('ai.action.shorter') },
      { id: 'longer', label: () => t('ai.action.longer') },
      { id: 'simplify', label: () => t('ai.action.simplify') }
    ]
  },
  {
    label: () => t('ai.group.tone'),
    actions: [
      { id: 'tone:professional', label: () => t('ai.action.tone.professional') },
      { id: 'tone:casual', label: () => t('ai.action.tone.casual') },
      { id: 'tone:friendly', label: () => t('ai.action.tone.friendly') },
      { id: 'tone:confident', label: () => t('ai.action.tone.confident') }
    ]
  },
  {
    label: () => t('ai.group.translate'),
    actions: [
      { id: 'translate:zh', label: () => t('ai.action.translate.zh') },
      { id: 'translate:en', label: () => t('ai.action.translate.en') },
      { id: 'translate:ja', label: () => t('ai.action.translate.ja') }
    ]
  },
  {
    label: () => t('ai.group.ask'),
    actions: [
      { id: 'explain', label: () => t('ai.action.explain') },
      { id: 'summarize', label: () => t('ai.action.summarize') }
    ]
  }
]

export function AIPanel({
  onRun,
  onCancel,
  autoFocus = true
}: {
  /** Focus the instruction field on open (off where the panel opens on hover). */
  autoFocus?: boolean
  onRun: (action: AIAction) => void
  onCancel: () => void
}) {
  const [value, setValue] = useState('')
  const submit = () => {
    const instruction = value.trim()
    if (instruction) onRun({ id: 'custom', instruction })
  }
  return (
    <div role="menu" aria-label={t('ai.menu')}>
      <div className="p-1">
        <InputGroup className="h-8 shadow-none">
          <InputGroupInput
            // oxlint-disable-next-line jsx-a11y/no-autofocus -- the panel opens to type an instruction
            autoFocus={autoFocus}
            className="md:text-sm"
            placeholder={t('ai.editPlaceholder')}
            aria-label={t('ai.editPlaceholder')}
            data-testid="selection-menu-ai-input"
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
              aria-label={t('ai.send')}
              disabled={!value.trim()}
              onClick={submit}
            >
              <ArrowUpIcon aria-hidden />
            </InputGroupButton>
          </InputGroupAddon>
        </InputGroup>
      </div>
      {AI_GROUPS.map((group) => (
        <div key={group.actions[0].id}>
          <PanelTitle>{group.label()}</PanelTitle>
          {group.actions.map((action) => (
            <button
              key={action.id}
              type="button"
              role="menuitem"
              className={rowClass}
              data-testid={`ai-action-${action.id}`}
              onClick={() => onRun({ id: action.id })}
            >
              <span className="flex-1 truncate">{action.label()}</span>
            </button>
          ))}
        </div>
      ))}
    </div>
  )
}
