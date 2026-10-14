# CLAUDE.md

Guidance for Claude Code (and any agent or human) working in this repository.

## Project Overview

Hikki is a Notion-like, local-first notebook for macOS, iPhone and iPad. The shell is SwiftUI; the page editor is
Tiptap 3 (React 19 + Tailwind CSS v4) running in a single long-lived `WKWebView` per window, bridged to Swift.
Tuist generates the Xcode project; bun manages the web workspace (`editor/`).

## Project Constraints (read first)

These rules are mandatory. Automated ones are noted.

- **Design tokens only.** Colors, spacing, radii, text sizes and component sizes come from `design/tokens.json`
  (shadcn/ui semantic color names, Tailwind scale names). Regenerate with `make tokens`; never edit
  `HikkiUI/Sources/Generated/DesignTokens.swift` or `editor/src/theme.css` by hand. Swift uses `Theme.*`, `Spacing.*`,
  `Radius.*`, `Size.*`, `.font(.hk(.sm))`; the web uses Tailwind classes (`bg-background`, `text-muted-foreground`,
  `rounded-md`, `p-2.5`). _Enforced by `make lint-design` (`scripts/lint-design.sh`)._ A justified exception carries
  a `design-lint: allow` comment on the same line.
- **Motion.** Everything that appears, leaves or reacts moves the same way, from the `motion` tokens. Web surfaces
  (menus, popovers, tooltips, panels, the outline list) take `hk-pop` — mounted when shown: `FloatingLayer` adds it,
  the Base UI popups in `editor/src/components/ui/` carry it, a React panel stays mounted through its leave with
  `usePresence` (`editor/src/components/floating.tsx`) — or `hk-pop-toggle` + `data-open` when they stay mounted. Lists
  mark the selected row with one gliding surface (`editor/src/components/gliding-highlight.tsx`, rows `relative` +
  `data-index`), block tints fade (`.tiptap [data-id]`), hover fades and the 97 % press live in the shadcn `Button` /
  `Toggle` (restyled in `editor/src/components/ui/`); Swift uses `Motion.easeOut()`. No per-component durations, easings or
  tw-animate classes. _Enforced by `make lint-design`._
- **Reusable UI lives in `HikkiUI`** (no app state: plain values + closures, a `#Preview` each, listed in the DEBUG
  gallery `Hikki/Sources/ComponentGallery.swift`, launch argument `-HikkiGallery`). Native components follow the same
  look as the web's shadcn style (`base-vega`: `Radius.md` controls, `Theme.*` colors).
- **Web UI primitives are shadcn** (style `base-vega`, Base UI primitives, hugeicons; config in `editor/components.json`,
  components in `editor/src/components/ui/`). Add components with `cd editor && bun run ui:add <name>` (the shadcn CLI,
  then oxfmt). Prefer a shadcn component over a hand-rolled one;
  editor-specific pieces live in `editor/src/components/`. Fields, buttons, toggles, tooltips and popovers are always the shadcn
  components (`Input`, `InputGroup`, `Textarea`, `Button`, `Toggle`, `Kbd`…) restyled with classes — never a bare
  `<input>` / `<button>`; Phosphor icons are imported by their `…Icon` names. Files under `editor/src` are
  kebab-case (`editor/src/components/find-panel.tsx`; the component inside stays PascalCase), and a folder holds either
  `.tsx` or `.ts`, never both: React lives in `editor/src/components/` and `editor/src/page/`; `editor/src/core/`
  (bridge, protocol, editor setup, catalogs), `editor/src/extensions/`, `editor/src/lib/` and `editor/src/hooks/` are
  plain TypeScript — an extension that shows a React panel calls the component file's `render*` helper
  (`renderFindPanel`, `renderTableOverlay`…) instead of holding JSX. Class recipes that aren't a component
  (`.hk-floating`, `.hk-column`) live in `editor/src/style.css`, and `cn` is shadcn's own `cn` npm package, imported
  `from 'cn'` as the generated components do (`editor/src/lib/utils.ts` is the one-line re-export `shadcn init` writes).
- **Icons go through one list** (`design/icons.json`, `make icons`). The native shell draws SF Symbols (each icon's
  `"sf"` name; the generated `Icon` enum, `IconView` / `IconLabel`, `Icon.glyph` for system-sized spots), falling
  back to the bundled Phosphor asset where there is no symbol; the web editor uses `@phosphor-icons/react`. No raw
  `Image(systemName:)` / `systemImage:` — _enforced by `make lint-design`_.
