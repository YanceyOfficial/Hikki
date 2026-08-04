import { atom } from 'jotai'

import { backend } from '#lib/backend/index'
import type { DocumentMeta } from '#lib/types'

export const docMetasAtom = atom<DocumentMeta[]>([])

export const refreshDocsAtom = atom(null, async (_get, set) => {
  set(docMetasAtom, await backend.listDocuments())
})

export type SettingsSection = 'general' | 'appearance' | 'ai' | 'logs' | 'about'

export const settingsDialogOpenAtom = atom(false)
export const settingsDialogSectionAtom = atom<SettingsSection>('general')

export const openSettingsAtom = atom(
  null,
  (_get, set, section: SettingsSection = 'general') => {
    set(settingsDialogSectionAtom, section)
    set(settingsDialogOpenAtom, true)
  }
)
