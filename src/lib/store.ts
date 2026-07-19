import { atom } from 'jotai'

import { backend } from '#lib/backend/index'
import type { DocumentMeta } from '#lib/types'

export const docMetasAtom = atom<DocumentMeta[]>([])

export const refreshDocsAtom = atom(null, async (_get, set) => {
  set(docMetasAtom, await backend.listDocuments())
})