- **Keyboard shortcuts come from one registry.** `design/shortcuts.json` → `make shortcuts` generates
  `Hikki/Sources/Generated/Shortcuts.swift` (`Shortcut.x.keyboardShortcut` / `.display`) and
  `editor/src/generated/shortcuts.ts` (`matchesShortcut`, `shortcutLabel`, `tiptapShortcut` in
  `editor/src/core/shortcuts.ts`). Each entry says who binds it: `app` (native menu), `editor` (the page; menus only
  display it) or `both`. No literal key equivalents or "⌘X" labels in code; the generator refuses two shortcuts on
  the same keys. _Checked by `make lint-design`._ Users rebind any of them in Settings → Shortcuts: the overrides
  (`HikkiCore/Sources/Shortcuts/KeyCombo.swift` — what may be bound, conflicts) live in
  `Hikki/Sources/ShortcutStore.swift` (UserDefaults; `Shortcut.keyboardShortcut` / `.display` read it, observed by the
  menus) and reach the page through `window.hikki.setShortcuts`, where `ShortcutOverrides`
  (`editor/src/extensions/shortcuts.ts`) runs a rebound shortcut on its new keys ahead of the default-bound keymaps.
- **Copy language.** User-facing strings are keys, never literals: native `app:<area>.<element>` keys in
  `Hikki/Resources/Localization/Localizable.xcstrings` (interpolations become `%@`, e.g. `app:page.edited %@`); web
  `t('area.key')` with catalogs in `editor/src/locales/`. English is the source; zh-Hans must be complete. The native
  side tells the editor its language (`window.hikki.setLocale`). _Enforced by `make lint-l10n`
  (`scripts/l10n-audit.mjs`): missing / unused keys, untranslated values, placeholder mismatches, literal UI text._
- **Secrets stay server-side.** Third-party API keys (Unsplash) live only in the BFF (`bff/`, Hono on Vercel).
  Unsplash rules: hotlink `urls`, attribute the photographer with utm links, report picks via the download endpoint.
- **Pre-commit gate.** `.husky/pre-commit` runs lint-staged (oxlint + oxfmt for web files, `swift-format` for
  Swift), `make lint-design lint-docs lint-l10n`, the editor + BFF typecheck and web unit tests. `make check` adds the Swift tests and both
  platform builds. Don't `--no-verify`.
- **Tests with every change.** Web logic: vitest in `editor/test/`. Swift data/logic: Swift Testing in
  `HikkiCore/Tests/`. User-visible flows: XCUITest in `HikkiUITests/` (look elements up by accessibility identifier).
  A bug fix comes with a test that fails without the fix — check that it does.
- **Bridge protocol.** Messages are defined twice — `editor/src/core/protocol.ts` and
  `HikkiCore/Sources/Bridge/BridgeMessage.swift` — and versioned by `PROTOCOL_VERSION` / `BridgeProtocol.version`.
  Change both together and bump both.
- **Split write paths.** `DocumentStore.saveContent` writes only editor-owned columns; metadata (icon, cover,
  favorite, lock, trash) has its own methods, so a late debounced autosave can never revert it. The editor's `flush()`
  returns nothing when the page wasn't edited — viewing a page must never bump its edited time.
- **Concurrency.** The app and `HikkiUI` default to MainActor isolation. Anything AppKit/UIKit may call off the main
  thread (dynamic color providers, KVO callbacks) must be `nonisolated` / `@Sendable`.
- **Logs never contain page content.** Use `Log.info` / `Log.warn` / `Log.error` with a category; IDs and counts only.
- **Keep this file current.** Architecture or directory changes update CLAUDE.md in the same commit.
  _Paths are checked by `make lint-docs` (`scripts/check-claude-md.mjs`)._

## Commands

```sh
make bootstrap      # bun install + tuist install (first clone)
make generate       # build the editor bundle and generate Hikki.xcworkspace
make tokens         # regenerate design tokens after editing design/tokens.json
make lint           # oxlint + swift-format lint --strict
make fmt            # oxfmt + swift-format format
make test           # lint, format check, design + docs lint, web + BFF typecheck/tests, HikkiCore tests (macOS)
make test-ui-ios    # XCUITest on the iOS simulator
make test-ui-mac    # XCUITest on macOS — takes over the screen; don't run while someone is using the Mac
make check          # test + macOS and iOS builds
cd editor && bun run dev   # the editor alone in a browser (console-logging bridge)
cd bff && bun run dev      # the BFF locally (needs UNSPLASH_ACCESS_KEY); the editor reads VITE_HIKKI_BFF_URL (editor/.env.*; prod: unsplash.yancey.app)
```

## Code Structure

