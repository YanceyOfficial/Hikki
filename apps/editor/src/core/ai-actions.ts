import { t } from './i18n'

/** A group of the Ask AI panel's actions, and the ids the app knows them by. */
export type AIGroup = { label: () => string; actions: { id: string; label: () => string }[] }

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
    label: () => t('ai.group.ask'),
    actions: [
      { id: 'explain', label: () => t('ai.action.explain') },
      { id: 'summarize', label: () => t('ai.action.summarize') }
    ]
  }
]
