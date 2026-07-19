import { useSetAtom } from 'jotai'
import { useEffect, useMemo, useState } from 'react'
import { useParams } from 'react-router'

import { Editor } from '#components/editor'
import { PageHeader } from '#components/page-header'
import { backend } from '#lib/backend/index'
import { debounce } from '#lib/debounce'
import { refreshDocsAtom } from '#lib/store'
import type { Doc } from '#lib/types'

export default function DocumentPage() {
  const { id } = useParams<{ id: string }>()
  const [doc, setDoc] = useState<Doc | null>(null)
  const [notFound, setNotFound] = useState(false)
  const refresh = useSetAtom(refreshDocsAtom)

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

  const update = (patch: Partial<Doc>) => {
    setDoc((prev) => {
      if (!prev) return prev
      const next = { ...prev, ...patch }
      save(next)
      return next
    })
  }

  return (
    <div
      data-testid="document-page"
      className="mx-auto w-full max-w-3xl px-8 py-10"
    >
      <PageHeader doc={doc} onPatch={update} />
      <Editor
        key={doc.id}
        docId={doc.id}
        initialBlocks={doc.blocks}
        onBlocksChange={(blocks) => update({ blocks })}
      />
    </div>
  )
}