```
design/tokens.json            design tokens (single source)
design/icon/                  app icon (Hi✦): layered SVGs for Icon Composer (generate.mjs → hi-star/, --all for alternatives)
design/logo/                  wordmark + lockups (generate.mjs: text → outlines with fontkit, sparkle i-dot)
scripts/gen-tokens.mjs        tokens → Swift + Tailwind theme
scripts/lint-design.sh        no literal colors/fonts/spacing/radii in view code
Configs/Version.xcconfig      MARKETING_VERSION / CURRENT_PROJECT_VERSION
Project.swift                 Tuist manifest (targets: Hikki, HikkiCore, HikkiSearch, HikkiUI + their tests, HikkiUITests)
Hikki/Sources/                app: SwiftUI shell, navigation (tabs), sidebar, page bar, search, editor host
Hikki/Resources/AppIcon.icon  Icon Composer document (merged from design/icon/hi-star; actool renders all sizes)
HikkiCore/Sources/            framework: Store (GRDB/SQLite, page tree, assets, tabs model), Text (Japanese readings),
                              Bridge (protocol, JSONValue), Logging (file log, MetricKit crash collection),
                              Layout (split view geometry), Shortcuts (KeyCombo)
HikkiSearch/Sources/          framework: the search engine — its own SQLite index (trigram FTS5, BM25), query parsing,
                              ranking, pinyin keys, fuzzy titles; tests in HikkiSearch/Tests/
HikkiUI/Sources/              framework: reusable SwiftUI components + Theme
editor/src/                   web editor: main.tsx + style.css; each folder below holds only .tsx or only .ts
editor/src/core/              bridge, protocol, transport, editor setup, block catalog, i18n, shortcuts, links, page store
editor/src/extensions/        Tiptap extensions (.ts; React panels are drawn through the components' render* helpers)
editor/src/components/        editor UI (.tsx): menus, panels, the floating layer, icons (kebab-case files)
editor/src/components/ui/     shadcn components (generated via `bun run ui:add`)
editor/src/page/              page header, cover picker, outline (.tsx)
editor/src/hooks/             React hooks (useEditorSnapshot)
editor/src/lib/               data helpers: cover catalog, Unsplash client, emoji data; shadcn's utils re-export
editor/test/                  vitest
bff/                          backend-for-frontend (Hono, Vercel): Unsplash proxy, YouTube embed shim; tests with `bun test`
HikkiUITests/                 XCUITest flows
```

## Gotchas

- **swiftly** on `PATH` shadows Xcode's Swift and breaks `tuist install`; the Makefile strips it.
- `make test-core` (tuist test) regenerates a test-only workspace; the target regenerates the full one afterwards.
- **Window chrome is native**: the system `NavigationSplitView` and window toolbar (Liquid Glass groups: back/forward
  `ControlGroup`, tabs, page actions). Don't reintroduce a custom title bar — an earlier one needed an isa-swizzled
  layout hook to keep the traffic lights in place. The page scrolls under the toolbar (WKWebView
  `obscuredContentInsets` on macOS, an explicit scroll inset on iOS).
- **Sidebar**: Mac/iPad draw our own rows in a `LazyVStack` (`Hikki/Sources/SidebarView.swift`) — a native `List`
  paints selection in the system accent (not the colour tone) and swallowed row drops on iPad; iPhone keeps a `List`.
  Fills on the sidebar use resolved colours (dynamic ones picked up the active window's vibrancy).
- **Data directory**: `HIKKI_DATA_DIR` overrides it (UI tests, demos). DEBUG hooks: `HIKKI_OPEN_TABS=a,b`,
  `HIKKI_OPEN_SEARCH`, `HIKKI_OPEN_FIND`, `HIKKI_DEBUG_NAV=a,b,c`, `HIKKI_DEBUG_SPOTLIGHT_QUERY=<text>` (logs the page ids Spotlight ranks), `HIKKI_OPEN_FILE=<asset>` (the PDF viewer), `HIKKI_OPEN_SPLIT=<page id>|file:<asset>|picker` (split view), `HIKKI_DEBUG_SIDEBAR` (hide + show the split view sidebar), `HIKKI_OPEN_SETTINGS`, `HIKKI_ACTIVATE`, `HIKKI_WORKSPACE=<name>` (seeds a device workspace, skips onboarding;
  UI tests set it by default — pass `workspace: nil` to `launch()` to test onboarding).
- **Storage (option C)**: the workspace folder is the source of truth — one JSON file per page
  (`HikkiCore/Sources/Store/PageFile.swift`: `pages/<id>.json`, format-versioned, content as JSON); SQLite is a
  rebuildable cache/index. `HikkiCore/Sources/Store/WorkspaceSync.swift` reconciles on launch and app activation
  (newer side wins; a missing file deletes the page only if it was synced before — `pageFileState`) and writes every
  committed page change through (a GRDB transaction observer). It also watches `pages/` (a dispatch source;
  unchanged files are skipped by modification date + size) and posts `pagesChangedOnDisk`, so an open editor
  reloads a page another device changed (`window.hikki.reload`, declined while it has unsaved edits). While files
  are still downloading (iCloud placeholders / half-written files) it passes again with backoff — kqueue events are
  unreliable in iOS file-provider folders. Assets live in `<folder>/assets`. **Conflict copies**: nothing two devices
  wrote is lost. When iCloud kept several versions of a page file (`NSFileVersion`, behind the `FileVersionStore`
  protocol in `HikkiCore/Sources/Store/FileConflicts.swift`; tests fake it), the newest edit wins as the page and every
  other version that says something different becomes a sibling page titled "<title> (conflicted copy <device>,
  <date>)" (`ConflictCopy`), then the conflicts are marked resolved. The same happens when the row and the file both
  changed since they last agreed — `pageFileState.baseUpdatedAt`, set on every write and import (`syncBases`).
