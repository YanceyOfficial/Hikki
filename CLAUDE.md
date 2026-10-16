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
  `<input>` / `<button>` (_checked by `make lint-design`_); a row in a menu, list or panel is `MenuRow`
  (`editor/src/components/menu-row.tsx`: a ghost `Button` as a full-width row, `glide` in lists with a gliding
  highlight); Phosphor icons are imported by their `…Icon` names. Files under `editor/src` are
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
- **Failures have codes and reach the user as toasts.** Every user-visible failure has a code in `design/errors.json`
  (`make errors` generates `ErrorCode` in `HikkiCore/Sources/Errors/ErrorCode.swift`, its messages in
  `Hikki/Sources/Generated/ErrorMessages.swift`, `editor/src/generated/errors.ts`, `bff/src/generated/errors.ts` and both
  string catalogs; numbers by area: 1xxx app, 2xxx pages & workspace, 3xxx editor, 4xxx files, 5xxx AI, 6xxx search,
  7xxx network — never reused). Report with `Toasts.report(code, error, category:)` natively (logs it with an incident
  id via `Incident.report`, then a toast with the code and "Copy details"), `reportError(id, error)` in the editor
  (`editor/src/core/errors.ts`, over the `reportError` bridge message); confirmations are `Toasts.shared.show` /
  `notify`. The BFF answers failures as `{error: {code, id, message}, requestId}` (`bff/src/http.ts`). No ad-hoc alerts
  or silent catches for something the user should know. _Checked by `make lint-design` (`gen-errors.mjs --check`)._
- **Keep this file current.** Architecture or directory changes update CLAUDE.md in the same commit.
  _Paths are checked by `make lint-docs` (`scripts/check-claude-md.mjs`)._

## Commands

