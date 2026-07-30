import '@blocknote/core/fonts/inter.css'
import '@blocknote/shadcn/style.css'
import {
  BlockNoteSchema,
  createCodeBlockSpec,
  type Block
} from '@blocknote/core'
import { CommentsExtension } from '@blocknote/core/comments'
// `en` (the default English dictionary) is only exported from this
// `/locales` subpath, not the package root - confirmed via
// `@blocknote/core`'s own `package.json` `exports` map, whose root `"."`
// entry re-exports `i18n/dictionary.js` (the `Dictionary` *type*) but not
// `i18n/locales/index.js` (the actual locale objects like `en`).
import { en } from '@blocknote/core/locales'
import {
  FormattingToolbar,
  FormattingToolbarController,
  getFormattingToolbarItems,
  SideMenuController,
  SuggestionMenuController,
  useCreateBlockNote
} from '@blocknote/react'
import { BlockNoteView } from '@blocknote/shadcn'
import { offset, shift, size, type Middleware } from '@floating-ui/react'
import { useTheme } from 'next-themes'
import { useEffect, useLayoutEffect, useRef, useState } from 'react'
import { createHighlighter } from 'shiki'

import { CodeBlockCopyOverlay } from '#components/code-block-copy-overlay'
import { CommentThreadsSidebar } from '#components/comment-threads-sidebar'
import { EditorSideMenu } from '#components/editor-side-menu'
import {
  HeadingAnchors,
  useHeadingAnchors
} from '#components/heading-anchor-overlay'
import { Button } from '#components/ui/button'
import { Popover, PopoverContent, PopoverTrigger } from '#components/ui/popover'
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger
} from '#components/ui/tooltip'
import { WritingToolsButton } from '#components/writing-tools-button'
import { WritingToolsPopover } from '#components/writing-tools-popover'
import { backend } from '#lib/backend/index'
import { guessLanguage } from '#lib/guess-language'
import type { VaultThreadStore } from '#lib/vault-thread-store'

interface EditorProps {
  docId: string
  initialBlocks: unknown[]
  onBlocksChange: (blocks: unknown[]) => void
  threadStore: VaultThreadStore
  commentsPortalTarget: HTMLElement | null
}