- **Page history** (`HikkiCore/Sources/Store/PageHistory.swift`): versions are files in the workspace folder,
  `history/<page id>/<yyyyMMddTHHmmss.SSSZ>.json` (format-versioned, atomic writes), so they sync like pages. Policy
  (`PageHistoryPolicy`, Notion-like): the first save of an editing session (10 quiet minutes) keeps the page _as it
  was_ — `EditorController.save` calls `recordBeforeEdit`, which reads the row only when a session starts and keeps
  nothing for an unchanged or empty page (viewing never adds history); a page another device replaces is kept first
  (`WorkspaceSync.Options.willReplace`); restoring keeps the current page first (`snapshot(reason: .restore)`). Pruned
  on every write: everything from the last 24 h, then the newest per day, nothing past 30 days; a page deleted for good
  takes its history along (`onDeleted`). UI: page ⋯ → Page History… (`Hikki/Sources/PageHistoryView.swift`) lists
  versions beside a native preview — `TextBlock`/`PageDiff` (`HikkiCore/Sources/Store/PageDiff.swift`) flatten both
  versions to blocks and diff them block by block, then word by word (CJK by character), drawn by HikkiUI's
  `VersionDiffView`. Restore writes through `saveContent` + `setIcon`/`setCover` and reloads open editors.
  DEBUG: `HIKKI_HISTORY_INTERVAL=<s>` shortens the session (UI tests).