```sh
make bootstrap      # bun install + tuist install (first clone)
make generate       # build the editor bundle and generate Hikki.xcworkspace
make tokens         # regenerate design tokens after editing design/tokens.json
make errors         # regenerate the error-code tables and messages after editing design/errors.json
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
design/errors.json            error codes for app, editor and BFF (single source; scripts/gen-errors.mjs)
design/fixtures/              fixtures both sides are tested against (content-text.json: block texts, Swift + editor)
Configs/Version.xcconfig      MARKETING_VERSION / CURRENT_PROJECT_VERSION
Project.swift                 Tuist manifest (targets: Hikki, HikkiCore, HikkiSearch, HikkiAI, HikkiUI + their tests, HikkiUITests)
Hikki/Sources/                app: SwiftUI shell, navigation (tabs), sidebar, page bar, search, editor host
Hikki/Resources/AppIcon.icon  Icon Composer document (merged from design/icon/hi-star; actool renders all sizes)
HikkiCore/Sources/            framework: Store (GRDB/SQLite, page tree, assets, tabs model), Text (Japanese readings),
                              Bridge (protocol, JSONValue), Logging (file log, MetricKit crash collection),
                              Layout (split view geometry), Shortcuts (KeyCombo)
HikkiSearch/Sources/          framework: the search engine — its own SQLite index (trigram FTS5, BM25), query parsing,
                              ranking, pinyin keys, fuzzy titles; tests in HikkiSearch/Tests/
HikkiAI/Sources/              framework: AI — one streaming client over OpenAI (Responses) and Anthropic (Messages) with
                              their own web search + citations, the fixed model catalog; tests in HikkiAI/Tests/
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
  paints selection in the system accent (not the colour tone) and swallowed row drops on iPad. Fills on the sidebar use
  resolved colours (dynamic ones picked up the active window's vibrancy). Markdown / HTML / text files or folders
  dragged onto it import (`Hikki/Sources/SidebarFileDrop.swift`): on a page row as its children (the row tints as for
  "inside"), elsewhere at the top level (the sidebar is outlined); ContentView runs the import through
  `Navigator.importDrop` → `AppModel.importFiles(_:parentId:)`. A page row's own drag carries a page link, never a
  file, so the two never mix; iPad drags (typed documents, no file URL) load as a temporary copy.
- **iPhone is its own layout**, not the Mac's squeezed — in every posture but an unfolded iPhone Duo on its side: a
  phone with a regular width (the Duo unfolded upright, a large iPhone on its side) reads as compact at the root
  (`PhoneLayout.forcesCompact`, `PhonePosture` in `Hikki/Sources/RootView.swift`); its top bars stay 24 pt clear of the screen's top edge
  (`clearOfTopEdge`: the Duo shows its status bar beside the camera, so its top inset is a few points) (prototype: the "Hikki iPhone redesign" canvas): the collapsed
  split view's sidebar column is `Hikki/Sources/PhoneHome.swift` (a ☰ · Home top bar, All pages / Trash tiles,
  "Jump back in" cards, Quick create — a blank page, today's note titled with the date, a page from the clipboard
  (`QuickNote`, HikkiCore) — Ask AI suggestions sent with this week's pages (`Navigator.pendingAIQuestion`), This
  week — HikkiUI's `WeekActivityCard` over the store's daily activity — recently edited, and favorites; the lists come
  from a `HomeDigest` (HikkiCore) worked out per tree change, the activity read in a task) and opening anything shows the detail through `Navigator.compactColumn`
  (`preferredCompactColumn`). The page tree is Notion's side drawer: `Hikki/Sources/PhoneDrawer.swift` (workspace +
  search, favorites, the tree — its actions on a long press, Add a page, then All pages · Trash · Settings fixed at the bottom)
  inside HikkiUI's `SideDrawer` (`HikkiUI/Sources/SideDrawer.swift`, exodus-ios's drawer, 75 % of the width: the content is a card pushed
  right and dimmed; a UIKit pan takes horizontal drags anywhere — flick projection, rubber band past open — and lets a
  horizontal list keep its drags unless it sits at its leading edge; ☰ or a tap on the card toggles; `Motion.easeOut()`). Root screens and pages float one bottom bar —
  `FloatingActionBar` (HikkiUI): Search · Ask AI · New page at home, Outline · Ask about this page · Edit on a page
  (hidden while the keyboard is up); the page's ⋯ is a sheet (`Hikki/Sources/PhonePageActions.swift`: quick tiles,
  history, export, move, facts). All pages groups by day (`RecencyGroup`, HikkiCore). Ask AI is a native chat sheet
  (`Hikki/Sources/AIChat.swift`: the open page's text as context, model menu, web search, `AIPrompts.chat`; answers render through `AIMarkdown`, which keeps only http(s) links). Left
  out on iPhone: tabs, split view, the inspector panel, Home's table, Shortcuts settings. Search is a full-screen cover
  (the field fixed at the top, results filling the rest). A page runs to the top of the screen: the scroll view has no
  top inset and the editor makes that room itself (`setInsets` with `bleed`, `--hk-bleed-top`), so a cover fills it
  behind the status bar and the glass buttons (`.hk-cover`) and a page without one starts below them.
- **Data directory**: `HIKKI_DATA_DIR` overrides it (UI tests, demos). DEBUG hooks: `HIKKI_OPEN_TABS=a,b`,
  `HIKKI_OPEN_SEARCH`, `HIKKI_OPEN_FIND`, `HIKKI_DEBUG_NAV=a,b,c`, `HIKKI_DEBUG_SPOTLIGHT_QUERY=<text>` (logs the page ids Spotlight ranks), `HIKKI_OPEN_FILE=<asset>` (the PDF viewer), `HIKKI_OPEN_SPLIT=<page id>|file:<asset>|picker` (split view), `HIKKI_DEBUG_SIDEBAR` (hide + show the split view sidebar), `HIKKI_OPEN_SETTINGS`, `HIKKI_DEBUG_TOAST` (a sample failure toast), `HIKKI_OPEN_AI`, `HIKKI_OPEN_PAGE_ACTIONS`, `HIKKI_DEMO_PAGES` (an empty workspace gets sample pages, ids fixed per title — `Hikki/Sources/DemoPages.swift`), `HIKKI_ACTIVATE`, `HIKKI_WORKSPACE=<name>` (seeds a device workspace, skips onboarding;
  UI tests set it by default — pass `workspace: nil` to `launch()` to test onboarding).
- **Storage (option C)**: the workspace folder is the source of truth — one JSON file per page
  (`HikkiCore/Sources/Store/PageFile.swift`: `pages/<id>.json`, format-versioned, content as JSON); SQLite is a
  rebuildable cache/index. `HikkiCore/Sources/Store/WorkspaceSync.swift` reconciles on launch and app activation
  (newer side wins; a missing file deletes the page only if it was synced before — `pageFileState`) and writes every
  committed page change through (a GRDB transaction observer). "Newer" is `changedAt` (`lastChange`): every write
  method sets it — moves, reorders, trash, restore and favorites too, which leave `updatedAt` (the "Edited" date)
  alone — and page files carry it as an optional key (format stays 1; absent = `updatedAt`). A pass compares ids,
  parents and change times only (`syncHeads`), reading a full row just for pages it writes or replaces; an import
  replaces a row only if it is still as compared (`importPage(_:expecting:)`), and a write-through never overwrites a
  file that changed since it last agreed with the row (a pass then makes the conflicted copy). A remote deletion of
  a page waits while a page under it still has a file (moved out elsewhere, its new file not read yet); parent loops
  two devices made are broken (`breakParentCycles`: the smallest id goes to the top). It also watches `pages/` (a
  dispatch source; unchanged files are skipped by modification date + size — stamps persisted in `pageFileState`, so a
  launch reads only changed files — and a watched change that is only this device's own writes runs no pass) and
  posts `pagesChangedOnDisk`, so an open editor
  reloads a page another device changed (`window.hikki.reload`, declined while it has unsaved edits). While files
  are still downloading (iCloud placeholders / half-written files) it passes again with backoff — kqueue events are
  unreliable in iOS file-provider folders. Assets live in `<folder>/assets`. **Conflict copies**: nothing two devices
  wrote is lost. When iCloud kept several versions of a page file (`NSFileVersion`, behind the `FileVersionStore`
  protocol in `HikkiCore/Sources/Store/FileConflicts.swift`; tests fake it), the newest edit wins as the page and every
  other version that says something different becomes a sibling page titled "<title> (conflicted copy <device>,
  <date>)" (`ConflictCopy`), then the conflicts are marked resolved. The same happens when the row and the file both
  changed since they last agreed — `pageFileState.baseUpdatedAt` (the agreed `lastChange`), set on every write and
  import (`syncBases`) — and when the editor saves over a title/body it never loaded (`saveContent(_:loaded:)` with
  the `LoadedContent` it last loaded or saved). Pages deleted for good here go to `Options.onDeleted`, which takes
  their history and comments along.
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
  `VersionDiffView`; a title that differs from the page's now is marked the same way above the body
  (`PageDiff.title`, `VersionTitleView`, "Title changed"). Restore writes through `saveContent` + `setIcon`/`setCover` and reloads open editors.
  DEBUG: `HIKKI_HISTORY_INTERVAL=<s>` shortens the session (UI tests).
- **Import / export** (`Hikki/Sources/PageTransfer.swift`): the editor converts, in its own schema
  (`editor/src/core/convert.ts`: Tiptap's official `@tiptap/markdown`, HTML through the schema's parse/render rules;
  blocks with no Markdown form export as their container's blocks or their rendered HTML) — `window.hikki.exportPage`
  / `importDocument`. Export (page ⋯ → Export: Markdown, HTML, PDF, JSON = the page file) is packed by
  `PageExport` (`HikkiCore/Sources/Store/PageExport.swift`): one file, or — when the page attaches files — a folder
  with the document and `assets/` it links into relatively; saved with `.fileExporter` on both platforms. PDF renders
  the HTML export in an offscreen light web view (`createPDF`: one tall page). Import (File → Import…, the workspace
  menu) takes .md/.html/.txt — or a folder of them, such as an export — as new top-level pages; pictures and
  attachments a document links by relative path inside its folder are copied into the workspace's assets
  (`HikkiCore/Sources/Store/PageImport.swift`; nothing outside the folder), and Markdown's inline pictures are lifted
  into blocks (`liftBlockMedia`). Whatever the file holds, the body fits the schema (text fallback, its reason logged).
  Files dropped on the sidebar import the same way (see Sidebar; a dropped file's name is reduced to its last
  component before it is copied). DEBUG: `HIKKI_EXPORT_DIR=<folder>`
  skips the save panel, `HIKKI_IMPORT_FILE=<path>` imports at launch (UI tests).
  **Bulk** (Settings → Workspace → Import & Export, `TransferSection` → `Hikki/Sources/BulkTransfer.swift`, one job
  per app on `AppModel.bulkTransfer`, running on when Settings closes: progress with Cancel, then a summary with the
  skipped files and why; `onFinish` is the hook for app-wide notices). Import takes many files and folders:
  `WorkspaceImport` (`HikkiCore/Sources/Store/WorkspaceTransfer.swift`) plans the tree — a chosen folder's contents
  go to the top level, a subfolder is a page (empty, its name) unless a document beside it has its name, `assets/`
  is attachments; Markdown/HTML/text go through the editor (`AppModel.importConverted`, relative links may climb to
  the chosen folder, not out), Hikki page files (JSON) come back as they were, keeping their id when it is free and
  their place by `parentId` too (a flat `pages/` folder rebuilds its tree). Export writes every live page into a new
  folder (`WorkspaceExport`: `Title.<ext>` plus `Title/` for subpages, sibling names safe and unique ignoring case,
  attachments once in the top `assets/` linked with `../`); Markdown/HTML through any window's editor (each window
  registers its own), JSON = the page files with attachments kept by name, so a JSON export imported into an empty
  workspace is the same workspace. DEBUG: `HIKKI_BULK_IMPORT=<path>|<path>`, `HIKKI_BULK_EXPORT=<format>|<folder>`.
- **Workspace identity** lives in the folder (a workspace.json next to `pages/`: id, name, icon — `WorkspaceIdentity`); the per-device
  record (`AppPaths.workspace`) only adds the location. A device picking a folder that has one _opens_ that workspace
  (onboarding says so), and a newer identity from another device replaces the local name/icon on activation. Settings →
  Storage → Change folder re-points a workspace (`AppModel.changeLocation`: synced marks cleared, local pages written
  out, the folder's imported — nothing deleted).
- **Popups close one way**: every `FloatingLayer` opened with `onDismiss` (`editor/src/components/floating.tsx`) joins
  one dismiss bus — a single pair of document listeners: Escape and a press outside every open layer dismiss the newest
  one, and the opener says what that means (the slash and block menus exit, the math and ruby panels cancel; it gets
  the reason and may answer `'keep'` — Escape in the block menu closes its submenu first). No popup installs its own
  outside-click or Escape listener. `dismissAllLayers` runs as `loadDocument` starts, so nothing outlives its page, and a
  menu or panel acting on a block later follows it through edits meanwhile (`followNode` / `followPosition` in
  `editor/src/extensions/block-units.ts`: by block id, else mapped; gone → it closes). Base UI popups (shadcn) bring their own. A layer follows its
  anchor when the page scrolls, and a scroll over any popup (`hk-pop`) never reaches the page behind it
  (`editor/src/lib/scroll-containment.ts`, one set of document listeners).
- **Editor menus**: `editor/src/core/blocks.ts` is the one block catalog (groups, Markdown shortcuts, `turnInto`, `isActive`)
  behind the "/" menu (`editor/src/components/slash-menu.tsx`) and the selection menu's "Turn into"
  (`editor/src/components/selection-menu.tsx`, positioned by Tiptap's BubbleMenu; its side panels stay inside the menu element
  or BubbleMenu hides on blur). The selection menu and the block menu share "Turn into"
  (`editor/src/components/block-type-list.tsx`) and the colour list (`editor/src/components/color-list.tsx`). Text/background colors are stored as palette names (`editor/src/extensions/colors.ts`) and
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
- **Search** (⌘K, `Hikki/Sources/SearchPalette.swift`) is the `HikkiSearch` package: `SearchIndex`
  (`HikkiSearch/Sources/SearchIndex.swift`) keeps its own SQLite file (`search.sqlite` next to the database, WAL so
  searches read beside writes) with every page's title (and pinyin keys) and its text blocks with their ids, stored
  as written and once more folded (`SearchQuery.fold`: no case, no accents — "cafe" finds Café), the folded copy under
  a trigram FTS5 index. `Hikki/Sources/SearchIndexer.swift` feeds it — every committed page change through the
  store's commit observer (a record whose title, icon and edited time the index has is skipped), plus a reconcile at
  launch by edited time (the index is rebuildable; `SearchIndex.version` empties an outdated one). Each page's
  content is read once, natively (`ContentText.extract` in `HikkiCore/Sources/Store/ContentText.swift`: headings,
  blocks, attached files; block text reads as the editor's `editor/src/core/extract.ts` — `design/fixtures/content-text.json` holds
  both to the same answers), for the index and Spotlight both. A search looks each term up on its own — FTS for
  three characters or more, a scan of the folded blocks for shorter ones — so every page holding a term is a
  candidate. `SearchRanker` orders results: whole title, its start, every term at a word start / anywhere, the pinyin
  keys; headings below titles, text below headings, the BM25 order (summed over a page's blocks, headings weighed 3×)
  among text matches, attached files a step below the page's own text, recent pages ahead on ties; an fzf-style
  subsequence of a title counts only when nothing else matched and the query has three letters or more. Attached
  files (inline images and file attachments) have their text read on device — PDFs through PDFKit, images through
  Vision's text recognition (`HikkiSearch/Sources/AttachmentText.swift`) — by one background reader
  (`HikkiSearch/Sources/FileTextReader.swift`), once per file name: the file texts live apart from pages, outlive a
  new index layout and the trash, and a file that can't be read is marked and not tried again (one not on the device
  yet is, at the next launch). A hit whose only match is in a file names it and opens at the block showing it. The
  store has no search left in it. One ranked list ("Best matches"); a row shows the parent path, the excerpt
  with the terms emphasized (`HighlightedText`) and the edited time. Only for the hits shown are the matching blocks
  read: a text hit names its best block (`SearchRanker.bestBlock`: most terms, a heading ahead of body text, one
  starting with a term, the earliest), its excerpt runs from there, and opening it lands on that block with the words
  selected (`Navigator.open(_:at:revealing:)` → `window.hikki.revealText`; without a block, the first place a term
  occurs). A page's other matching blocks (`SearchHit.moreMatches`, the first 50; `moreMatchCount` counts them all)
  fold under its row — "N more matches", then the first five, "Show N more", "Hide" (`SearchListItem`, rows
  `SearchMatchRow` / `SearchMatchesToggleRow` in HikkiUI) — each opening at its block. Under the field, scope chips
  (`FilterChip`: All / Titles / Text / Files — `SearchScope` in `HikkiSearch/Sources/SearchOptions.swift`; the ranker
  and the index only count matches where the scope looks, Files always shows the file's excerpt) and a sort menu
  (Best match / Last edited, `SearchSort`). The palette's search runs off the main thread in its own task
  (`AppModel.search` → `SearchIndex.search`, `@concurrent`): a newer query cancels the older one, which stops between
  steps and interrupts its read, so a busy index never freezes typing. Index failures are logged and shown once per
  run (`searchIndexFailed`). Pages also go into the device's Spotlight index
  (Core Spotlight: `Hikki/Sources/SpotlightIndex.swift`, items shaped by `SpotlightItems` in HikkiSearch; Settings →
  Spotlight, default on, off empties it); a Spotlight result opens the page through `onContinueUserActivity`. The
  index is shared by every run of the app, so a run on its own data folder (`HIKKI_DATA_DIR`: UI tests, demos) never
  writes to it (`SpotlightItems.writesAllowed`; `HIKKI_SPOTLIGHT=1` to test Spotlight itself), and a new item format
  (`SpotlightPreferences.version`) empties the domain before pushing every page again (`reseed`).
  No search by meaning: on-device embeddings (`NLContextualEmbedding`, 2026-10-14) separated related from unrelated
  sentences too poorly, and semantic search over Ollama embeddings (bge-m3, e5) was built and removed on 2026-10-15 —
  one-word queries across languages ("busy" → 忙しい) still missed, and its indexer competed with word search.
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
- **Split view** (Mac and the larger iPads — not iPad mini or a phone: `SplitPolicy`, `Navigator.splitAllowed`;
  `Hikki/Sources/SplitView.swift`): the current tab and a second pane side by side, either
  holding a page or a PDF (`Navigator.split`, `isSplit`). The pane's page has its own editor (a second web view, made
  on first use and wired like the main one in `ContentView`). Opened from the
  View → Show Split View (⌘\\) (no toolbar button: drag is the way) — an empty pane offers the left page's PDF attachments, PDFs
  open in tabs and recent pages — or a page's "Open in Split View". The divider drags (fraction remembered); the pane's editor never takes the keyboard when its page loads
  (`window.hikki.setAutoFocus(false)` — an empty page's title would otherwise grab it from the page beside); the pane's
  bar closes it, and its title is a chooser (recent pages, More… for the picker) to show another page; the same page may be on both sides (write left, read right — each editor reloads the other's saves, `pageSavedInEditor`). The inspector belongs to the left page, so it
  closes when the window splits; its toggle, ⌥⌘I and the page's star / ⋯ / lock buttons are off while split. By drag: a sidebar row or a page's tab dropped onto the pane shows there (`PageDrop`), and
  dropped on the right edge of the left side — the right quarter, 96–240 pt — opens beside it: native content
  (Home, a PDF) through `EdgeDrop` in `Hikki/Sources/SplitView.swift`, a page through the editor's own edge
  (`editor/src/extensions/split-drop.ts`, `openInSplit` bridge message, `window.hikki.setSplitDrop`), since the web
  view takes the drags over it. Split already, that edge replaces the right side, so the right pane outlines itself
  whole (`Navigator.splitDropHover`, set by `EdgeDrop` and the editor's `splitDropHover` message) — a half-width zone
  on the left read as a third column. iPadOS keeps the screen's very edge for "open in a new window".
- **PDF viewer**: a PDF attachment opens in a pane of its own in a tab (`Route.file`), drawn natively by
  `HikkiUI/Sources/PDFViewer.swift` (PDFKit: continuous pages, zoom/fit, page number, find, thumbnails, an unlock prompt
  for password-protected files — the password is never stored); other attachments still open in Quick Look. Panes are
  the unit the planned split view will put side by side.
- **Comments** (Notion's): ⇧⌘M or the selection menu's Comment starts a thread on the selected passage. The passage
  carries a `comment` mark with the thread's id (`editor/src/extensions/comments.ts`), so it moves with edits; the
  words live natively in `comments/<page id>.json` in the workspace folder (`HikkiCore/Sources/Store/PageComments.swift`:
  format-versioned, merged by id with tombstones, iCloud conflict versions folded in), written through the
  `commentCreate` / `commentReply` / `commentResolve` / `commentDelete` bridge messages and pushed back with
  `window.hikki.setComments`. A draft is only a highlight until it is sent; adding or removing the mark is kept out of undo but saved (`SAVE_META`
  — `isUserEdit` in `editor/src/core/bridge.ts` otherwise skips non-undo transactions), and an open thread whose mark is
  missing is marked again where its quote occurs once (`findQuote`). `editor/src/components/comments.tsx` draws
  cards in the right margin when the window is wide (`#page[data-comments]` shifts the page left at ≥ 1240 px), count
  badges with a thread card under the passage otherwise; on a phone (`PHONE_QUERY`: coarse pointer, narrow or short
  window) the open thread or a new comment is a bottom sheet instead (shadcn `Drawer`, `editor/src/components/ui/drawer.tsx`,
  restyled to the motion tokens): grabber, quote, comments with their actions always shown, the reply field at the
  foot riding the software keyboard (`visualViewport`) and clear of the native bottom bar (`--hk-inset-bottom`);
  scrim, swipe down or Escape close it, and neither opening nor closing it focuses the page. A tap on a commented
  passage opens its thread without moving the caret (the plugin cancels that touch's click, so no keyboard comes up);
  a click on a Mac still places the caret. Resolved threads lose their highlight. Each comment in an
  open thread shows its actions on hover (the first: resolve ✓; all: ⋯ → Edit in place, Copy link to discussion —
  `hikki://page/<id>#<thread id>`, which `scrollToBlock` turns into opening the thread — and Delete: a reply alone,
  the first comment the whole discussion); `commentEdit` rewrites one (`editedAt`; a merge keeps the newer edit).
  "@" in the field (typed, or its @ button) mentions a page: stored as `[@Title](hikki://page/<id>)` in the text
  (`editor/src/lib/comment-text.ts`), drawn as a chip with the page's current icon and title, "@Title" natively
  (`PageComment.plainBody`). The page column is
  `.hk-column` alone in `editor/index.html` (fixed 96 px side margins).
- **Inspector** (Mac/iPad: a full-height trailing panel inside the detail column — SwiftUI's `.inspector` widened the
  window — with the window title hidden while it is open, as in Photos; iPhone: a sheet from the page ⋯ menu):
  `Hikki/Sources/InspectorView.swift`, one mode at a time (`InspectorMode`): the outline, the page's comments (open /
  resolved threads, Reopen) or the AI chat (`AIChatView`, the same conversation as the iPhone sheet, about the page beside it — and the passage selected
  in it, reported by the `selection` bridge message; Notion's composer: attached pictures / PDFs (+, drop, paste; sent as
  base64 — `HikkiAI/Sources/AIAttachments.swift` scales pictures to 1568 px), context chips, @ to add other pages, the
  field, attach · web · model · send). The toolbar's trailing
  end, as Xcode's: [star · ⋯] [outline · comments] [AI in its own circle, `AIGlyph`], the open view marked; View →
  Show Outline (⌥⌘I); no tab bar. The page's facts (location, created, edited, words and
  characters) are the last lines of its ⋯ menu. The editor reports the outline and size with `pageInfo` (headings with
  block ids, words — CJK characters count one each — and characters from Tiptap's CharacterCount) and the heading the
  reader is in with `activeHeading` (a scroll-spy in `editor/src/core/bridge.ts`: the last heading past a line under
  the toolbar, the last one at the end; a heading jumped to from an outline stays marked until the reader scrolls).
  The panel's outline puts it on a background that glides from row to row and keeps it in view; the page's own hover rail lights its bar, and its list opens on it (the shared `GlidingHighlight`, following the hovered row meanwhile). A heading
  picked in the outline lands at the top (`window.hikki.jumpToHeading`). While the inspector shows the outline the
  page's hover rail hides (`window.hikki.setOutlineRail`).
- **Tabs keep their place**: the editor reports where the page is scrolled (`scroll` message, throttled); ContentView
  remembers it per tab when another tab takes over and, when a tab is shown again, loads its page and scrolls back
  (`window.hikki.restoreScroll`). Another page opened inside a tab starts at its top (`loadDocument`).
- **A window's editors** (`WindowEditors` in `Hikki/Sources/ContentView.swift`): the main one made once per window, the
  split pane's on first use. Each holds the window's `EditorSettings` (tone, spelling, AI review style, shortcuts —
  ContentView sets both at once) and replays them on ready; bridge calls go through its `call` helper. The tree
  changes on every save, so nothing on that path may re-render or re-send for nothing: the navigator assigns tabs /
  expanded rows only when they changed (`NavigationTabs.pruned`), and each editor sends the page index and its own
  page's lock only when they changed (`EditorPageState`, `HikkiCore/Sources/Bridge/EditorPageState.swift`). Editor
  callbacks capture weakly (a strong capture kept closed windows' web processes alive; DEBUG logs "editor released").
  Unsaved typing is flushed when a window goes to the background or closes and on ⌘Q (`Hikki/Sources/SaveOnExit.swift`:
  every editor, then the workspace folder, 3 s cap; iOS under a background-task assertion). The page / trash
  observation runs once for the app (`AppModel.observation`).
- **AI** (Settings → AI; `HikkiAI/Sources/`): the provider HTTP APIs directly over URLSession with SSE — the Swift client
  packages tried (SwiftOpenAI, SwiftAnthropic) dropped web-search citations and error bodies. `AIClients.client(for:keys:)`
  streams `AIEvent`s (text, searching, citation, finished); `HikkiAI/Sources/StreamDecoders.swift` reads each provider's events
  tolerantly (unknown events skipped, malformed lines ignored, only error events throw), `HTTPErrors` maps failures
  to `AIError`. Models are a fixed list (`AIModelCatalog`; "Auto" picks a balanced one among the providers with a
  key). The model menu (`AIModelButton` in `Hikki/Sources/AISettings.swift` over `HikkiUI/Sources/ModelPickerList.swift`;
  the chat's composer and Settings → AI) is Notion's: Auto, starred models under Favorites, Recommended, Other
  models — a star on each row (`AIModelFavorites` in `HikkiAI/Sources/AIModelFavorites.swift`, UserDefaults
  `ai.favoriteModels`); a pick in the chat is also the default, which the page's Ask AI runs on. Each provider may have a base URL (blank: its own API; `HikkiAI/Sources/AIEndpoint.swift` — OpenAI's base
  includes `/v1`, Anthropic's doesn't, as in their SDKs; https, or http only to loopback). Keys live in the Keychain
  (`AIPreferences`, `Hikki/Sources/AISettings.swift`), one per provider and origin (`AIEndpoint.keyAccount`), so a key
  only ever goes to the address it was entered for. The editor asks through `aiRequest` / `aiCancel` (selected parts of blocks as inline HTML + nearby
  text) and gets `window.hikki.aiEvent`s back. `Hikki/Sources/AIService.swift` runs them (one per window, both
  editors) with the prompts in `HikkiAI/Sources/AIPrompts.swift`: an edit asks for JSON `{"blocks":[{id, html}]}`
  with the same ids and inline tags only, an answer for short Markdown with web search; page text is wrapped in tags
  as data. In the page: the selection menu's "Ask AI" (`editor/src/components/ai-panel.tsx`) runs a preset or the
  user's words; `editor/src/extensions/ai-review.ts` shows an edit in the review style picked in Settings → AI
  (thumbnails: `ReviewStyleThumbnail` / `ThumbnailOption` in HikkiUI; `ai.reviewStyle`, sent with
  `window.hikki.setAIReviewStyle`): A `inline` (default) — removals struck through and additions as widgets in the page
  (decorations only, the document untouched) under a bar from `editor/src/components/ai-review.tsx` (Accept ↵ in one
  undo step, Discard esc, Retry, a follow-up); B `diff` — − / + lines in the bar; C `bubble` — a card listing each
  change with the model's reason (`explain` in the request, `notes` in the reply), the page untouched until Replace
  (B and C: `editor/src/components/ai-review-styles.tsx`). Answers get a card (Insert below, Copy) that draws their
  Markdown as page blocks (`markdownBlocks` / `markdownDOM` in `editor/src/core/convert.ts`: no media, web links only)
  and inserts it as blocks; answers and reasons are written in the app's language (`AIPrompts.languageLine`). Model output is untrusted: the reply is parsed tolerantly (`editor/src/lib/ai-content.ts`;
  sanitized inline HTML through the schema, unknown keys dropped, an unreadable reply is an error), citations must be
  http(s), and any change to the page closes the review.
- **Find, spelling, insets**: find and replace is `editor/src/extensions/find.ts` (Tiptap's extension, RE2 regex) with
  `editor/src/components/find-panel.tsx`; the page handles ⌘F/⌥⌘F/⌘G itself, the native Edit menu and the page ⋯ menu ("Find
  in Page", the only way on a phone) call `window.hikki.find`. Spellcheck is WebKit's (Settings → Editor,
  `window.hikki.setSpellcheck`). `window.hikki.setInsets` gives the page the toolbar height for fixed panels and, on
  iPhone, the floating bar's room at the foot (`--hk-inset-bottom`, 0 while the keyboard is up).
- **iOS input zoom**: fields under 16px make iOS zoom the page on focus (fixed panels then sit off screen); touch
  devices get 16px fields via an unlayered rule in `editor/src/style.css` (the page title is exempt).
- **Editor content safety**: content that doesn't fit the schema (corrupt, or from a newer Hikki) opens read-only and
  is never saved (`enableContentCheck`); housekeeping transactions (`addToHistory: false` — UniqueID stamping
  block ids, remote reloads) never count as edits; continuous typing still saves every 2 s (`maxWaitMs`).
- **Lock page** (Page menu ⇧⌘L, the page ⋯ menu, the sidebar context menu): `lockedAt` on the page
  (`DocumentStore.setLocked`; it bumps `updatedAt` like icon/cover so other devices pick it up). The load payload
  carries `locked`, `window.hikki.setLocked` flips it while open (each editor, split pane included, for the page it
  shows — `EditorController.setPages`); title, body, icon and cover refuse changes meanwhile
  (`EditorBridge.frozen`) and a toolbar lock (`LockIndicator`) unlocks.
- **Workspace**: first launch shows `Hikki/Sources/OnboardingView.swift` until the workspace file (`AppPaths.workspace`) exists
  (`HikkiCore/Sources/Store/Workspace.swift`). A folder location stores a security-scoped bookmark
  (`HikkiCore/Sources/Store/FolderBookmark.swift`); page data does not live in that folder yet.
- **Diagnostics** (local only, nothing leaves the device by itself): every log line carries the run's `Log.session`;
  the launch line has `AppInfo` (version, build, OS, device, language, protocol). `CrashReporter` keeps MetricKit
  reports and drops a marker on a fatal signal or uncaught exception (`crash.marker.running`, written with `write(2)`
  only), so the next launch toasts "Hikki quit unexpectedly" (`pendingCrash`; an iOS background kill leaves no marker).
  Settings → About → Diagnostics: Export diagnostics (`DiagnosticsBundle`: logs, reports and an about file — counts and
  non-sensitive settings, never content or keys — zipped through `NSFileCoordinator` when shared) and Logs
  (`Hikki/Sources/LogsView.swift`, newest entries with a level filter). A toast's "Copy details" gives the code, the
  incident id (grep it in the logs) and the app summary.
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
- **Settings** (`Hikki/Sources/SettingsView.swift`): pages (`SettingsPage`: General — appearance, language, editor,
  menu bar — then Workspace, Shortcuts, Search, AI, About; iPhone has no Shortcuts) as the classic toolbar tabs of the
  Mac Settings window and a hub list on iPhone/iPad; each page is a grouped form of sections, the last page opened is
  remembered.
  `HIKKI_OPEN_SETTINGS=<page>` opens that page (screenshots). Optional integrations get pages here with a
  detected/not-detected status, exodus's way.
- **Appearance** (Settings → General → Theme) is applied app-wide (`NSApp.appearance` / window `overrideUserInterfaceStyle`),
  not with `preferredColorScheme`, which left parts of windows in the old scheme after switching back.
- **macOS windows**: closing the last main window only hides it (Dock click restores it) and closes Settings —
  `Hikki/Sources/WindowLifecycle.swift`.
- **Menu bar extra** (`Hikki/Sources/MenuBarExtra.swift`, macOS, Settings → General → Menu bar): its menu has no
  focused window, so New Page / Search post `MenuBarRequests.shared.pending` and the key window's ContentView
  performs it. The glyph is `Hikki/Resources/Assets.xcassets` → MenuBarIcon (template PNGs at 1x/2x rasterized from
  `design/icon/hi-star/menubar.svg` — as an SVG asset the label rendered empty). The preference key has no dot (a
  dotted `@AppStorage` key on `MenuBarExtra(isInserted:)` looped the main menu).
- Simulators sometimes fail with "Busy (Application failed preflight checks)": `xcrun simctl shutdown all`, boot again.