// Fixes the block-type suggestion menu ("/" or the side menu's "+" button)
// compressing itself into a sliver of space below the cursor instead of
// flipping above it, near the bottom of a scrolled document - reproduced via
// Playwright (long document, cursor pinned near the viewport's bottom edge,
// open the menu there: with far more room above the cursor than below, the
// menu still rendered squashed into the small space below it).
//
// Root cause (found by instrumenting a diagnostic middleware and inspecting
// floating-ui's own per-pass state - see the Task 13 report for the full
// trace): BlockNote's stock config runs `autoPlacement`/`flip` *before*
// `size()`, and `size()` shrinks the menu to fit by mutating the floating
// element's `maxHeight` directly. That mutation changes the floating
// element's own size, which - because `GenericPopover` watches it with
// `autoUpdate`'s `ResizeObserver` - queues another full re-run of the
// pipeline. On that re-run, `platform.getElementRects()` measures the
// element *as `size()` last left it*, i.e. already shrunk to fit whichever
// side was previously picked - so the placement logic evaluates overflow
// against that stale, artificially-small height, finds "it fits" trivially,
// and never reconsiders the other side even when it would fit the menu's
// *true* (unconstrained) height far better. This reproduced identically
// with both `autoPlacement` (BlockNote's default) and `flip` swapped in -
// it's an inherent interaction with `size()`'s DOM-mutating `apply`, not a
// quirk of either placement middleware. Directly injecting the menu's true
// unconstrained height back into the shared `rects` (floating-ui's
// documented `reset: { rects }` escape hatch) does fix the side it picks,
// but then corrupts `shift`/`size`'s *positioning* math, which also reads
// `rects.floating.height` - so the menu ends up on the right side but
// floating off-screen with a gap, sized for a height it was never actually
// given.
//
// This middleware sidesteps all of that by never touching the shared
// `rects` at all. It asks floating-ui's own `detectOverflow` a narrower
// question - "with `elementContext: 'reference'`, how much room is there
// between the cursor and the clipping boundary above vs. below it?" (see
// `detectOverflow` in `@floating-ui/core`: with that option it measures
// `rects.reference` against the boundary and ignores the floating
// element's position/size entirely) - which is exactly the "which side has
// more room" comparison this menu needs, computed independently of
// whatever height `size()` last left the menu at. It then resets
// `placement` directly if the better side differs from the current one,
// leaving `offset`/`shift`/`size` afterward to size and position the menu
// normally for whichever side won - so nothing about the actual layout math
// is disturbed, only which side is chosen.
const chooseVerticalPlacement: Middleware = {
  name: 'choose-vertical-placement',
  async fn(state) {
    const overflow = await state.platform.detectOverflow(state, {
      elementContext: 'reference',
      padding: 10
    })
    const availableAbove = -overflow.top
    const availableBelow = -overflow.bottom
    // Ties (including the common case of both sides having ample room) keep
    // "bottom", matching the default/expected placement for a menu opened
    // while typing.
    const betterSide = availableAbove > availableBelow ? 'top' : 'bottom'
    const currentSide = state.placement.split('-')[0]
    if (betterSide === currentSide) {
      return {}
    }
    return { reset: { placement: `${betterSide}-start` } }
  }
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
  threadStore,
  commentsPortalTarget
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
      // Overrides just one string in BlockNote's default English dictionary:
      // the orphaned-thread reference text shown when a comment's original
      // highlighted text can no longer be found (BlockNote's own
      // `getReferenceText` reads `editor.dictionary.comments
      // .deleted_reference_text` - see comment-threads-sidebar.tsx's
      // `Thread`/`orphaned` usage). Stock BlockNote's wording here is
      // "Original content deleted" - misleading in this app specifically,
      // since orphaning happens here on *every* reload (BlockNote's own
      // #1701: the comment mark isn't part of the persisted `Block[]` JSON
      // model, so it never survives a reload - see
      // comment-threads-sidebar.tsx's doc comment), not just genuine content
      // deletion, and the comment body itself is never actually lost
      // (`doc.threads`/`VaultThreadStore` round-trip it correctly - the
      // *position* is what's gone, not the content).
      //
      // `useCreateBlockNote`'s `dictionary` option *replaces* the whole
      // default dictionary object rather than deep-merging with it
      // (confirmed via `@blocknote/core`'s `BlockNoteEditor.ts`:
      // `this.dictionary = options.dictionary || en`) - so the full `en`
      // object is spread first and only this one nested field is
      // overridden, rather than passing just the one changed key and losing
      // every other string in the dictionary.
      dictionary: {
        ...en,
        comments: {
          ...en.comments,
          deleted_reference_text:
            "This comment's position couldn't be restored after reloading — the comment itself wasn't deleted."
        }
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

  // See heading-anchor-overlay.tsx's doc comment for why this exists and why
  // it's a DOM-sibling overlay rather than an `id` set directly on the
  // heading's own rendered node.
  const [headingAnchors, recomputeHeadingAnchors] = useHeadingAnchors(
    containerRef,
    editor
  )

  // Entry point for the Writing Tools popover (Task 10's real popover body,
  // wired in below via `WritingToolsPopover`).
  const [writingToolsOpen, setWritingToolsOpen] = useState(false)
  // The button that opens this popover (`WritingToolsButton`) is rendered by
  // BlockNote's own floating formatting toolbar - a different part of the
  // component tree than `WritingToolsPopover` below, positioned by
  // BlockNote's own floating-ui instance, not this one. So there's no
  // sibling `PopoverTrigger` this popover can anchor against (see
  // popover.tsx's doc comment on `PopoverContent`'s `anchor` prop for why
  // that matters to Base UI specifically). Snapshotting the live text
  // selection's bounding rect as a virtual anchor element the moment the
  // popover opens sidesteps that entirely - it needs no ref into BlockNote's
  // own floating toolbar DOM, and it's exactly where the user's attention
  // already is.
  const [writingToolsAnchor, setWritingToolsAnchor] = useState<{
    getBoundingClientRect: () => DOMRect
  } | null>(null)

  // The block range - and the text sent to the AI - the popover should act
  // on, captured once at the moment it opens rather than re-read live while
  // the popover is up (the user's BlockNote selection collapses the instant
  // they click into the popover's own describe-input/buttons, which live
  // outside the editor's contentEditable).
  //
  // `editor.getSelection()` returns `{ blocks: Block[] }` - ALL blocks fully
  // spanned by the current selection, in full, even when the selection only
  // highlights a sub-range within a single block. Confirmed against the
  // installed `@blocknote/core`'s own source
  // (`api/blockManipulation/selections/selection.ts`'s `getSelection()`): it
  // returns `undefined` only when `tr.selection.empty` (a collapsed, bare
  // cursor) or the selection is a NodeSelection (e.g. a selected image
  // block) - never for an ordinary, partial, within-block text selection,
  // which still walks up to the enclosing block(s) and returns them whole.
  // The `getTextCursorPosition().block` fallback below exists for that
  // genuinely-collapsed-cursor case (⌘J with no highlighted text at all),
  // not for "the selection stays within one block" - that case is already
  // covered by `getSelection()` itself.
  //
  // `text` is therefore captured as `editor.blocksToMarkdownLossy(blocks)` -
  // the full text of the captured block(s) - rather than
  // `editor.getSelectedText()`'s sub-range text. Sending only the
  // sub-range's text to the AI while `onReplace` below replaces the WHOLE
  // captured block(s) with the AI's output was a real data-loss bug: e.g.
  // selecting just "brown" inside "The quick brown fox jumps." sent only
  // "brown" to the AI, and Replace then swapped the ENTIRE paragraph for a
  // new one containing just the AI's rewrite of that one word - silently
  // deleting "The quick"/"fox jumps." everywhere else in the block.
  // `blocksToMarkdownLossy` (confirmed against `BlockNoteEditor.d.ts`:
  // `blocksToMarkdownLossy(blocks?: PartialBlock[]): string`, a synchronous
  // method) is BlockNote's own block-array-to-text serializer - it returns
  // markdown syntax rather than bare plain text, but that's an acceptable
  // (arguably better) "text to work on" for the AI: still fully readable,
  // and it preserves structure (e.g. existing bold/lists) that flattening to
  // plain text would otherwise lose.
  const [writingToolsSelection, setWritingToolsSelection] = useState<{
    blocks: Block[]
    text: string
  } | null>(null)

  const openWritingTools = () => {
    const selection = window.getSelection()
    const rect =
      selection && selection.rangeCount > 0
        ? selection.getRangeAt(0).getBoundingClientRect()
        : null
    setWritingToolsAnchor(rect ? { getBoundingClientRect: () => rect } : null)
    const blocks = editor.getSelection()?.blocks ?? [
      editor.getTextCursorPosition().block
    ]
    setWritingToolsSelection({
      blocks,
      text: editor.blocksToMarkdownLossy(blocks)
    })
    setWritingToolsOpen(true)
  }

  // `⌘J` mirrors the button's own click handler. Scoped to this editor's own
  // container (not `window`) so it doesn't fire while focus is elsewhere in
  // the app (e.g. the sidebar or a dialog). Gated on `editor.getSelection()`
  // being defined - confirmed against `@blocknote/core`'s own
  // `BlockNoteEditor.getSelection()` (delegates to
  // `_selectionManager.getSelection()`) that this returns `undefined` for a
  // collapsed selection (a bare cursor, no highlighted text) and a real
  // object once a range is selected - the same check
  // `BasicTextStyleButton`/`CreateLinkButton` use to decide whether to
  // render at all, and equivalent to the formatting toolbar's own visibility
  // condition (`FormattingToolbarExtension`'s `shouldShow`: hidden whenever
  // `tr.selection.empty`).
  useEffect(() => {
    const container = containerRef.current
    if (!container) return

    const handleKeyDown = (event: KeyboardEvent) => {
      if (
        event.metaKey &&
        event.key === 'j' &&
        editor.getSelection() !== undefined
      ) {
        event.preventDefault()
        openWritingTools()
      }
    }

    container.addEventListener('keydown', handleKeyDown)
    return () => container.removeEventListener('keydown', handleKeyDown)
  }, [editor])

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
        onChange={() => {
          onBlocksChange(editor.document)
          recomputeHeadingAnchors()
        }}
        // The built-in side menu is disabled here and remounted manually
        // below via `SideMenuController` - see editor-side-menu.tsx's doc
        // comment for why (swapping BlockNote's own react-icons SVGs for
        // lucide-react ones has no dedicated prop; this is the supported
        // customization point for replacing the default side-menu buttons).
        sideMenu={false}
        // The built-in block-type suggestion menu (opened by typing "/" or
        // by the side menu's "+" button - both route through the same
        // `SuggestionMenu` extension, see editor-side-menu.tsx's
        // `openSuggestionMenu('/')`) is disabled here too and remounted
        // manually below with corrected positioning middleware - see that
        // `SuggestionMenuController`'s doc comment for why.
        slashMenu={false}
        // The built-in formatting toolbar (shown on a text selection - Bold,
        // Italic, "Add comment", "Create link", etc.) is disabled here too
        // and remounted manually below via `FormattingToolbarController`, so
        // the Writing Tools entry point can be appended to its item list.
        // `BlockNoteView`'s own `formattingToolbar` prop is boolean-only
        // (confirmed against `@blocknote/react`'s `BlockNoteDefaultUIProps`
        // - `false` just skips mounting the default
        // `FormattingToolbarController` entirely, there's no
        // render-prop/children override on `BlockNoteView` itself) - a
        // custom toolbar's item list requires mounting
        // `FormattingToolbarController` directly, same shape as
        // `SideMenuController` above.
        formattingToolbar={false}
        shadCNComponents={{
          Button: { Button },
          Tooltip: { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger },
          Popover: { Popover, PopoverContent, PopoverTrigger }
        }}
      >
        <SideMenuController sideMenu={EditorSideMenu} />
        {/* Reimplements BlockNote's own default slash-menu wiring
            (`BlockNoteDefaultUI.tsx`: same `triggerCharacter` and
            `shouldOpen`, disabling it inside tables) but replaces
            `autoPlacement` with `chooseVerticalPlacement` (defined above -
            see its doc comment for the full root-cause trace and why a
            plain `flip()` swap isn't enough either). `offset`, `shift`, and
            the `size` callback are otherwise copied verbatim from
            BlockNote's own `SuggestionMenuController` source
            (`@blocknote/react`) so behavior is unchanged in every other
            respect (including the still-shrink-to-fit behavior on the
            genuinely-chosen side, when even that side is too small for the
            full menu). */}
        <SuggestionMenuController
          triggerCharacter="/"
          shouldOpen={(state) =>
            !state.selection.$from.parent.type.isInGroup('tableContent')
          }
          floatingUIOptions={{
            useFloatingOptions: {
              middleware: [
                offset(10),
                chooseVerticalPlacement,
                shift(),
                size({
                  apply({ elements, availableHeight }) {
                    elements.floating.style.maxHeight = `${Math.max(0, availableHeight)}px`
                  },
                  padding: 10
                })
              ]
            }
          }}
        />
        {/* Mitigates BlockNote's own #1701: the comment mark isn't part of
            the `Block[]` JSON model, so it doesn't survive a reload - this
            keeps every thread discoverable via `doc.threads` regardless.
            See comment-threads-sidebar.tsx's doc comment for the full story. */}
        <CommentThreadsSidebar portalTarget={commentsPortalTarget} />
        {/* Reimplements BlockNote's own default formatting-toolbar item list
            (`getFormattingToolbarItems()` - Bold, Italic, "Add comment",
            "Create link", etc., unchanged) with one extra button appended:
            the Writing Tools entry point. `formattingToolbar` here is a
            plain component (`FC<FormattingToolbarProps>`, confirmed against
            `FormattingToolbarController`'s own prop type) rendered with no
            props of its own, matching every other override in this file. */}
        <FormattingToolbarController
          formattingToolbar={() => (
            <FormattingToolbar>
              {getFormattingToolbarItems()}
              <WritingToolsButton
                key="writingToolsButton"
                onClick={openWritingTools}
              />
            </FormattingToolbar>
          )}
        />
      </BlockNoteView>
      {/* Not remounted on the `colorMode` key change above - it just watches
          `containerRef`'s DOM, so it naturally survives BlockNoteView being
          torn down and recreated underneath it. See its own doc comment for
          why this is a DOM overlay rather than a BlockNote extension point. */}
      <CodeBlockCopyOverlay containerRef={containerRef} />
      {/* Real DOM `id`s for table-of-contents.tsx's `FluidToc` to scroll to/
          observe - see heading-anchor-overlay.tsx's doc comment for why this
          can't just be an `id` set on the heading's own rendered node. */}
      <HeadingAnchors anchors={headingAnchors} />
      <WritingToolsPopover
        open={writingToolsOpen}
        onOpenChange={setWritingToolsOpen}
        anchor={writingToolsAnchor}
        selectedText={writingToolsSelection?.text ?? ''}
        onReplace={(text) => {
          // Replaces the blocks that were selected when the popover opened
          // with the AI's output, via BlockNote's own block-replacement API
          // - never raw `Doc.blocks` mutation (spec §14b).
          // `replaceBlocks(blocksToRemove: BlockIdentifier[], blocksToInsert:
          // PartialBlock[])` - confirmed against `BlockNoteEditor.d.ts`; a
          // full `Block` (has an `id`) satisfies `BlockIdentifier` (`{ id:
          // string } | string`) structurally, so the captured blocks can be
          // passed directly as `blocksToRemove`.
          //
          // The AI's raw text is parsed through `editor.tryParseMarkdownToBlocks`
          // (confirmed against `BlockNoteEditor.d.ts`:
          // `tryParseMarkdownToBlocks(markdown: string): Block[]`, synchronous)
          // rather than hardcoded as a single `{ type: 'paragraph', content:
          // text }` block. The system prompts in `#lib/ai/prompts` explicitly
          // ask for markdown output for several actions (e.g. "a markdown
          // table" for the `table` transform, "a bulleted list" for
          // `list`/`keyPoints`) - inserting that raw markdown syntax as one
          // literal paragraph would show the user "| a | b |" text instead of
          // an actual table. Parsing it back into real blocks applies to every
          // action's output uniformly: plain single-line text with no markdown
          // syntax parses right back into a single equivalent paragraph block
          // (confirmed against the installed source,
          // `api/parsers/markdown/parseMarkdown.ts`'s `markdownToBlocks` /
          // `markdownToHtml.ts`'s tokenizer: an unadorned line becomes one
          // `<p>` and therefore one paragraph block), so this is a strict
          // superset of the previous behavior for the existing plain-text e2e
          // fixtures.
          if (writingToolsSelection) {
            editor.replaceBlocks(
              writingToolsSelection.blocks,
              editor.tryParseMarkdownToBlocks(text)
            )
          }
          setWritingToolsOpen(false)
        }}
        onInsertBelow={(text) => {
          // `insertBlocks(blocksToInsert: PartialBlock[], referenceBlock:
          // BlockIdentifier, placement?: 'before' | 'after')` - the
          // reference is a single block, not an array, so this inserts
          // after the *last* block of the captured selection, leaving the
          // original text untouched above it. Parses the AI's output through
          // `tryParseMarkdownToBlocks` for the same reason as `onReplace`
          // above.
          if (writingToolsSelection) {
            editor.insertBlocks(
              editor.tryParseMarkdownToBlocks(text),
              writingToolsSelection.blocks[
                writingToolsSelection.blocks.length - 1
              ],
              'after'
            )
          }
          setWritingToolsOpen(false)
        }}
      />
    </div>
  )
}
