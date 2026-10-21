import { ArrowUpIcon, CaretDownIcon, CheckIcon } from '@phosphor-icons/react'
import { useRef, useState } from 'react'

import { Button } from '@/components/ui/button'
import {
  InputGroup,
  InputGroupAddon,
  InputGroupButton,
  InputGroupInput
} from '@/components/ui/input-group'

import { t } from '../core/i18n'
import type { AIModelMenu } from '../core/protocol'
import type { AIAction } from '../extensions/ai-review'
import { aiModels, modelName } from '../lib/ai-models'
import { MenuRow, MenuTitle } from './menu-row'

type AIGroup = { label: () => string; actions: { id: string; label: () => string }[] }

/** The AI actions: what the user types, then presets (edits replace the selection after review; Ask explains it). */
export const AI_GROUPS: AIGroup[] = [
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

/** About a picture or a PDF (the block menu on an image or a file): nothing to edit, only answers. */
const MEDIA_GROUPS: AIGroup[] = [
  {
    label: () => t('ai.group.ask'),
    actions: [
      { id: 'describe', label: () => t('ai.action.describe') },
      { id: 'extractText', label: () => t('ai.action.extractText') },
      { id: 'explain', label: () => t('ai.action.explain') },
      { id: 'summarize', label: () => t('ai.action.summarize') }
    ]
  }
]

export function AIPanel({
  onRun,
  onCancel,
  autoFocus = true,
  media = false
}: {
  /** Focus the instruction field on open (off where the panel opens on hover). */
  autoFocus?: boolean
  /** About a picture or a PDF: questions and answers only (the field asks, `ask`). */
  media?: boolean
  onRun: (action: AIAction) => void
  onCancel: () => void
}) {
  const [value, setValue] = useState('')
  // The models this request may run on (none without a key); a pick holds for this request only — the default
  // stays the chat's.
  const [menu] = useState(aiModels)
  const [model, setModel] = useState<string | null>(null)
  const [picking, setPicking] = useState(false)
  const field = useRef<HTMLInputElement>(null)
  const placeholder = media ? t('ai.askPlaceholder') : t('ai.editPlaceholder')
  const run = (action: AIAction) => onRun(model ? { ...action, model } : action)
  const submit = () => {
    const instruction = value.trim()
    if (instruction) run({ id: media ? 'ask' : 'custom', instruction })
  }
  const pick = (id: string) => {
    setModel(id === menu?.choice ? null : id)
    setPicking(false)
    field.current?.focus()
  }
  return (
    <div role="menu" aria-label={t('ai.menu')}>
      <div className="p-1">
        <InputGroup className="h-8 shadow-none">
          <InputGroupInput
            ref={field}
            // oxlint-disable-next-line jsx-a11y/no-autofocus -- the panel opens to type an instruction
            autoFocus={autoFocus}
            className="md:text-sm"
            placeholder={placeholder}
            aria-label={placeholder}
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
                if (picking) setPicking(false)
                else onCancel()
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
        {/* On a line of its own, so the field keeps its width. */}
        {menu && (
          <Button
            variant="ghost"
            size="xs"
            className="mt-1 max-w-full text-muted-foreground"
            aria-label={t('ai.model.label')}
            aria-expanded={picking}
            data-testid="ai-model"
            onClick={() => setPicking(!picking)}
          >
            <span className="truncate">{choiceName(model ?? menu.choice)}</span>
            <CaretDownIcon data-icon="inline-end" aria-hidden />
          </Button>
        )}
      </div>
      {menu && picking ? (
        <ModelList menu={menu} current={model ?? menu.choice} onPick={pick} />
      ) : (
        (media ? MEDIA_GROUPS : AI_GROUPS).map((group) => (
          <div key={group.actions[0].id}>
            <MenuTitle>{group.label()}</MenuTitle>
            {group.actions.map((action) => (
              <MenuRow
                key={action.id}
                role="menuitem"
                data-testid={`ai-action-${action.id}`}
                onClick={() => run({ id: action.id })}
              >
                <span className="flex-1 truncate">{action.label()}</span>
              </MenuRow>
            ))}
          </div>
        ))
      )}
    </div>
  )
}

const choiceName = (choice: string): string => modelName(choice) ?? t('ai.model.auto')

const GROUP_TITLES: Record<AIModelMenu['groups'][number]['kind'], () => string> = {
  favorites: () => t('ai.model.favorites'),
  recommended: () => t('ai.model.recommended'),
  other: () => t('ai.model.other')
}

/** The models to run this request on, in the panel's place (a popup of its own would take the menu's focus). */
function ModelList({
  menu,
  current,
  onPick
}: {
  menu: AIModelMenu
  current: string
  onPick: (id: string) => void
}) {
  const row = (id: string, name: string, detail?: string) => (
    <MenuRow
      key={id}
      role="menuitemradio"
      aria-checked={id === current}
      data-testid={`ai-model-${id}`}
      onClick={() => onPick(id)}
    >
      <span className="flex-1 truncate">
        {name}
        {detail && <span className="text-muted-foreground"> · {detail}</span>}
      </span>
      {id === current && <CheckIcon size={14} aria-hidden />}
    </MenuRow>
  )
  return (
    <div role="group" aria-label={t('ai.model.label')}>
      <MenuTitle>{t('ai.model.label')}</MenuTitle>
      {row('auto', t('ai.model.auto'), menu.auto ?? undefined)}
      {menu.groups.map((group) => (
        <div key={group.kind}>
          <MenuTitle>{GROUP_TITLES[group.kind]()}</MenuTitle>
          {group.models.map((m) => row(m.id, m.name))}
        </div>
      ))}
    </div>
  )
}
