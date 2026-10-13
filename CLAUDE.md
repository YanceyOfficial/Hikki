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
  `usePresence` (`editor/src/ui/floating.tsx`) — or `hk-pop-toggle` + `data-open` when they stay mounted. Lists
  mark the selected row with one gliding surface (`editor/src/ui/GlidingHighlight.tsx`, rows `relative` +
  `data-index`), block tints fade (`.tiptap [data-id]`), anything clickable takes `ui.press` / the `ui.button`
  recipes (hover fade + 97 % press); Swift uses `Motion.easeOut()`. No per-component durations, easings or
  tw-animate classes. _Enforced by `make lint-design`._
- **Reusable UI lives in `HikkiUI`** (no app state: plain values + closures, a `#Preview` each, listed in the DEBUG
  gallery `Hikki/Sources/ComponentGallery.swift`, launch argument `-HikkiGallery`). Native components follow the same
  look as the web's shadcn style (`base-vega`: `Radius.md` controls, `Theme.*` colors).
- **Web UI primitives are shadcn** (style `base-vega`, Base UI primitives, hugeicons; config in `editor/components.json`,
  components in `editor/src/components/ui/`). Add components only with `cd editor && bun run ui:add <name>` — the
  wrapper fixes the CLI's wrong `cn` import under TypeScript 7. Prefer a shadcn component over a hand-rolled one;
  editor-specific pieces live in `editor/src/ui/`.
- **Icons go through one list** (`design/icons.json`, `make icons`). The native shell draws SF Symbols (each icon's
  `"sf"` name; the generated `Icon` enum, `IconView` / `IconLabel`, `Icon.glyph` for system-sized spots), falling
  back to the bundled Phosphor asset where there is no symbol; the web editor uses `@phosphor-icons/react`. No raw
  `Image(systemName:)` / `systemImage:` — _enforced by `make lint-design`_.
- **Keyboard shortcuts come from one registry.** `design/shortcuts.json` → `make shortcuts` generates
  `Hikki/Sources/Generated/Shortcuts.swift` (`Shortcut.x.keyboardShortcut` / `.display`) and
  `editor/src/generated/shortcuts.ts` (`matchesShortcut`, `shortcutLabel`, `tiptapShortcut` in
  `editor/src/shortcuts.ts`). Each entry says who binds it: `app` (native menu), `editor` (the page; menus only
  display it) or `both`. No literal key equivalents or "⌘X" labels in code; the generator refuses two shortcuts on
  the same keys. _Checked by `make lint-design`._
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
- **Bridge protocol.** Messages are defined twice — `editor/src/protocol.ts` and
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
Project.swift                 Tuist manifest (targets: Hikki, HikkiCore, HikkiUI, HikkiCoreTests, HikkiUITests)
Hikki/Sources/                app: SwiftUI shell, navigation (tabs), sidebar, page bar, search, editor host
Hikki/Resources/AppIcon.icon  Icon Composer document (merged from design/icon/hi-star; actool renders all sizes)
HikkiCore/Sources/            framework: Store (GRDB/SQLite, page tree, assets, tabs model), Search (pinyin, fuzzy),
                              Bridge (protocol, JSONValue), Logging (file log, MetricKit crash collection)
HikkiUI/Sources/              framework: reusable SwiftUI components + Theme
editor/src/                   web editor: bridge, Tiptap extensions, page header, ui primitives
editor/src/components/ui/     shadcn components (generated via `bun run ui:add`)
editor/test/                  vitest
bff/                          backend-for-frontend (Hono, Vercel): Unsplash proxy; tests with `bun test`
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
  `HIKKI_OPEN_SEARCH`, `HIKKI_OPEN_FIND`, `HIKKI_DEBUG_NAV=a,b,c`, `HIKKI_DEBUG_SIDEBAR` (hide + show the split view sidebar), `HIKKI_OPEN_SETTINGS`, `HIKKI_ACTIVATE`, `HIKKI_WORKSPACE=<name>` (seeds a device workspace, skips onboarding;
  UI tests set it by default — pass `workspace: nil` to `launch()` to test onboarding).
- **Storage (option C)**: the workspace folder is the source of truth — one JSON file per page
  (`HikkiCore/Sources/Store/PageFile.swift`: `pages/<id>.json`, format-versioned, content as JSON); SQLite is a
  rebuildable cache/index. `HikkiCore/Sources/Store/WorkspaceSync.swift` reconciles on launch and app activation
  (newer side wins; a missing file deletes the page only if it was synced before — `pageFileState`) and writes every
  committed page change through (a GRDB transaction observer). It also watches `pages/` (a dispatch source;
  unchanged files are skipped by modification date + size) and posts `pagesChangedOnDisk`, so an open editor
  reloads a page another device changed (`window.hikki.reload`, declined while it has unsaved edits). While files
  are still downloading (iCloud placeholders / half-written files) it passes again with backoff — kqueue events are
  unreliable in iOS file-provider folders. Assets live in `<folder>/assets`. Not yet: conflict copies.
