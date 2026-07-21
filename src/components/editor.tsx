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
import { createHighlighter } from 'shiki'

import { Button } from '#components/ui/button'
import { Popover, PopoverContent, PopoverTrigger } from '#components/ui/popover'
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger
} from '#components/ui/tooltip'
import { backend } from '#lib/backend/index'
import { guessLanguage } from '#lib/guess-language'

interface EditorProps {
  docId: string
  initialBlocks: unknown[]
  onBlocksChange: (blocks: unknown[]) => void
}

// Kept as a constant so the paste-detection handler below can recognize a
// code block that's still on its default language without duplicating the
// literal in two places.
const DEFAULT_CODE_LANGUAGE = 'typescript'

const SUPPORTED_CODE_LANGUAGES = [
  'typescript',
  'javascript',
  'tsx',
  'jsx',
  'vue',
  'python',
  'rust',
  'go',
  'java',
  'c',
  'cpp',
  'csharp',
  'php',
  'ruby',
  'swift',
  'kotlin',
  'sql',
  'bash',
  'json',
  'yaml',
  'toml',
  'markdown',
  'html',
  'css',
  'scss',
  'dockerfile',
  'graphql'
] as const

export function Editor({ docId, initialBlocks, onBlocksChange }: EditorProps) {
  const { resolvedTheme } = useTheme()
  const editor = useCreateBlockNote(
    {
      schema: BlockNoteSchema.create().extend({
        blockSpecs: {
          codeBlock: createCodeBlockSpec({
            indentLineWithTab: true,
            defaultLanguage: DEFAULT_CODE_LANGUAGE,
            supportedLanguages: {
              typescript: { name: 'TypeScript', aliases: ['ts'] },
              javascript: { name: 'JavaScript', aliases: ['js'] },
              tsx: { name: 'TSX' },
              jsx: { name: 'JSX' },
              vue: { name: 'Vue' },
              python: { name: 'Python', aliases: ['py'] },
              rust: { name: 'Rust', aliases: ['rs'] },
              go: { name: 'Go' },
              java: { name: 'Java' },
              c: { name: 'C' },
              cpp: { name: 'C++' },
              csharp: { name: 'C#', aliases: ['cs'] },
              php: { name: 'PHP' },
              ruby: { name: 'Ruby', aliases: ['rb'] },
              swift: { name: 'Swift' },
              kotlin: { name: 'Kotlin' },
              sql: { name: 'SQL' },
              bash: { name: 'Bash', aliases: ['sh', 'shell'] },
              json: { name: 'JSON' },
              yaml: { name: 'YAML', aliases: ['yml'] },
              toml: { name: 'TOML' },
              markdown: { name: 'Markdown', aliases: ['md'] },
              html: { name: 'HTML' },
              css: { name: 'CSS' },
              scss: { name: 'SCSS' },
              dockerfile: { name: 'Dockerfile' },
              graphql: { name: 'GraphQL' }
            },
            // This creates a highlighter, it can be asynchronous to load it
            // afterwards. The plain `shiki` package (unlike the old hand-
            // generated `shiki.bundle.ts`) lazy-loads each of these languages
            // via dynamic import internally, so listing all ~26 here doesn't
            // bundle them eagerly. `github-dark-default` is shiki 4.x's
            // bundled id for the softer GitHub dark palette (bg #0d1117 /
            // fg #e6edf3) - a single dark theme so the code block reads
            // consistently regardless of the app's light/dark mode; see the
            // matching container-chrome override in globals.css for why the
            // surrounding box needed a fix too.
            createHighlighter: () =>
              createHighlighter({
                themes: ['github-dark-default'],
                langs: [...SUPPORTED_CODE_LANGUAGES]
              })
          })
        }
      }),
      initialContent:
        initialBlocks.length > 0 ? (initialBlocks as Block[]) : undefined,
      uploadFile: async (file: File) =>
        (await backend.importAsset(docId, file)).url,
      // BlockNote's own default paste handler already turns a pasted fenced
      // markdown code block (```python ... ```) into a codeBlock with the
      // language read from the fence - that path needs no new code here.
      // The gap is pasting *unfenced* code directly into an existing code
      // block: BlockNoteEditor's `defaultPasteHandler` special-cases "cursor
      // is already inside a code block" by forcing a plain-text paste
      // (@blocknote/core's pasteExtension.ts, `isInCodeBlock` branch) before
      // it ever looks at markdown/VS Code clipboard annotations, so no
      // language detection runs for that case. Best-effort-detect it here.
      pasteHandler: ({ event, editor, defaultPasteHandler }) => {
        const handled = defaultPasteHandler()

        const { block } = editor.getTextCursorPosition()
        if (
          block.type === 'codeBlock' &&
          block.props.language === DEFAULT_CODE_LANGUAGE
        ) {
          const pastedText = event.clipboardData?.getData('text/plain')
          const guessed = pastedText ? guessLanguage(pastedText) : undefined
          if (
            guessed &&
            (SUPPORTED_CODE_LANGUAGES as readonly string[]).includes(guessed)
          ) {
            editor.updateBlock(block.id, { props: { language: guessed } })
          }
        }

        return handled
      }
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