- **Import / export** (`Hikki/Sources/PageTransfer.swift`): the editor converts, in its own schema
  (`editor/src/core/convert.ts`: Tiptap's official `@tiptap/markdown`, HTML through the schema's parse/render rules;
  blocks with no Markdown form export as their container's blocks or their rendered HTML) — `window.hikki.exportPage`
  / `importDocument`. Export (page ⋯ → Export: Markdown, HTML, PDF, JSON = the page file) is packed by
  `PageExport` (`HikkiCore/Sources/Store/PageExport.swift`): one file, or — when the page attaches files — a folder
  with the document and `assets/` it links into relatively; saved with `.fileExporter` on both platforms. PDF renders
  the HTML export in an offscreen light web view (`createPDF`: one tall page). Import (File → Import…, the workspace
  menu) takes .md/.html/.txt as new top-level pages; whatever the file holds, the body fits the schema (text fallback).
  Not yet: dropping files on the sidebar, relative images in imported Markdown. DEBUG: `HIKKI_EXPORT_DIR=<folder>`
  skips the save panel, `HIKKI_IMPORT_FILE=<path>` imports at launch (UI tests).
- **Workspace identity** lives in the folder (a workspace.json next to `pages/`: id, name, icon — `WorkspaceIdentity`); the per-device
  record (`AppPaths.workspace`) only adds the location. A device picking a folder that has one _opens_ that workspace
  (onboarding says so), and a newer identity from another device replaces the local name/icon on activation. Settings →
  Storage → Change folder re-points a workspace (`AppModel.changeLocation`: synced marks cleared, local pages written
  out, the folder's imported — nothing deleted).
- **Popups close one way**: every `FloatingLayer` opened with `onDismiss` (`editor/src/components/floating.tsx`) joins
  one dismiss bus — a single pair of document listeners: Escape and a press outside every open layer dismiss the newest
  one, and the opener says what that means (the slash and block menus exit, the math and ruby panels cancel). No popup
  installs its own outside-click or Escape listener. Base UI popups (shadcn) bring their own.
- **Editor menus**: `editor/src/core/blocks.ts` is the one block catalog (groups, Markdown shortcuts, `turnInto`, `isActive`)
  behind the "/" menu (`editor/src/components/slash-menu.tsx`) and the selection menu's "Turn into"
  (`editor/src/components/selection-menu.tsx`, positioned by Tiptap's BubbleMenu; its side panels stay inside the menu element
  or BubbleMenu hides on blur). Text/background colors are stored as palette names (`editor/src/extensions/colors.ts`) and
  styled from the `ink-*` / `wash-*` tokens — never raw CSS colors in the document.
- **Code blocks** (`editor/src/extensions/code-block.ts`): lowlight with the `common` grammars, colored by the
  `syntax-*` tokens (Xcode's Default Light/Dark); new blocks use the last picked language
  (`editor/src/extensions/code-languages.ts`). "Auto-detect" (`language: auto`) guesses with our own signatures
  (`editor/src/extensions/code-detect.ts` — highlight.js's guess ties CSS/JS/Python on short snippets) and names the
  guess in the header; the same guess feeds lowlight, so colours and label agree. Node views are plain DOM with small React roots for controls (the editor
  is the core `Editor`, not `@tiptap/react`).
- **Block controls** (`editor/src/extensions/block-controls.ts`, units in `editor/src/extensions/block-units.ts`): our
  own + / ⋮⋮ handle on pointer events (HTML5 drag-and-drop is unreliable in WebKit), centred on the block's first line;
  drag shows a ghost and a drop line (side edges make columns); a click opens `editor/src/components/block-menu.tsx`. Fine
  pointers only. Block colours are `blockColor` / `blockBackground` attributes. Block-level highlights (drag
  source, the block a menu is open for) are node decorations from `editor/src/extensions/block-highlight.ts` —
  never classes on the node's DOM, which ProseMirror drops on redraw.
- **Rich blocks**: toggles (`editor/src/extensions/toggle.ts`; open/closed is not stored, so opening never saves),
  callouts, KaTeX formulas (`editor/src/extensions/math.ts`; our panel replaces Tiptap's `prompt()`), tables
  (`editor/src/extensions/table.ts` + `editor/src/extensions/table-ops.ts`, controls drawn by
  `editor/src/components/table-overlay.tsx`) and columns (`editor/src/extensions/columns.ts`: schema needs 2–5 columns, so
  removing one of two replaces the row; dragging a block onto another's side edge makes a row).
- **Network images** load like exodus's (`editor/src/components/lazy-load-image.tsx`: skeleton, fade in, an icon on
  failure) — covers and the Unsplash grid use the component; body images get the same through
  `editor/src/extensions/image-loading.ts` (`data-load` states styled in `editor/src/style.css`; Tiptap's resizable view hides its
  container until an image loads, so the CSS shows it meanwhile).
- **Covers**: the stored value is `gradient:<id>` or an image URL, and an image's vertical position rides along
  as a `#y=<0-100>` fragment (`editor/src/lib/covers.ts`: `coverPosition`, `withCoverPosition`), so the store and
  the protocol keep a plain string. "Reposition" on the cover (`editor/src/page/page-header.tsx`) drags the picture
  one pixel per pixel over its overflow and saves or cancels.
- **Embeds** (`editor/src/extensions/embed.ts`, transforms in `editor/src/lib/embeds.ts`): one `embed` block — an
  `<iframe>` on a third-party page (sandboxed, keeps its origin) or on a snippet of HTML (`srcdoc`, no origin) — behind
  the "/" menu's Embeds group (Embed, HTML, Google Drive, Tweet, Gist, Google Maps, Figma). `embedFromURL` turns a
  pasted link into the provider's embeddable URL (YouTube, Vimeo, Figma, Maps, Drive/Docs, gists as a script snippet,
  tweets via platform.twitter.com, CodePen). Any other page is a link card instead of a frame (most sites refuse to be
  framed): icon, title, description and address, read natively by `HikkiCore/Sources/Text/LinkPreview.swift` through
  the `linkPreview` bridge request (exodus's `safe-fetch` rules: http/https, public hosts only, every redirect checked)
  and stored in the block when it is added; an older card without details reads them for display only. The height is an attribute, set by the handle
  under the frame. The native navigation delegate lets https / about: load in subframes only, and popups from a frame
  open in the system browser (`HikkiCore/Sources/Bridge/EditorNavigationPolicy.swift` decides; the editor's own scheme
  loads as the page only — in a frame it would be same-origin with the page). Embedded pages are hostile by default:
  the bridge drops script messages from any frame but the editor's own main frame (`BridgeProtocol.trustsFrame` —
  WebKit hands `messageHandlers` to every frame), and a stored embed `src` loads only when it is an https page
  (`safeFrameSrc`). YouTube's player refuses to play (error 153) without an HTTP Referer, which a page on
  the app's own scheme never sends, so with `VITE_HIKKI_BFF_URL` set the frame loads the BFF's shim page
  (`/embed/youtube/<id>`, `bff/src/index.ts`) and the player sees that as its referrer.
- **Home** (`Hikki/Sources/HomeView.swift`) is a database of every page (Notion's): a native `Table` (Name, Location,
  Created, Edited, Words, Favorite — click a header to sort, double-click or Return opens) or a gallery of cards, with
  a filter and New Page on top; iPhone gets a list. Sorting is `HomeSort` (Sendable, for Swift 6's table). The sidebar
  shows Home and Trash as Notion's row of icons (the open one widens into a pill with its name) and no section title.
  Trash has the same layout (table: deleted, deleted for good, Restore/Delete). Settings → Workspace → Keep deleted pages
  (7/30/90 days or until emptied, default 30; `TrashPreferences`) purges older trash at launch and activation
  (`DocumentStore.purgeTrash`); the deletion reaches other devices through the workspace folder.
- **Tabs from the sidebar** (Mac/iPad): a sidebar row focuses the tab already showing its page, or opens it as a new tab
  at the end; past `Navigator.recentTabLimit` the least recently focused tab closes (`NavigationTabs.openRecent`,
  recency kept in the saved tabs). Links and history still navigate inside the active tab.
- **Page links** (`editor/src/extensions/page-links.ts`): `hikki://page/<id>#<block>`. The native side feeds the editor
  the page index (`window.hikki.setPages`) so pasted links get titles; "Copy link to block" puts a ready `<a>` plus the
  URL on the clipboard; a plain-text paste of a link becomes a labelled hyperlink, and so does a dropped one: a
  sidebar row's drag carries the page's link (`PageLink.dragItem`), the editor's `handleDrop` inserts it where it
  lands, and the toolbar's `TabStrip` (`TabStripDrop`, `HikkiUI/Sources/TabStrip.swift`) opens it — between tabs
  as a new tab (or that page's tab is focused), onto a tab in that tab. Clicks go through the bridge
  (`openPage` with the block, `openLink` for the web) and `window.hikki.scrollToBlock` lands on the block.
- **Mentions, emoji, typography**: "@" mentions a page (`editor/src/extensions/page-mention.ts`, Tiptap's Mention: a
  `mention` node with the page id and its title at the time as `label`; the chip is a `hikki://page/<id>` link drawn
  with the page's current icon and title from the index, the label only a fallback). ":" suggests emoji
  (`editor/src/extensions/emoji-suggestion.ts`, Tiptap's Suggestion over the icon picker's emojibase data) and inserts
  the plain character — not Tiptap's Emoji node, whose plugin rewrites every emoji in a page into nodes. Both menus
  are `suggestionMenu` (`editor/src/extensions/suggestion-menu.ts`) over the shared `CommandList`. Typography turns
  -- … -> (c) into their characters; quotes, fractions and × stay as typed. Text extraction (search, word counts)
  treats mentions, ruby and inline math as part of the line.
- **Ruby / furigana** (`editor/src/extensions/ruby.ts`): an inline node (`<ruby><rb>…</rb><rt>…</rt></ruby>`, reading as
  an attribute); ⇧⌘R or Format → More → Ruby opens the reading panel, prefilled from the native tokenizer
  (`HikkiCore/Sources/Text/JapaneseReading.swift`, `suggestReading` message): a phrase comes back as kanji runs with
  readings and bare kana (役に立ちます → 役(やく)に立(た)ちます), one ruby per run; "Whole" puts one reading over all of it.
- **Semantic search** (Settings → Search, off by default): Hikki only reads and writes vectors; the model runs
  outside it behind `EmbeddingProvider` (`HikkiSearch/Sources/Embeddings.swift`) — one implementation, the
  OpenAI-compatible embeddings API (Ollama at `http://localhost:11434/v1` by default, LM Studio, llama.cpp, OpenAI with
  a key in the Keychain), so a better model is a setting, not code. Model-specific prefixes (e5's "query: "/"passage: ")
  come from the model name; loopback requests skip the proxy. Pages are cut into passages with the title in front
  (`Chunker`), stored with their vectors in `search.sqlite` under the model's identity (a new model starts over;
  `HikkiSearch/Sources/SemanticIndex.swift`, brute-force cosine with vDSP). `SemanticIndexer`
  (`Hikki/Sources/SemanticSearch.swift`) embeds a page once it has been quiet for 30 s, backfills at launch and after a
  settings change by edited time, re-sends only changed passages, and retries in 5 min when the model is unreachable.
  ⌘K shows word matches at once and, a quarter second later, pages related only by meaning under "Related" — only
  those that stand out from the median page (similarities sit in a narrow band for small models); word matches keep
  their order. The qllama build of multilingual-e5-small on Ollama tokenizes many single words to the same vector (measured
  2026-10-14: "money" = "cooking"); sentences work.
- **Search** (⌘K, `Hikki/Sources/SearchPalette.swift`) is the `HikkiSearch` package: `SearchIndex`
  (`HikkiSearch/Sources/SearchIndex.swift`) keeps its own SQLite file (`search.sqlite` next to the database) with every
  page's title, pinyin keys, headings and text under a trigram FTS5 index; `Hikki/Sources/SearchIndexer.swift` feeds it
  — every committed page change through the store's commit observer, plus a reconcile at launch by edited time (the
  index is rebuildable; `SearchIndex.version` empties an outdated one). Headings come out of the stored content
  natively (`ContentText.headings`, `HikkiCore/Sources/Store/ContentText.swift`), so synced pages count too.
  `SearchRanker` orders results: whole title, its start, every term at a word start / anywhere, the pinyin keys, then
  fzf-style subsequences; headings below titles, text below headings, the index's BM25 order (headings weighed 3×)
  among text matches, attached files a step below the page's own text, recent pages ahead on ties; it also cuts the
  excerpt. Attached files (`ContentText.assets`: inline images and file attachments) have their text read on device —
  PDFs through PDFKit, images through Vision's text recognition (`HikkiSearch/Sources/AttachmentText.swift`) — one
  file at a time at low priority after the page is indexed, once per file; a hit whose only match is in a file names
  it. The store has no search left in it. One ranked list ("Best matches"); a row shows the parent path, the excerpt
  with the terms emphasized (`HighlightedText`) and the edited time. Pages also go into the device's Spotlight index
  (Core Spotlight: `Hikki/Sources/SpotlightIndex.swift`, items shaped by `SpotlightItems` in HikkiSearch; Settings →
  Spotlight, default on, off empties it); a Spotlight result opens the page through `onContinueUserActivity`.
  On-device embeddings (`NLContextualEmbedding`) were measured and rejected for a "related" tier: related and
  unrelated sentence pairs overlap too much (2026-10-14).
- **Full screen (macOS)**: Xcode's way, in `Hikki/Sources/FullScreenChrome.swift` — the toolbar stays and gets its
  background while in full screen (that is what puts the columns below the toolbar row instead of under it); the
  traffic lights come down with the menu bar into that row. Measured, not guessed: in full screen AppKit moves the
  toolbar into its own window and does not draw the window buttons there until the menu bar shows (alpha / hidden
  changes draw nothing); dropping `autoHideMenuBar` from the presentation options makes AppKit hide the menu bar for
  good; Photos' hide-and-slide-in bar (`windowToolbarFullScreenVisibility(.onHover)`) came back transparent over the
  sidebar's search field. When the menu bar comes in, the toolbar row slides down with it by the menu bar's height,
  so the sidebar search field keeps that much free under the row in full screen (`fullScreenSlack` in the
  environment). The detail content doesn't add this extra inset, avoiding excess whitespace below the toolbar. The
  state is re-read on enter/exit/resize/key (restored windows) and logged (category `fullscreen`). DEBUG:
  `HIKKI_DEBUG_FULLSCREEN` forces the layout on in a window, `HIKKI_DEBUG_ENTER_FULLSCREEN` enters full screen 1.5 s
  after launch, `HIKKI_DEBUG_QUIT_AFTER=<s>` quits — own-instance checks.
- **Split view** (Mac/iPad, `Hikki/Sources/SplitView.swift`): the current tab and a second pane side by side, either
  holding a page or a PDF (`Navigator.split`, `isSplit`). The pane's page has its own editor (a second web view, made
  on first use and wired like the main one in `ContentView`). Opened from the
  View → Show Split View (⌘\\) (no toolbar button: drag is the way) — an empty pane offers the left page's PDF attachments, PDFs
  open in tabs and recent pages — or a page's "Open in Split View". The divider drags (fraction remembered); the pane's
  bar closes it, and its title is a chooser (recent pages, More… for the picker) to show another page; the same page may be on both sides (write left, read right — each editor reloads the other's saves, `pageSavedInEditor`). The inspector belongs to the left page, so it
  closes when the window splits; its toggle, ⌥⌘I and the page's star / ⋯ / lock buttons are off while split. By drag: a sidebar row or a page's tab dropped onto the pane shows there (`PageDrop`), and
  dropped on the right edge of the left side — the right quarter, 96–240 pt — opens beside it: native content
  (Home, a PDF) through `EdgeDrop` in `Hikki/Sources/SplitView.swift`, a page through the editor's own edge
  (`editor/src/extensions/split-drop.ts`, `openInSplit` bridge message, `window.hikki.setSplitDrop`), since the web
  view takes the drags over it. iPadOS keeps the screen's very edge for "open in a new window".
- **PDF viewer**: a PDF attachment opens in a pane of its own in a tab (`Route.file`), drawn natively by
  `HikkiUI/Sources/PDFViewer.swift` (PDFKit: continuous pages, zoom/fit, page number, find, thumbnails, an unlock prompt
  for password-protected files — the password is never stored); other attachments still open in Quick Look. Panes are
  the unit the planned split view will put side by side.
- **Inspector** (Mac/iPad: a full-height trailing panel inside the detail column — SwiftUI's `.inspector` widened the
  window — with the window title hidden while it is open, as in Photos; iPhone: a sheet from the page ⋯ menu):
  `Hikki/Sources/InspectorView.swift`, one mode at a time (`InspectorMode`): the outline or AI (a placeholder until the AI
  work lands; comments later), each opened by its own toolbar toggle (list, and `AIGlyph` — the AI mark in the ink
  palette's sweep), View → Show Outline (⌥⌘I); no tab bar. The page's facts (location, created, edited, words and
  characters) are the last lines of its ⋯ menu. The editor reports the outline and size with `pageInfo` (headings with
  block ids, words — CJK characters count one each — and characters from Tiptap's CharacterCount) and the heading the
  reader is in with `activeHeading` (a scroll-spy in `editor/src/core/bridge.ts`: the last heading past a line under
  the toolbar, the last one at the end; a heading jumped to from an outline stays marked until the reader scrolls).
  The panel's outline puts it on a background that glides from row to row and keeps it in view; the page's own hover rail lights its bar, and its list opens on it (the shared `GlidingHighlight`, following the hovered row meanwhile). A heading
  picked in the outline lands at the top (`window.hikki.jumpToHeading`). While the inspector shows the outline the
  page's hover rail hides (`window.hikki.setOutlineRail`).
- **Find, spelling, insets**: find and replace is `editor/src/extensions/find.ts` (Tiptap's extension, RE2 regex) with
  `editor/src/components/find-panel.tsx`; the page handles ⌘F/⌥⌘F/⌘G itself, the native Edit menu and the page ⋯ menu ("Find
  in Page", the only way on a phone) call `window.hikki.find`. Spellcheck is WebKit's (Settings → Editor,
  `window.hikki.setSpellcheck`). `window.hikki.setInsets` gives the page the toolbar height for fixed panels.
- **iOS input zoom**: fields under 16px make iOS zoom the page on focus (fixed panels then sit off screen); touch
  devices get 16px fields via an unlayered rule in `editor/src/style.css` (the page title is exempt).
- **Editor content safety**: content that doesn't fit the schema (corrupt, or from a newer Hikki) opens read-only and
  is never saved (`enableContentCheck`); housekeeping transactions (`addToHistory: false` — UniqueID stamping
  block ids, remote reloads) never count as edits; continuous typing still saves every 2 s (`maxWaitMs`).
- **Lock page** (Page menu ⇧⌘L, the page ⋯ menu, the sidebar context menu): `lockedAt` on the page
  (`DocumentStore.setLocked`; it bumps `updatedAt` like icon/cover so other devices pick it up). The load payload
  carries `locked`, `window.hikki.setLocked` flips it while open; title, body, icon and cover refuse changes meanwhile
  (`EditorBridge.frozen`) and a toolbar lock (`LockIndicator`) unlocks.
- **Workspace**: first launch shows `Hikki/Sources/OnboardingView.swift` until the workspace file (`AppPaths.workspace`) exists
  (`HikkiCore/Sources/Store/Workspace.swift`). A folder location stores a security-scoped bookmark
  (`HikkiCore/Sources/Store/FolderBookmark.swift`); page data does not live in that folder yet.
- **Demos and screenshots** on the Mac: launch the built binary with `HIKKI_DATA_DIR` and
  `-ApplePersistenceIgnoreState YES` (otherwise saved-state restoration can leave no window), capture by window id. Never
  `pkill -f Hikki` — the developer runs their own instance of the same binary (shared DerivedData).
- **BFF on Vercel** (project root `bff/`) compiles `src/` per file and runs it as Node ESM: relative imports need
  `.js` extensions (enforced by `NodeNext` in `bff/tsconfig.json`), and `src/` must not rely on Bun/Node ambient
  types (read env through Hono's `env(c)` adapter); tests get Bun types from `bff/tsconfig.test.json`.
- **Demo recordings** (macOS): `HikkiUITests/UnsplashDemoRecording.swift` drives a flow at a watchable pace when run
  with `TEST_RUNNER_HIKKI_RECORD=1`; record with `screencapture -v -V <s>` meanwhile. UI tests paste text rather than
  type it on macOS when spaces matter — synthesized keys go through the active input method (a Chinese IME eats them).
- **Colour tone**: one for now — `ColorTone.standard` (Kurenai, `design/tokens.json` `tone.default`); the other
  palettes stay in the tokens and `[data-tone]` CSS for when a picker returns. `make tokens` also writes the app's
  `AccentColor.colorset` from it, so system menus, selection and controls take the tone (where the user's system
  accent is "Multicolor" — a chosen system accent overrides every app's).
- **Settings** (`Hikki/Sources/SettingsView.swift`): pages (`SettingsPage`: Workspace, General, Appearance, Editor,
  Search, About) as the classic toolbar tabs of the Mac Settings window and a hub list on iPhone/iPad; each page is a grouped form of sections, the last page opened is remembered.
  `HIKKI_OPEN_SETTINGS=<page>` opens that page (screenshots). Optional integrations (a local Ollama for semantic
  search, later) get pages here with a detected/not-detected status, exodus's way.
- **Appearance** (Settings → Theme) is applied app-wide (`NSApp.appearance` / window `overrideUserInterfaceStyle`),
  not with `preferredColorScheme`, which left parts of windows in the old scheme after switching back.
- **macOS windows**: closing the last main window only hides it (Dock click restores it) and closes Settings —
  `Hikki/Sources/WindowLifecycle.swift`.
- **Menu bar extra** (`Hikki/Sources/MenuBarExtra.swift`, macOS, Settings → General → Menu bar): its menu has no
  focused window, so New Page / Search post `MenuBarRequests.shared.pending` and the key window's ContentView
  performs it. The glyph is `Hikki/Resources/Assets.xcassets` → MenuBarIcon (template PNGs at 1x/2x rasterized from
  `design/icon/hi-star/menubar.svg` — as an SVG asset the label rendered empty). The preference key has no dot (a
  dotted `@AppStorage` key on `MenuBarExtra(isInserted:)` looped the main menu).
- Simulators sometimes fail with "Busy (Application failed preflight checks)": `xcrun simctl shutdown all`, boot again.