- **Workspace identity** lives in the folder (a workspace.json next to `pages/`: id, name, icon — `WorkspaceIdentity`); the per-device
  record (`AppPaths.workspace`) only adds the location. A device picking a folder that has one _opens_ that workspace
  (onboarding says so), and a newer identity from another device replaces the local name/icon on activation. Settings →
  Storage → Change folder re-points a workspace (`AppModel.changeLocation`: synced marks cleared, local pages written
  out, the folder's imported — nothing deleted).
- **Editor menus**: `editor/src/blocks.ts` is the one block catalog (groups, Markdown shortcuts, `turnInto`, `isActive`)
  behind the "/" menu (`editor/src/ui/SlashMenu.tsx`) and the selection menu's "Turn into"
  (`editor/src/ui/SelectionMenu.tsx`, positioned by Tiptap's BubbleMenu; its side panels stay inside the menu element
  or BubbleMenu hides on blur). Text/background colors are stored as palette names (`editor/src/extensions/colors.ts`) and
  styled from the `ink-*` / `wash-*` tokens — never raw CSS colors in the document.
- **Code blocks** (`editor/src/extensions/code-block.tsx`): lowlight with the `common` grammars, colored by the
  `syntax-*` tokens (Xcode's Default Light/Dark); new blocks use the last picked language
  (`editor/src/extensions/code-languages.ts`). "Auto-detect" (`language: auto`) guesses with our own signatures
  (`editor/src/extensions/code-detect.ts` — highlight.js's guess ties CSS/JS/Python on short snippets) and names the
  guess in the header; the same guess feeds lowlight, so colours and label agree. Node views are plain DOM with small React roots for controls (the editor
  is the core `Editor`, not `@tiptap/react`).
- **Block controls** (`editor/src/extensions/block-controls.tsx`, units in `editor/src/extensions/block-units.ts`): our
  own + / ⋮⋮ handle on pointer events (HTML5 drag-and-drop is unreliable in WebKit), centred on the block's first line;
  drag shows a ghost and a drop line (side edges make columns); a click opens `editor/src/ui/BlockMenu.tsx`. Fine
  pointers only. Block colours are `blockColor` / `blockBackground` attributes. Block-level highlights (drag
  source, the block a menu is open for) are node decorations from `editor/src/extensions/block-highlight.ts` —
  never classes on the node's DOM, which ProseMirror drops on redraw.
- **Rich blocks**: toggles (`editor/src/extensions/toggle.ts`; open/closed is not stored, so opening never saves),
  callouts, KaTeX formulas (`editor/src/extensions/math.tsx`; our panel replaces Tiptap's `prompt()`), tables
  (`editor/src/extensions/table.tsx` + `editor/src/extensions/table-ops.ts`, controls drawn by
  `editor/src/ui/TableOverlay.tsx`) and columns (`editor/src/extensions/columns.ts`: schema needs 2–5 columns, so
  removing one of two replaces the row; dragging a block onto another's side edge makes a row).
- **Page links** (`editor/src/extensions/page-links.ts`): `hikki://page/<id>#<block>`. The native side feeds the editor
  the page index (`window.hikki.setPages`) so pasted links get titles; "Copy link to block" puts a ready `<a>` plus the
  URL on the clipboard; a plain-text paste of a link becomes a labelled hyperlink; clicks go through the bridge
  (`openPage` with the block, `openLink` for the web) and `window.hikki.scrollToBlock` lands on the block.
- **Ruby / furigana** (`editor/src/extensions/ruby.tsx`): an inline node (`<ruby><rb>…</rb><rt>…</rt></ruby>`, reading as
  an attribute); ⇧⌘R or Format → More → Ruby opens the reading panel, prefilled from the native tokenizer
  (`HikkiCore/Sources/Search/JapaneseReading.swift`, `suggestReading` message): a phrase comes back as kanji runs with
  readings and bare kana (役に立ちます → 役(やく)に立(た)ちます), one ruby per run; "Whole" puts one reading over all of it.
- **Full screen (macOS)**: `Hikki/Sources/FullScreenScrim.swift` fades the top of each column while the window is in full
  screen, where the auto-hidden toolbar slides down over the content (Photos). `HIKKI_DEBUG_SCRIM` forces it on.
- **Find, spelling, insets**: find and replace is `editor/src/extensions/find.tsx` (Tiptap's extension, RE2 regex) with
  `editor/src/ui/FindPanel.tsx`; the page handles ⌘F/⌥⌘F/⌘G itself, the native Edit menu and the page ⋯ menu ("Find
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
  palettes stay in the tokens and `[data-tone]` CSS for when a picker returns.
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
