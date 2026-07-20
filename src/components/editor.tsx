import '@blocknote/core/fonts/inter.css'
import '@blocknote/shadcn/style.css'
import type { Block } from '@blocknote/core'
import { useCreateBlockNote } from '@blocknote/react'
import { BlockNoteView } from '@blocknote/shadcn'

import { backend } from '#lib/backend/index'

interface EditorProps {
  docId: string
  initialBlocks: unknown[]
  onBlocksChange: (blocks: unknown[]) => void
}

export function Editor({ docId, initialBlocks, onBlocksChange }: EditorProps) {
  const editor = useCreateBlockNote(
    {
      initialContent:
        initialBlocks.length > 0 ? (initialBlocks as Block[]) : undefined,
      uploadFile: async (file: File) =>
        (await backend.importAsset(docId, file)).url
    },
    [docId]
  )
  return (
    <div data-testid="editor" className="mt-4">
      <BlockNoteView
        editor={editor}
        onChange={() => onBlocksChange(editor.document)}
      />
    </div>
  )
}
