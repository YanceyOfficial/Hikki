import { useSetAtom } from 'jotai'
import { useEffect, useMemo, useState } from 'react'
import { useParams } from 'react-router'

import { Editor } from '#components/editor'
import { EditorBoundary } from '#components/editor-boundary'
import { PageHeader } from '#components/page-header'
import { TableOfContents } from '#components/table-of-contents'
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
  // Small `fixed`-positioned anchor DOM node for the floating comments badge:
  // tracked via a callback ref (not a plain `useRef`) so its value change
  // itself triggers a re-render, letting `Editor`/`CommentThreadsSidebar`
  // react to the node becoming available after the anchor `<div>` first
  // mounts. `CommentThreadsSidebar` (mounted deep inside `Editor`'s
  // `<BlockNoteView>`) paints its trigger button + popover into this node via
  // `ReactDOM.createPortal` - see its own doc comment for why it needs a
  // portal at all (BlockNoteContext/ComponentsContext access) rather than
  // just rendering here directly.
  const [commentsAnchorNode, setCommentsAnchorNode] =
    useState<HTMLDivElement | null>(null)

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
    <div data-testid="document-page" className="px-12 py-12">
      <div className="mx-auto max-w-3xl min-w-0">
        <PageHeader doc={doc} onPatch={update} />
        <EditorBoundary>
          <Editor
            key={doc.id}
            docId={doc.id}
            initialBlocks={doc.blocks}
            onBlocksChange={(blocks) => update({ blocks })}
            threadStore={threadStore}
            commentsPortalTarget={commentsAnchorNode}
          />
        </EditorBoundary>
      </div>
      <TableOfContents blocks={doc.blocks} />
      {/* Floating anchor for CommentThreadsSidebar (mounted inside
          Editor/BlockNoteView) to portal its trigger button + popover into -
          see the comment on `commentsAnchorNode` above. Empty until that
          portal paints into it, and renders nothing itself when there are no
          threads (CommentThreadsSidebar's own empty-state check). */}
      <div
        ref={setCommentsAnchorNode}
        data-testid="comments-anchor"
        className="fixed right-6 bottom-6 z-40"
      />
    </div>
  )
}
