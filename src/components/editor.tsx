import '@blocknote/core/fonts/inter.css'
import '@blocknote/shadcn/style.css'
import {
  BlockNoteSchema,
  createCodeBlockSpec,
  type Block
} from '@blocknote/core'
import { CommentsExtension } from '@blocknote/core/comments'
import { SideMenuController, useCreateBlockNote } from '@blocknote/react'
import { BlockNoteView } from '@blocknote/shadcn'
import { useTheme } from 'next-themes'
import { useLayoutEffect, useRef } from 'react'
import { createHighlighter } from 'shiki'

import { CodeBlockCopyOverlay } from '#components/code-block-copy-overlay'
import { EditorSideMenu } from '#components/editor-side-menu'
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
import type { VaultThreadStore } from '#lib/vault-thread-store'

interface EditorProps {
  docId: string
  initialBlocks: unknown[]
  onBlocksChange: (blocks: unknown[]) => void
  threadStore: VaultThreadStore
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

export function Editor({
  docId,
  initialBlocks,
  onBlocksChange,
  threadStore
}: EditorProps) {
  const { resolvedTheme } = useTheme()
  const colorMode = resolvedTheme === 'dark' ? 'dark' : 'light'
  // See the comment on `createHighlighter` below for why only the single
  // currently-active theme is loaded here, not both.
  const codeBlockTheme = colorMode === 'dark' ? 'min-dark' : 'min-light'

  // @blocknote/core's `lazyShikiPlugin` caches the shiki highlighter (and
  // the parser built from it) on `globalThis` via `Symbol.for(...)` - a
  // *page-lifetime* global, not per-editor-instance state (see
  // `blocks-DGsP5WKr.js`: `let t = globalThis; ...; t[Cn] = t[Cn] ||
  // e.createHighlighter()`). That means whichever theme is loaded the
  // *first* time any code block is ever highlighted in this page session
  // wins forever after - neither recreating the BlockNote editor (the
  // `colorMode` dependency below) nor remounting BlockNoteView (the `key`
  // below) helps, since both still hit the same already-populated global
  // slot instead of calling our `createHighlighter` again. Empirically
  // confirmed: toggling light/dark live left code blocks rendering in the
  // *previous* mode's colors (sometimes to the point of the text being
  // unreadable against the new background) until a full page reload.
  //
  // Since BlockNote used the global symbol registry (`Symbol.for`, not a
  // module-private `Symbol()`), that slot is intentionally reachable from
  // outside its module - so clear it ourselves whenever the resolved mode
  // actually changes, forcing the next highlight to recreate the highlighter
  // with the theme that matches the *current* mode. This runs in a
  // `useLayoutEffect` (not a plain `useEffect`) so the clear is committed
  // synchronously after DOM mutations but before the browser paints -
  // before BlockNoteView's own remounted (new `key`) tree gets its first
  // paint, and before/alongside BlockNote's own plugin-init effects (which
  // also run in the layout-effect phase) that first call into the
  // highlighter.
  const lastColorModeRef = useRef<typeof colorMode | null>(null)
  useLayoutEffect(() => {
    if (
      lastColorModeRef.current !== null &&
      lastColorModeRef.current !== colorMode
    ) {
      const globalSlots = globalThis as unknown as Record<symbol, unknown>
      delete globalSlots[Symbol.for('blocknote.shikiHighlighterPromise')]
      delete globalSlots[Symbol.for('blocknote.shikiParser')]
    }
    lastColorModeRef.current = colorMode
  }, [colorMode])
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
            // afterwards. The plain `shiki` package lazy-loads each of these
            // languages via dynamic import internally, so listing all ~26
            // here doesn't bundle them eagerly.
            //
            // `min-light`/`min-dark` are shiki's minimal, low-saturation
            // themes - closer to this app's soft palette than the more
            // vivid `github-*` themes. BlockNote's own highlight plugin
            // (`prosemirror-highlight`'s shiki adapter) always tokenizes
            // with `highlighter.getLoadedThemes()[0]` - there's no per-
            // render theme switch. Only ever loading the *one* theme that
            // matches the current mode (rather than both, reordered) avoids
            // relying on that array-order behavior: empirically, loading
            // both `min-light` and `min-dark` into the same highlighter and
            // reordering which came first still left some default/plain
            // tokens resolving against the *other* theme's color (e.g. a
            // dark-mode block rendering plain punctuation in min-light's
            // near-black `#24292e` - invisible against a dark background).
            // `codeBlockTheme` (closed over `colorMode`, in the dependency
            // array below) re-creates the whole editor - and therefore a
            // fresh highlighter loaded with only the correct theme -
            // whenever the app's light/dark mode flips.
            createHighlighter: () =>
              createHighlighter({
                themes: [codeBlockTheme],
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
      },
      // Registers BlockNote's open-source Comments extension (additive -
      // BlockNote merges this list into its own default extensions, it
      // doesn't replace them; see `ExtensionManager`'s constructor in
      // `@blocknote/core`). This alone is enough to light up comments end
      // to end: the default `FormattingToolbar` already renders
      // `AddCommentButton` (it self-hides via `editor.getExtension`
      // ("comments") when this extension isn't registered - see
      // `@blocknote/react`'s `AddCommentButton.tsx`), and `BlockNoteView`
      // always renders `FloatingComposerController`/`FloatingThreadController`
      // once the extension is present (`BlockNoteDefaultUI.tsx`) - no
      // additional wiring or custom toolbar needed here.
      extensions: [
        CommentsExtension({
          threadStore,
          // v1 scope: a single local user, no auth - every comment author
          // resolves to the same fixed identity (see VaultThreadStore's
          // `LOCAL_USER_ID`).
          resolveUsers: async (userIds) =>
            userIds.map((id) => ({ id, username: 'You', avatarUrl: '' }))
        })
      ]
    },
    // `colorMode` is included so the editor (and its code-block highlighter)
    // is recreated when the app's light/dark mode changes - see the
    // `codeBlockThemes` comment above. `initialContent` is re-read from the
    // latest `initialBlocks` on that remount, and `onBlocksChange` keeps
    // that prop in sync on every edit (src/pages/document-page.tsx), so no
    // content is lost - only the cursor position/undo stack reset, which is
    // an acceptable trade-off for an explicit theme toggle. `threadStore` is
    // included too, though in practice it's already stable for as long as
    // `docId` is unchanged (document-page.tsx memoizes it on `doc.id`).
    [docId, colorMode, threadStore]
  )
  const containerRef = useRef<HTMLDivElement | null>(null)
  return (
    // `relative` anchors `CodeBlockCopyOverlay`'s absolutely-positioned
    // overlay layer (a DOM sibling of BlockNoteView, not a descendant of its
    // contentEditable tree - see that component's doc comment for why).
    <div data-testid="editor" className="relative mt-4" ref={containerRef}>
      <BlockNoteView
        // BlockNote's code-block highlighter is cached on internal
        // ProseMirror plugin state that survives a mere `editor` prop swap -
        // toggling light/dark live (as opposed to a fresh page load already
        // in the target mode) left the *first* mode's shiki theme cached and
        // in use even after `editor` was recreated with the other theme.
        // Forcing a full remount via `key` sidesteps that stale-plugin-state
        // cache entirely.
        key={colorMode}
        editor={editor}
        theme={colorMode}
        onChange={() => onBlocksChange(editor.document)}
        // The built-in side menu is disabled here and remounted manually
        // below via `SideMenuController` - see editor-side-menu.tsx's doc
        // comment for why (swapping BlockNote's own react-icons SVGs for
        // lucide-react ones has no dedicated prop; this is the supported
        // customization point for replacing the default side-menu buttons).
        sideMenu={false}
        shadCNComponents={{
          Button: { Button },
          Tooltip: { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger },
          Popover: { Popover, PopoverContent, PopoverTrigger }
        }}
      >
        <SideMenuController sideMenu={EditorSideMenu} />
      </BlockNoteView>
      {/* Not remounted on the `colorMode` key change above - it just watches
          `containerRef`'s DOM, so it naturally survives BlockNoteView being
          torn down and recreated underneath it. See its own doc comment for
          why this is a DOM overlay rather than a BlockNote extension point. */}
      <CodeBlockCopyOverlay containerRef={containerRef} />
    </div>
  )
}
