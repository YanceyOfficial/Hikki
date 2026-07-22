import { useSetAtom } from 'jotai'
import { useEffect, useMemo, useState } from 'react'
import { useParams } from 'react-router'

import { Editor } from '#components/editor'
import { EditorBoundary } from '#components/editor-boundary'
import { PageHeader } from '#components/page-header'
import { backend } from '#lib/backend/index'
import { debounce } from '#lib/debounce'
import { refreshDocsAtom } from '#lib/store'
import type { Doc } from '#lib/types'
import {
  VaultThreadStore,
  type SerializedThread
} from '#lib/vault-thread-store'

export default function DocumentPage() {
  const { id } = useParams<{ id: string }>()
  const [doc, setDoc] = useState<Doc | null>(null)
  const [notFound, setNotFound] = useState(false)
  const refresh = useSetAtom(refreshDocsAtom)
  // Shared right-margin rail DOM node: tracked via a callback ref (not a
  // plain `useRef`) so its value change itself triggers a re-render, letting
  // `Editor`/`CommentThreadsSidebar` react to the node becoming available
  // after the rail `<div>` first mounts. This is the single shared rail slot
  // for the page - Task 12 (table of contents) stacks its own section inside
  // this same container later, so nothing here should assume comments are
  // its only consumer.
  const [pageRailNode, setPageRailNode] = useState<HTMLDivElement | null>(null)

  const save = useMemo(
    () =>
      debounce((next: Doc) => {
        backend.saveDocument(next).then(() => refresh())
      }, 800),
    [refresh]
  )

  // One `VaultThreadStore` per document, seeded once from `doc.threads` (the
  // shape the store expects, an array - `doc.threads` is `unknown` on `Doc`
  // and even defaults to `{}` on freshly-created documents, hence the
  // `Array.isArray` guard) and rebuilt only when the document itself
  // changes, not on every keystroke/comment edit. `onChange` patches
  // `threads` back into `doc` through the exact same debounced autosave
  // path `blocks`/`title` already use (see `update` below - not called
  // directly here since it's declared after this hook and referencing it
  // here would hit its temporal-dead-zone on first render).
  const threadStore = useMemo(() => {
    const initial =
      doc && Array.isArray(doc.threads)
        ? (doc.threads as SerializedThread[])
        : []
    return new VaultThreadStore(initial, (serialized) => {
      setDoc((prev) => {
        if (!prev) return prev
        const next = { ...prev, threads: serialized }
        save(next)
        return next
      })
    })
  }, [doc?.id])

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
      className="mx-auto flex w-full max-w-7xl gap-10 px-12 py-12"
    >
      <div className="mx-auto max-w-3xl min-w-0 flex-1">
        <PageHeader doc={doc} onPatch={update} />
        <EditorBoundary>
          <Editor
            key={doc.id}
            docId={doc.id}
            initialBlocks={doc.blocks}
            onBlocksChange={(blocks) => update({ blocks })}
            threadStore={threadStore}
            commentsPortalTarget={pageRailNode}
          />
        </EditorBoundary>
      </div>
      <div
        ref={setPageRailNode}
        data-testid="page-rail"
        className="hidden w-[300px] shrink-0 2xl:block"
      />
    </div>
  )
}
