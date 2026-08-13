import { atom } from 'jotai'

import { backend } from '#lib/backend/index'
import type { DashboardStats, DocumentMeta } from '#lib/types'

export const docMetasAtom = atom<DocumentMeta[]>([])

export const refreshDocsAtom = atom(null, async (_get, set) => {
  set(docMetasAtom, await backend.listDocuments())
})

export type SettingsSection = 'general' | 'ai' | 'logs' | 'about'

export const settingsDialogOpenAtom = atom(false)
export const settingsDialogSectionAtom = atom<SettingsSection>('general')

export const openSettingsAtom = atom(
  null,
  (_get, set, section: SettingsSection = 'general') => {
    set(settingsDialogSectionAtom, section)
    set(settingsDialogOpenAtom, true)
  }
)

export const dashboardStatsAtom = atom<DashboardStats | null>(null)
export const recentDocsAtom = atom<DocumentMeta[]>([])

export const refreshDashboardAtom = atom(null, async (_get, set) => {
  const [stats, recent] = await Promise.all([
    backend.getDashboardStats(),
    backend.getRecentDocuments(8)
  ])
  set(dashboardStatsAtom, stats)
  set(recentDocsAtom, recent)
})
