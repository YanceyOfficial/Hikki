import { useSetAtom } from 'jotai'
import { useEffect, useMemo, useRef, useState } from 'react'
import { useParams } from 'react-router'

import { backend } from '#lib/backend/index'
import { debounce } from '#lib/debounce'
import { refreshDocsAtom } from '#lib/store'
import type { Doc } from '#lib/types'

export default function DocumentPage() {
  const { id } = useParams<{ id: string }>()
  const [doc, setDoc] = useState<Doc | null>(null)
  const [notFound, setNotFound] = useState(false)
  const refresh = useSetAtom(refreshDocsAtom)
  const latest = useRef<Doc | null>(null)

  const save = useMemo(
    () =>
      debounce((next: Doc) => {
        backend.saveDocument(next).then(() => refresh())
      }, 800),
    [refresh]
  )

  useEffect(() => {
    let active = true
    setDoc(null)
    setNotFound(false)
    backend
      .loadDocument(id!)
      .then((loaded) => {
        if (active) {
          setDoc(loaded)
          latest.current = loaded
        }
      })
      .catch(() => active && setNotFound(true))
    return () => {
      active = false
      save.flush()
    }
  }, [id, save])

  if (notFound) {
    return (
      <div
        data-testid="doc-not-found"
        className="text-muted-foreground p-8 text-sm"
      >
        This page doesn't exist (it may have been deleted).
      </div>
    )
  }
  if (!doc) return null

  const update = (next: Doc) => {
    setDoc(next)
    latest.current = next
    save(next)
  }

  return (
    <div
      data-testid="document-page"
      className="mx-auto w-full max-w-3xl px-8 py-10"
    >
      <input
        data-testid="doc-title"
        className="w-full bg-transparent text-4xl font-bold outline-none"
        placeholder="Untitled"
        value={doc.title}
        onChange={(e) => update({ ...doc, title: e.target.value })}
      />
      <p
        data-testid="editor-placeholder"
        className="text-muted-foreground mt-6 text-sm"
      >
        The editor lands in Phase 2.
      </p>
    </div>
  )
}
