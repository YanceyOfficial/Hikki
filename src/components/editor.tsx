import '@blocknote/core/fonts/inter.css'
import '@blocknote/shadcn/style.css'
import {
  BlockNoteSchema,
  createCodeBlockSpec,
  type Block
} from '@blocknote/core'
import { useCreateBlockNote } from '@blocknote/react'
import { BlockNoteView } from '@blocknote/shadcn'
import { useTheme } from 'next-themes'

import { Button } from '#components/ui/button'
import { Popover, PopoverContent, PopoverTrigger } from '#components/ui/popover'
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger
} from '#components/ui/tooltip'
import { backend } from '#lib/backend/index'
import { createHighlighter } from '#lib/shiki.bundle'

interface EditorProps {
  docId: string
  initialBlocks: unknown[]
  onBlocksChange: (blocks: unknown[]) => void
}

export function Editor({ docId, initialBlocks, onBlocksChange }: EditorProps) {
  const { resolvedTheme } = useTheme()
  const editor = useCreateBlockNote(
    {
      schema: BlockNoteSchema.create().extend({
        blockSpecs: {
          codeBlock: createCodeBlockSpec({
            indentLineWithTab: true,
            defaultLanguage: 'typescript',
            supportedLanguages: {
              typescript: {
                name: 'TypeScript',
                aliases: ['ts']
              },
              javascript: {
                name: 'JavaScript',
                aliases: ['js']
              },
              vue: {
                name: 'Vue'
              }
            },
            // This creates a highlighter, it can be asynchronous to load it afterwards
            createHighlighter: () =>
              createHighlighter({
                themes: ['github-dark', 'github-light'],
                langs: []
              })
          })
        }
      }),
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
        theme={resolvedTheme === 'dark' ? 'dark' : 'light'}
        onChange={() => onBlocksChange(editor.document)}
        shadCNComponents={{
          Button: { Button },
          Tooltip: { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger },
          Popover: { Popover, PopoverContent, PopoverTrigger }
        }}
      />
    </div>
  )
}
