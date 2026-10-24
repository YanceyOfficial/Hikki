# CLAUDE.md

Guidance for Claude Code (and any agent or human) working in this repository.

## Project Overview

Hikki is a Notion-like, local-first notebook for macOS, iPhone and iPad. The shell is SwiftUI; the page editor is
Tiptap 3 (React 19 + Tailwind CSS v4) running in a single long-lived `WKWebView` per window, bridged to Swift.
Tuist generates the Xcode project; bun manages the web workspace — a monorepo: apps in `apps/` (editor, bff, website), shared packages in `packages/`.

## Project Constraints (read first)

These rules are mandatory. Automated ones are noted.

- **Design tokens only.** Colors, spacing, radii, text sizes and component sizes come from `design/tokens.json`
  (shadcn/ui semantic color names, Tailwind scale names). Regenerate with `make tokens`; never edit
  `HikkiUI/Sources/Generated/DesignTokens.swift` or `apps/editor/src/theme.css` by hand. Swift uses `Theme.*`, `Spacing.*`,
  `Radius.*`, `Size.*`, `.font(.hk(.sm))`; the web uses Tailwind classes (`bg-background`, `text-muted-foreground`,
  `rounded-md`, `p-2.5`). _Enforced by `make lint-design` (`scripts/lint-design.sh`)._ A justified exception carries
  a `design-lint: allow` comment on the same line.
- **Motion.** Everything that appears, leaves or reacts moves the same way, from the `motion` tokens. Web surfaces
  (menus, popovers, tooltips, panels, the outline list) take `hk-pop` — mounted when shown: `FloatingLayer` adds it,
  the Base UI popups in `apps/editor/src/components/ui/` carry it, a React panel stays mounted through its leave with
  `usePresence` (`apps/editor/src/components/floating.tsx`) — or `hk-pop-toggle` + `data-open` when they stay mounted. Lists
  mark the selected row with one gliding surface (`apps/editor/src/components/gliding-highlight.tsx`, rows `relative` +
  `data-index`), block tints fade (`.tiptap [data-id]`), hover fades and the 97 % press live in the shadcn `Button` /
  `Toggle` (restyled in `apps/editor/src/components/ui/`); Swift uses `Motion.easeOut()`. No per-component durations, easings or
  tw-animate classes. _Enforced by `make lint-design`._
- **Reusable UI lives in `HikkiUI`** (no app state: plain values + closures, a `#Preview` each, listed in the DEBUG
  gallery `Hikki/Sources/ComponentGallery.swift`, launch argument `-HikkiGallery`). Native components follow the same
  look as the web's shadcn style (`base-vega`: `Radius.md` controls, `Theme.*` colors).
- **Web UI primitives are shadcn** (style `base-vega`, Base UI primitives, hugeicons; config in `apps/editor/components.json`,
  components in `apps/editor/src/components/ui/`). Add components with `cd apps/editor && bun run ui:add <name>` (the shadcn CLI,
  then oxfmt). Prefer a shadcn component over a hand-rolled one;
  editor-specific pieces live in `apps/editor/src/components/`. Fields, buttons, toggles, tooltips and popovers are always the shadcn
  components (`Input`, `InputGroup`, `Textarea`, `Button`, `Toggle`, `Kbd`…) restyled with classes — never a bare
  `<input>` / `<button>` (_checked by `make lint-design`_); a row in a menu, list or panel is `MenuRow`
  (`apps/editor/src/components/menu-row.tsx`: a ghost `Button` as a full-width row, `glide` in lists with a gliding
  highlight); Phosphor icons are imported by their `…Icon` names. Files under `apps/editor/src` are
  kebab-case (`apps/editor/src/components/find-panel.tsx`; the component inside stays PascalCase), and a folder holds either
  `.tsx` or `.ts`, never both: React lives in `apps/editor/src/components/` and `apps/editor/src/page/`; `apps/editor/src/core/`
  (bridge, protocol, editor setup, catalogs), `apps/editor/src/extensions/`, `apps/editor/src/lib/` and `apps/editor/src/hooks/` are
  plain TypeScript — an extension that shows a React panel calls the component file's `render*` helper
  (`renderFindPanel`, `renderTableOverlay`…) instead of holding JSX. Class recipes that aren't a component
  (`.hk-floating`, `.hk-column`) live in `apps/editor/src/style.css`, and `cn` is shadcn's own `cn` npm package, imported
  `from 'cn'` as the generated components do (`apps/editor/src/lib/utils.ts` is the one-line re-export `shadcn init` writes).
- **Icons go through one list** (`design/icons.json`, `make icons`). The native shell draws SF Symbols (each icon's
  `"sf"` name; the generated `Icon` enum, `IconView` / `IconLabel`, `Icon.glyph` for system-sized spots), falling
  back to the bundled Phosphor asset where there is no symbol; the web editor imports the same icons from the generated `apps/editor/src/generated/icons.ts` (Phosphor's component
  names), never `@phosphor-icons/react` directly: on iOS each wrapper draws the icon's SF Symbol instead — rendered
  natively by `EditorSchemeHandler` (`hikki-editor://sf/<name>.png`, `SymbolRequest` in HikkiCore) and painted as a
  mask in the text colour (`apps/editor/src/lib/sf-icons.ts`, told by `window.hikki.setIconStyle`); the Mac's page
  keeps Phosphor. No raw
  `Image(systemName:)` / `systemImage:` — _enforced by `make lint-design`_.
- **Keyboard shortcuts come from one registry.** `design/shortcuts.json` → `make shortcuts` generates
  `Hikki/Sources/Generated/Shortcuts.swift` (`Shortcut.x.keyboardShortcut` / `.display`) and
  `apps/editor/src/generated/shortcuts.ts` (`matchesShortcut`, `shortcutLabel`, `tiptapShortcut` in
  `apps/editor/src/core/shortcuts.ts`). Each entry says who binds it: `app` (native menu), `editor` (the page; menus only
  display it) or `both`. No literal key equivalents or "⌘X" labels in code; the generator refuses two shortcuts on
  the same keys. _Checked by `make lint-design`._ Users rebind any of them in Settings → Shortcuts: the overrides
  (`HikkiCore/Sources/Shortcuts/KeyCombo.swift` — what may be bound, conflicts) live in
  `Hikki/Sources/ShortcutStore.swift` (UserDefaults; `Shortcut.keyboardShortcut` / `.display` read it, observed by the
  menus) and reach the page through `window.hikki.setShortcuts`, where `ShortcutOverrides`
  (`apps/editor/src/extensions/shortcuts.ts`) runs a rebound shortcut on its new keys ahead of the default-bound keymaps.
- **Copy language.** User-facing strings are keys, never literals: native `app:<area>.<element>` keys in
  `Hikki/Resources/Localization/Localizable.xcstrings` (interpolations become `%@`, e.g. `app:page.edited %@`); web
  `t('area.key')` with catalogs in `apps/editor/src/locales/`. English is the source; zh-Hans must be complete. The native
  side tells the editor its language (`window.hikki.setLocale`). _Enforced by `make lint-l10n`
  (`scripts/l10n-audit.mjs`): missing / unused keys, untranslated values, placeholder mismatches, literal UI text._
- **Secrets stay server-side.** Third-party API keys (Unsplash) live only in the BFF (`apps/bff/`, Hono on Vercel).
  Unsplash rules: hotlink `urls`, attribute the photographer with utm links, report picks via the download endpoint.
- **Pre-commit gate.** `.husky/pre-commit` runs lint-staged (oxlint + oxfmt for web files, `swift-format` for
  Swift), `make lint-design lint-docs lint-l10n`, the editor + BFF typecheck and web unit tests. `make check` adds the Swift tests and both
  platform builds. Don't `--no-verify`.
- **Tests with every change.** Web logic: vitest in `apps/editor/test/`. Swift data/logic: Swift Testing in
  `HikkiCore/Tests/`. User-visible flows: XCUITest in `HikkiUITests/` (look elements up by accessibility identifier).
  A bug fix comes with a test that fails without the fix — check that it does.
- **Bridge protocol.** Messages are defined twice — `apps/editor/src/core/protocol.ts` and
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
  `Hikki/Sources/Generated/ErrorMessages.swift`, `apps/editor/src/generated/errors.ts`, `apps/bff/src/generated/errors.ts` and both
  string catalogs; numbers by area: 1xxx app, 2xxx pages & workspace, 3xxx editor, 4xxx files, 5xxx AI, 6xxx search,
  7xxx network — never reused). Report with `Toasts.report(code, error, category:)` natively (logs it with an incident
  id via `Incident.report`, then a toast with the code and "Copy details"), `reportError(id, error)` in the editor
  (`apps/editor/src/core/errors.ts`, over the `reportError` bridge message); confirmations are `Toasts.shared.show` /
  `notify`. The BFF answers failures as `{error: {code, id, message}, requestId}` (`apps/bff/src/http.ts`). No ad-hoc alerts
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
cd apps/editor && bun run dev   # the editor alone in a browser (console-logging bridge)
cd apps/website && bun run dev  # the website locally (TanStack/Solid docs: bunx @tanstack/intent@latest list)
cd apps/bff && bun run dev      # the BFF locally (needs UNSPLASH_ACCESS_KEY); the editor reads VITE_HIKKI_BFF_URL (apps/editor/.env.*; prod: unsplash.yancey.app)
```

## Code Structure

```
design/tokens.json            design tokens (single source)
PRODUCT.md, DESIGN.md         impeccable's records: product truth (platform ios; apps/website/PRODUCT.md is the site's) and the
                              visual system in words ("The Study Desk"); .impeccable/ holds its sidecar and critique snapshots
design/icon/                  app icon (Hi✦): layered SVGs for Icon Composer (generate.mjs → hi-star/, --all for alternatives)
design/logo/                  wordmark + lockups (generate.mjs: text → outlines with fontkit, sparkle i-dot)
scripts/gen-tokens.mjs        tokens → Swift + Tailwind theme
scripts/lint-design.sh        no literal colors/fonts/spacing/radii in view code
design/errors.json            error codes for app, editor and BFF (single source; scripts/gen-errors.mjs)
design/fixtures/              fixtures both sides are tested against (content-text.json: block texts, Swift + editor)
design/store/                 App Store material: listing text per locale (fastlane deliver layout), the demo workspace
                              screenshots are taken over, shoot.sh (simulators; iPad landscape through
                              HikkiUITests/StoreScreenshot.swift), mac-frame.mjs; README.md is the field-by-field guide
Configs/Version.xcconfig      MARKETING_VERSION / CURRENT_PROJECT_VERSION
Project.swift                 Tuist manifest (targets: Hikki, HikkiCore, HikkiSearch, HikkiAI, HikkiUI + their tests, HikkiUITests)
Hikki/Sources/                app: SwiftUI shell, navigation (tabs), sidebar, page bar, search, editor host
Hikki/Resources/AppIcon.icon  Icon Composer document (merged from design/icon/hi-star; actool renders all sizes)
HikkiCore/Sources/            framework: Store (GRDB/SQLite, page tree, assets, tabs model), Text (Japanese readings),
                              Bridge (protocol, JSONValue), Logging (file log, MetricKit crash collection),
                              Layout (`DeviceRules`: every per-device rule — orientation, split view, the Duo's vertical bar), Shortcuts (KeyCombo)
HikkiSearch/Sources/          framework: the search engine — its own SQLite index (trigram FTS5, BM25), query parsing,
                              ranking, pinyin keys, fuzzy titles; tests in HikkiSearch/Tests/
HikkiAI/Sources/              framework: AI — one streaming client over OpenAI (Responses) and Anthropic (Messages) with
                              their own web search + citations, the fixed model catalog, answers as Markdown blocks
                              (swift-markdown) and code colouring (HighlightSwift); tests in HikkiAI/Tests/
HikkiUI/Sources/              framework: reusable SwiftUI components + Theme
apps/editor/src/                   web editor: main.tsx + style.css; each folder below holds only .tsx or only .ts
apps/editor/src/core/              bridge, protocol, transport, editor setup, block catalog, i18n, shortcuts, links, page store
apps/editor/src/extensions/        Tiptap extensions (.ts; React panels are drawn through the components' render* helpers)
apps/editor/src/components/        editor UI (.tsx): menus, panels, the floating layer, icons (kebab-case files)
apps/editor/src/components/ui/     shadcn components (generated via `bun run ui:add`)
apps/editor/src/page/              page header, cover picker, outline (.tsx)
apps/editor/src/hooks/             React hooks (useEditorSnapshot)
apps/editor/src/lib/               data helpers: cover catalog, Unsplash client, emoji data; shadcn's utils re-export
apps/editor/test/                  vitest
apps/bff/                          backend-for-frontend (Hono, Vercel): Unsplash proxy, YouTube embed shim; tests with `bun test`
apps/website/                      the site at hikki.yancey.app (TanStack Start + Solid, SSR on Vercel, Tailwind v4 with its
                              own Mondrian palette — not the app's tokens): src/routes/ (/lab: an experimental
                              photo-grid layout), light/dark/system theme (`data-theme`, THEME_SCRIPT in src/theme.ts runs
                              before paint), screenshots in public/shots/ as WebP, each with a -dark twin (`Shot`), made by
                              `bun run shots <captures>` (sharp; crops in shots.json; public/og.jpg is the link-card JPEG);
                              the download moment is src/components/store.tsx — until APP_STORE_URL in src/site.ts is
                              set, "Coming to the App Store" is a status line in the header and the foot offers a
                              mailto (CONTACT_EMAIL) and the GitHub releases; set, both become the download link;
                              /privacy (src/routes/privacy.tsx) is the privacy policy, written from what the app
                              does — change it when storage, AI, the BFF or embeds change what leaves the device
packages/                     shared web packages (bun workspaces `apps/*`, `packages/*`): editor extensions and code
                              more than one app uses, each its own package.json, consumed from source
packages/excalidraw/          @hikki/excalidraw: Excalidraw 0.18.1 (pinned) for drawings — src/scene.ts (stored data,
                              text, Mermaid), src/components/drawing-canvas.tsx (the lazy `@hikki/excalidraw/canvas` entry), vite-plugin.ts
                              (bundles every font, drops the esm.sh fallback); tests in packages/excalidraw/test/
HikkiUITests/                 XCUITest flows
```

## Gotchas

- **swiftly** on `PATH` shadows Xcode's Swift and breaks `tuist install`; the Makefile strips it.
- **Linking**: GRDB is one dynamic framework (`Tuist/Package.swift` `productTypes`) — as a static library it was linked
  into both HikkiCore and HikkiSearch, two copies in one process. Release merges our four frameworks into the app binary
  (`MERGED_BINARY_TYPE = automatic` on the app; Debug keeps them separate); GRDB stays out of the merge (marked mergeable
  from Tuist's package project, the merged app looked for its symbols in an empty stub and crashed at launch). The editor
  bundle ships without a source map and with KaTeX's woff2 fonts only (`katexWoff2Only` in `apps/editor/vite.config.ts`).
  Measured (Instruments' App Launch, Release, a demo workspace): ~610 ms to the first frame, ~400 ms of it SwiftUI/AppKit
  building the window; our `HikkiApp.init` is ~22 ms. The editor's files are served on the main thread, so it is ready
  only once the window has drawn (~950 ms); starting its web view earlier (at `HikkiApp.init`) gained nothing.
- `make test-core` (tuist test) regenerates a test-only workspace; the target regenerates the full one afterwards.
- **Window chrome is native**: the system `NavigationSplitView` and window toolbar (Liquid Glass groups: back/forward
  `ControlGroup`, tabs, page actions). Don't reintroduce a custom title bar — an earlier one needed an isa-swizzled
  layout hook to keep the traffic lights in place. The page scrolls under the toolbar (WKWebView
  `obscuredContentInsets` on macOS, an explicit scroll inset on iOS).
- **Sidebar**: Mac/iPad draw our own rows in a `LazyVStack` (`Hikki/Sources/SidebarView.swift`) — a native `List`
  paints selection in the system accent (not the colour tone) and swallowed row drops on iPad. Fills on the sidebar use
  resolved colours (dynamic ones picked up the active window's vibrancy). The tree is one flat list of plain
  `SidebarRow`s (`PageTree.visibleRows(expanded:)`: id, title, icon, depth, expansion — no edited time) drawn by an
  `Equatable` `PageTreeRow` with its selection, drop line and pill colour passed in as values: no row reads the
  navigator, the model or `\.self` in its body (menus read the page by id when built, `PageActionsFor`), so a save,
  a navigation or a drag redraws only the rows that changed. `HIKKI_DEMO_PAGES=<n>` seeds n pages and
  `HIKKI_DEBUG_SIDEBAR_STATS=<file>` counts row bodies for `testSidebarRowsStayPutWhileTyping` (500 pages: before,
  opening a page redrew every built row and each save several; now one and none). Markdown / HTML / text files or folders
  dragged onto it import (`Hikki/Sources/SidebarFileDrop.swift`): on a page row as its children (the row tints as for
  "inside"), elsewhere at the top level (the sidebar is outlined); ContentView runs the import through
  `Navigator.importDrop` → `AppModel.importFiles(_:parentId:)`. A page row's own drag carries a page link, never a
  file, so the two never mix; iPad drags (typed documents, no file URL) load as a temporary copy.
- **Device compatibility lives in two files**: `HikkiCore/Sources/Layout/DeviceRules.swift` (native — a table of
  iPhone / iPhone Duo folded and unfolded / iPad / Mac: orientation — phones and a folded Duo upright, iPads and an
  unfolded Duo on their side, through `OrientationDelegate` in `Hikki/Sources/HikkiApp.swift` — split view, the
  vertical bar) and `apps/editor/src/lib/device.ts` (the editor's touch / pointer media queries). `#if os()` only separates
  the Mac from iOS; per-device behaviour is a named rule there, decided from the screen or window, never the idiom.
- **iPhone is its own layout**, not the Mac's squeezed — chosen by the window's width, never the device (Apple's
  "Preparing your app for iPhone Duo": no `userInterfaceIdiom`, orientation or screen checks): a compact width gets the
  iPhone layout, a regular one the iPad's (an unfolded iPhone Duo, a large iPhone on its side); its top bars stay 24 pt clear of the screen's top edge
  (`clearOfTopEdge`: the Duo shows its status bar beside the camera, so its top inset is a few points). Where the system
  has a vertical bar (iOS 27.1 `toolbarVerticalEdge`, read once in `RootView` as `verticalBarEdge`: the Duo's strip
  beside the camera), the floating bar's buttons and Home's ☰ are toolbar items the system puts there instead, and the
  page's web view runs under the bar (its cover to the edge; the column and the cover's buttons add CSS
  `env(safe-area-inset-*)`, which is 0 everywhere else). Simulator: `simctl io … screenshot --display=<id>` (see
  `simctl io <device> enumerate`) — the default display may be the Duo's inner screen, black while folded (prototype: the "Hikki iPhone redesign" canvas): the collapsed
  split view's sidebar column is `Hikki/Sources/PhoneHome.swift` (a ☰ · Home top bar, All pages / Trash tiles,
  "Jump back in" cards, Quick create — a blank page, today's note titled with the date, a page from the clipboard
  (`QuickNote`, HikkiCore) — Ask AI suggestions sent with this week's pages (`Navigator.pendingAIQuestion`), This
  week — HikkiUI's `WeekActivityCard` over the store's daily activity, every device's writing (a newer page from the
  folder counts its added words on the day it was edited, `importPage(_:expecting:)`) — recently edited, and favorites; the lists come
  from a `HomeDigest` (HikkiCore) worked out per tree change, the activity read in a task) and opening anything shows the detail through `Navigator.compactColumn`
  (`preferredCompactColumn`). The page tree is Notion's side drawer: `Hikki/Sources/PhoneDrawer.swift` (workspace +
  search, favorites, the tree — its actions on a long press, Add a page, then All pages · Trash · Settings fixed at the bottom)
  inside HikkiUI's `SideDrawer` (`HikkiUI/Sources/SideDrawer.swift`, exodus-ios's drawer, 75 % of the width: the content is a card pushed
  right and dimmed; a UIKit pan takes horizontal drags anywhere — flick projection, rubber band past open — and lets a
  horizontal list keep its drags unless it sits at its leading edge; ☰ or a tap on the card toggles; `Motion.easeOut()`). Root screens and pages float one bottom bar —
  `FloatingActionBar` (HikkiUI): Search · Ask AI · New page at home, Outline · Ask about this page · Edit on a page
  (hidden while the keyboard is up); the page's ⋯ is a sheet (`Hikki/Sources/PhonePageActions.swift`: quick tiles,
  history, export, move, facts). All pages groups by day (`RecencyGroup`, HikkiCore). Ask AI is a native chat sheet
  (`Hikki/Sources/AIChat.swift`: the open page's text as context, model menu, web search, `AIPrompts.chat`; answers render through `AIMarkdown` — see AI). Left
  out of the compact layout: tabs, split view, the inspector panel, Home's table. Search is a full-screen cover
  (the field fixed at the top, results filling the rest). A page runs to the top of the screen: the scroll view has no
  top inset and the editor makes that room itself (`setInsets` with `bleed`, `--hk-bleed-top`), so a cover fills it
  behind the status bar and the glass buttons (`.hk-cover`) and a page without one starts below them.
- **Data directory**: `HIKKI_DATA_DIR` overrides it (UI tests, demos). DEBUG hooks: `HIKKI_OPEN_TABS=a,b`,
  `HIKKI_OPEN_SEARCH`, `HIKKI_OPEN_FIND`, `HIKKI_DEBUG_NAV=a,b,c`, `HIKKI_DEBUG_SPOTLIGHT_QUERY=<text>` (logs the page ids Spotlight ranks), `HIKKI_OPEN_FILE=<asset>` (the PDF viewer), `HIKKI_OPEN_SPLIT=<page id>|file:<asset>|picker` (split view), `HIKKI_DEBUG_SIDEBAR` (hide + show the split view sidebar), `HIKKI_OPEN_SETTINGS`, `HIKKI_GALLERY_SECTION=<section>` (with `-HikkiGallery`: opens the gallery at that section), `HIKKI_DEBUG_TOAST` (a sample failure toast), `HIKKI_ACCESS=<state>` (the trial, see Trial and unlock), `HIKKI_OPEN_AI`, `HIKKI_OPEN_PAGE_ACTIONS`, `HIKKI_DEBUG_COVER_SHEET` (opens the page's cover sheet), `HIKKI_DEBUG_AI_ASK=<question>` (asks the AI panel about the open page) and `HIKKI_DEBUG_AI_EDIT=<words>` (selects them and runs Improve writing through `window.hikki.demoAI`) — screenshots of AI at work, which need a provider key, `HIKKI_DEMO_PAGES` (an empty workspace gets sample pages, ids fixed per title — `Hikki/Sources/DemoPages.swift`; `=<n>` above 1: n pages "Page 001"…, every tenth with three subpages), `HIKKI_ACTIVATE`, `HIKKI_FRESH_TABS` (skips the window's saved tabs; UI tests set it), `HIKKI_WORKSPACE=<name>` (seeds a device workspace — an iCloud one with `HIKKI_WORKSPACE_ICLOUD=1` — skips onboarding;
  UI tests set it by default — pass `workspace: nil` to `launch()` to test onboarding).
- **iCloud (CloudKit)** — how a workspace syncs (`Workspace.Location.cloud`, the default; `.device` keeps it on this
  device only; Settings → Storage → Sync with iCloud switches): the workspace folder lives in the app's own data
  (`<app data>/Workspace`, never iCloud Drive) and `HikkiCore/Sources/Store/CloudSync.swift` carries it through
  `CKSyncEngine` in the user's private database (container `iCloud.app.yancey.hikki`, zone `Workspace`): one `File`
  record per file of the folder — pages, history, comments, chats, assets, the drawing library, workspace.json —
  named by its path's SHA-256, the path and contents in encrypted fields (end-to-end encrypted), contents over 512 KB
  and every attachment as a `CKAsset`. `HikkiCore/Sources/Store/CloudMirror.swift` is the CloudKit-free half (tested
  in `CloudMirrorTests`): what changed in the folder since it last agreed with the cloud (size and date, then a
  content hash, kept with each record's system fields in a cloud-state file beside the database, not in the folder),
  and what to do with what arrives — written over a file unchanged here, otherwise settled: a page by the later
  change with the other as a conflicted copy (`ConflictCopy`), comments and chats merged (`mergeFiles`), anything
  else the cloud's — but a record still as last agreed (this device's own save fetched back) is no change
  there: the file stays and goes up. Changes go up after a quiet second (`noteLocalChanges`: `WorkspaceSync.Options.didWrite`, a scan
  every 10 s, activation), are sent before the app goes to the background (`flushWorkspace`), and come down with
  iCloud's pushes (`registerForRemoteNotifications`, iOS background mode `remote-notification`), on activation and
  on a pull to refresh (iOS: Home, the phone drawer, the sidebar, Trash — `syncRefreshable` in
  `Hikki/Sources/SyncRefresh.swift`, `AppModel.refreshFromCloud`);
  what arrives is a change on disk like any other (the folder reconciles, editors reload). The workspace belongs to the
  first iCloud account it syncs with (`CloudMirror.accountAllows`, kept in the cloud state): the engine starts only
  once `userRecordID` is that account and stops on any change (`.CKAccountChanged`, the engine's account events) —
  another account, or a sign-out and sign-in as someone else, sends and fetches nothing (`Status.accountChanged`)
  until the user turns iCloud off and on, which hands the workspace to the account in use (`releaseAccount`); a
  deleted zone sends everything again. A workspace still in an iCloud Drive folder (before CloudKit) is copied into the app once its
  files are all downloaded (`WorkspaceFolder.copyContents`, the folder left as it was; on the Mac a sandbox that
  won't open the old bookmark asks for the folder first) and becomes `.cloud`; folders can no longer be picked.
  A run on its own data folder (`HIKKI_DATA_DIR`: UI tests, demos) never syncs (`AppModel.cloudAllowed`) — its
  pages would land in the account's one workspace zone — unless `HIKKI_CLOUD=1`.
  Entitlements: `Hikki/Hikki-iOS.entitlements` and the Mac's two (see Mac sandbox); the CloudKit schema is created
  in the development environment on first save and must be deployed to production in the CloudKit console before
  a release.
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
  unreliable in iOS file-provider folders. Assets live in `<folder>/assets`; once a day at launch the ones nothing names any more — no string in any of the folder's JSON files (pages, history, comments, chats) or the database's rows — and untouched for 30 days are deleted (`HikkiCore/Sources/Store/AssetSweep.swift`; a file still downloading or unreadable skips the sweep). **Conflict copies**: nothing two devices
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
  (`apps/editor/src/core/convert.ts`: Tiptap's official `@tiptap/markdown`, HTML through the schema's parse/render rules;
  blocks with no Markdown form export as their container's blocks or their rendered HTML) — `window.hikki.exportPage`
  / `importDocument`. Export (page ⋯ → Export: Markdown, HTML, PDF, JSON = the page file) is packed by
  `PageExport` (`HikkiCore/Sources/Store/PageExport.swift`): one file, or — when the page attaches files — a folder
  with the document and `assets/` it links into relatively; saved with `.fileExporter` on both platforms. PDF renders
  the HTML export in an offscreen light web view (`createPDF`: one tall page). Import (File → Import…, the workspace
  menu) takes .md/.html/.txt — or a folder of them, such as an export — as new top-level pages, and a page's
  Import… (its context and ⋯ menus, `Navigator.importFiles(into:)`) takes several as its subpages; pictures and
  attachments a document links by relative path inside its folder are copied into the workspace's assets
  (`HikkiCore/Sources/Store/PageImport.swift`; nothing outside the folder), and Markdown's inline pictures are lifted
  into blocks (`liftBlockMedia`). Whatever the file holds, the body fits the schema (text fallback, its reason logged).
  Files dropped on the sidebar import the same way (see Sidebar; a dropped file's name is reduced to its last
  component before it is copied). DEBUG: `HIKKI_EXPORT_DIR=<folder>`
  skips the save panel, `HIKKI_IMPORT_FILE=<path>` imports at launch, `HIKKI_PICK_FILES=<path>|<path>` stands in
  for the picker (UI tests).
  **Bulk** (Settings → Workspace → Import & Export, `TransferSection` → `Hikki/Sources/BulkTransfer.swift`, one job
  per app on `AppModel.bulkTransfer`, running on when Settings closes: progress with Cancel, then a summary with the
  skipped files and why; `onFinish` is the hook for app-wide notices). Import takes many files and folders:
  `WorkspaceImport` (`HikkiCore/Sources/Store/WorkspaceTransfer.swift`) plans the tree — a chosen folder's contents
  go to the top level, a subfolder is a page (empty, its name) unless a document beside it has its name, `assets/`
  is attachments; Markdown/HTML/text go through the editor (`AppModel.importConverted`, relative links may climb to
  the chosen folder, not out), Hikki page files (JSON) come back as they were, keeping their id when it is free and
  their place by `parentId` too (a flat `pages/` folder rebuilds its tree). Export writes every live page into a new
  folder (`WorkspaceExport`: `Title.<ext>` plus `Title/` for subpages, sibling names safe and unique ignoring case,
  attachments once in the top `assets/` linked with `../`; a page whose parent is in the trash at the top, as the
  sidebar shows it); Markdown/HTML through any window's editor (each window registers its own), each stamped with the
  page's id and sibling place (`TransferStamp`: YAML front matter / `<meta>` tags; any front matter is stripped before
  a Markdown import), JSON = the page files with attachments kept by name, so a JSON export imported into an empty
  workspace is the same workspace. An import settles every page's id first (`WorkspaceImport.assignIDs`: the one it
  had when free here) and renames links and mentions between the imported pages to match (`PageLink.rewrite`), and
  stamped documents come back in their sibling order. DEBUG: `HIKKI_BULK_IMPORT=<path>|<path>`, `HIKKI_BULK_EXPORT=<format>|<folder>`.
- **Workspace identity** lives in the folder (a workspace.json next to `pages/`: id, name, icon — `WorkspaceIdentity`); the per-device
  record (`AppPaths.workspace`) only adds the location. A newer identity from another device replaces the local
  name/icon on activation, and one arriving from iCloud is adopted as it comes (a second device joining takes the
  workspace's name and icon).
- **Popups close one way**: every `FloatingLayer` opened with `onDismiss` (`apps/editor/src/components/floating.tsx`) joins
  one dismiss bus — a single pair of document listeners: Escape and a press outside every open layer dismiss the newest
  one, and the opener says what that means (the slash and block menus exit, the math and ruby panels cancel; it gets
  the reason and may answer `'keep'` — Escape in the block menu closes its submenu first). No popup installs its own
  outside-click or Escape listener. `dismissAllLayers` runs as `loadDocument` starts, so nothing outlives its page, and a
  menu or panel acting on a block later follows it through edits meanwhile (`followNode` / `followPosition` in
  `apps/editor/src/extensions/block-units.ts`: by block id, else mapped; gone → it closes). Base UI popups (shadcn) bring their own. A layer follows its
  anchor when the page scrolls, and a scroll over any popup (`hk-pop`) never reaches the page behind it
  (`apps/editor/src/lib/scroll-containment.ts`, one set of document listeners).
- **Editor menus**: `apps/editor/src/core/blocks.ts` is the one block catalog (groups, Markdown shortcuts, `turnInto`, `isActive`)
  behind the "/" menu (`apps/editor/src/components/slash-menu.tsx`) and the selection menu's "Turn into"
  (`apps/editor/src/components/selection-menu.tsx`, positioned by Tiptap's BubbleMenu; its side panels stay inside the menu element
  or BubbleMenu hides on blur). The selection menu and the block menu share "Turn into"
  (`apps/editor/src/components/block-type-list.tsx`) and the colour list (`apps/editor/src/components/color-list.tsx`). Text/background colors are stored as palette names (`apps/editor/src/extensions/colors.ts`) and
  styled from the `ink-*` / `wash-*` tokens — never raw CSS colors in the document.
- **Code blocks** (`apps/editor/src/extensions/code-block.ts`): lowlight with the `common` grammars, colored by the
  `syntax-*` tokens (Xcode's Default Light/Dark); new blocks use the last picked language
  (`apps/editor/src/extensions/code-languages.ts`). "Auto-detect" (`language: auto`) guesses with our own signatures
  (`apps/editor/src/extensions/code-detect.ts` — highlight.js's guess ties CSS/JS/Python on short snippets) and names the
  guess in the header; the same guess feeds lowlight, so colours and label agree. Node views are plain DOM with small React roots for controls (the editor
  is the core `Editor`, not `@tiptap/react`).
- **Block controls** (`apps/editor/src/extensions/block-controls.ts`, units in `apps/editor/src/extensions/block-units.ts`): our
  own + / ⋮⋮ handle on pointer events (HTML5 drag-and-drop is unreliable in WebKit), centred on the block's first line;
  anything inside a toggle, quote or callout shows the outermost container's handle (`handleUnitAtPos`; drops and caret
  commands still reach the blocks inside; list items keep one each; a columns row has none of its own — each
  column's blocks do, wherever in the column the pointer is: `unitAt` — in its own column's gutter, the gap between columns, never over the column before: `handleLeft` / `columnFloor`, and it steps aside while the pointer is on the column divider); drag shows a ghost and a drop line (side edges make columns); a click opens `apps/editor/src/components/block-menu.tsx`. Fine
  pointers only. The block menu is Notion's: a search field over the actions (and Turn-into targets), the block's kind
  as its section title (`apps/editor/src/core/block-kinds.ts`: catalog labels, an embed's service), then an embed's own
  actions (Replace — the embed panel on its link, same block; Caption — `apps/editor/src/extensions/embed-caption.ts`, a
  `caption` attribute drawn under the frame or card; Open in browser; Copy link to original), Turn into / Color, Copy
  link / Duplicate / Move to / Delete, Comment, Ask AI, and the block's words and characters at the foot. Move to
  (`apps/editor/src/extensions/move-block.ts`, its list `apps/editor/src/components/page-picker.tsx`; on iPhone the
  ⋯ sheet's searchable list, `touchMoveBlock`) sends the block — a list item in its list, comment marks left behind —
  with its text and words as `moveBlocks`; the app (`AppModel.moveBlocks`) flushes every editor, appends it to the
  target through the store (`BlockMove`: a blank page takes it in place of its empty line; the target as it was kept
  in its history; a locked target refused) and reloads editors showing it, and only once the reply says it is there
  does it leave the page (one undo step) — a failure never loses it. No per-block edited time (none is stored). Block colours are `blockColor` / `blockBackground` attributes. Block-level highlights (drag
  source, the block a menu is open for) are node decorations from `apps/editor/src/extensions/block-highlight.ts` —
  never classes on the node's DOM, which ProseMirror drops on redraw.
- **Drawings** (`apps/editor/src/extensions/drawing.ts`, "/" Drawing): an atom `drawing` block storing Excalidraw's
  live elements and its pictures as asset references (`files`: id → `{src, mimeType}`, never data URLs), shown in the
  page as a PNG preview asset (`preview`, twice the size; dark mode inverts it as Excalidraw does). A click opens the
  full-screen editor (`apps/editor/src/components/drawing-overlay.tsx` over `@hikki/excalidraw/canvas`, loaded on
  first open — Excalidraw and Mermaid are their own chunks, never in the page's start-up): changes go into the block
  as they rest (out of the page's undo, saved with `SAVE_META`), Done stores the preview. On a phone-sized screen
  (`DeviceRules.drawingsReadOnly`: the screen, not the window, so an iPad page beside its sidebar still draws) drawings
  are read-only: one opens in Excalidraw's view mode with Close, which writes nothing, and "/" and the keyboard's "+"
  panel offer no Drawing (`BlockType.available`); before a page switch's flush the
  native side awaits `window.hikki.finishDrawing()`, which closes an open drawing as Done does (preview included), and
  `loadDocument` still closes one at once (`closeDrawing`, its last strokes kept) when that couldn't. While it is open
  the iOS keyboard bar stays away (`HikkiWebView.hidesKeyboardBar`, from the `fullScreen` message). Excalidraw's
  Library is the Mac's (`window.hikki.setDrawings({library, readOnly})`, sent on ready and on a size-class change; elsewhere its button is hidden, and Browse
  libraries everywhere — excalidraw.com can't hand a library back): kept in the workspace folder as
  `<folder>/drawings/library.json` (`HikkiCore/Sources/Store/DrawingLibrary.swift`, format-versioned, the later write wins),
  read with the `drawingLibrary` request and written with `saveDrawingLibrary`; items are checked like scenes
  (`storedLibraryItems`) and written only when they changed, never over a Library that couldn't be read
  (`packages/excalidraw/src/library.ts`). The package never touches the bridge: the editor hands it a
  host (uploads through `uploadFile`, pictures read back with `fetch` — asset responses allow the editor's own origin
  — and Text to diagram). Text to diagram (Excalidraw's TTD dialog) is an `aiRequest` with action `diagram`
  (`apps/editor/src/core/diagram.ts`; `AIPrompts.diagramInstructions` asks for Mermaid only), which Excalidraw's
  mermaid-to-excalidraw draws. No network: every font Excalidraw draws with, Xiaolai (CJK, ~12 MB) included, is copied
  into the bundle under the editor's `excalidraw` folder (`setDrawingAssetPath`), and the build replaces Excalidraw's esm.sh fallback.
  Its text (text elements, as typed) is one block for search and word counts — `apps/editor/src/core/extract.ts` and `ContentText` agree
  through `design/fixtures/content-text.json`. Excalidraw's UI takes the colour tone through its CSS variables
  (`.hk-drawing-editor .excalidraw` in style.css). Each Done stores a new preview; the old one leaves `assets/`
  through the asset sweep (see Storage) once no version names it. Scenes are hostile (synced, imported, pasted — the same rules as embeds): only
  drawable element kinds are kept (no `embeddable` / `iframe` / magic frame, no `customData`), links are http(s) only
  and open through `openLink`, pictures and the preview are workspace assets only (`localAssetSrc`), pastes are
  checked like stored scenes (`checkPaste`) and Mermaid loses anything that loads (`safeMermaid`); the build also
  stops Excalidraw fetching pictures named in pasted HTML and running an iframe element's HTML (`REMOTE_PATCHES` in
  the package's vite plugin, its test fails if an Excalidraw update moves them).
- **Rich blocks**: toggles (`apps/editor/src/extensions/toggle.ts`; open/closed is not stored, so opening never saves; a
  summary may be a heading — `level` 1–3, set by `# `…`### ` at its start, cleared by Backspace there),
  callouts, KaTeX formulas (`apps/editor/src/extensions/math.ts`; our panel replaces Tiptap's `prompt()`), tables
  (`apps/editor/src/extensions/table.ts` + `apps/editor/src/extensions/table-ops.ts`, controls drawn by
  `apps/editor/src/components/table-overlay.tsx`) and columns (`apps/editor/src/extensions/columns.ts`: schema needs 2–5 columns, so
  removing one of two replaces the row; dragging a block onto another's side edge makes a row; Notion's 64 px gap holds
  the next column's block handle, the resize line in its middle shown only on hover; a row narrower than
  480 px — an iPhone's page — stacks its columns, a container query in style.css).
- **Network images** load like exodus's (`apps/editor/src/components/lazy-load-image.tsx`: skeleton, fade in, an icon on
  failure) — covers and the Unsplash grid use the component; body images get the same through
  `apps/editor/src/extensions/image-loading.ts` (`data-load` states styled in `apps/editor/src/style.css`; Tiptap's resizable view hides its
  container until an image loads, so the CSS shows it meanwhile). A picture already loaded in this run
  (`apps/editor/src/lib/loaded-images.ts`) skips both — a tab switch rebuilds the page, and its cover and pictures
  went through skeleton and fade again: a flash on every switch.
- **Covers**: the stored value is `gradient:<id>` or an image URL, and an image's vertical position rides along
  as a `#y=<0-100>` fragment (`apps/editor/src/lib/covers.ts`: `coverPosition`, `withCoverPosition`), so the store and
  the protocol keep a plain string. "Reposition" on the cover (`apps/editor/src/page/page-header.tsx`) drags the picture
  one pixel per pixel over its overflow and saves or cancels — Mac only. Touch screens (`pointer: coarse`) have no
  buttons over the cover and no Reposition: a long press on it, or the page ⋯ menu's Cover… (`window.hikki.editCover`),
  opens its sheet (Change cover, Remove; `apps/editor/src/page/cover-sheet.tsx`), and the page and callout icon pickers open
  as the same bottom sheet (`apps/editor/src/components/bottom-sheet.tsx`, keyboard-aware) instead of popovers. On every
  touch screen (iPhone and iPad) the cover's sheet is native: the editor says so when the page is ready
  (`window.hikki.setNativeCover`), the page only asks
  (`coverSheet`, with the editor's BFF address) and HikkiUI's `CoverSheet` (`Hikki/Sources/CoverSheetHost.swift`:
  actions, then Gallery · Upload — photo library, camera, Files into the assets — · Link · Unsplash through
  `UnsplashClient` in `HikkiCore/Sources/Text/Unsplash.swift`, credited, a pick reported as a download) hands the pick
  back as the page's own (`window.hikki.applyCover`). The built-in gradients are design tokens (`cover` in
  `design/tokens.json` → `--cover-<id>` for the web, `CoverGradient` in Swift). The icon pickers (page and callout)
  go native the same way (`setNativeIcons`; the page asks with `iconSheet` through `apps/editor/src/lib/icon-sheet.ts`,
  each opening under an id): HikkiUI's `IconPickerSheet` (`Hikki/Sources/IconSheetHost.swift`: search, categories,
  recent picks, Random, Remove, a callout's background) over the emojibase data the editor ships, read natively by
  `EmojiCatalog` (`HikkiCore/Sources/Text/EmojiCatalog.swift`), answered with `window.hikki.applyIcon` /
  `applyIconColor`.
- **Embeds** (`apps/editor/src/extensions/embed.ts`, transforms in `apps/editor/src/lib/embeds.ts`): one `embed` block — an
  `<iframe>` on a third-party page (sandboxed, keeps its origin) or on a snippet of HTML (`srcdoc`, no origin) — behind
  the "/" menu's Embeds group — a short list of work services: Embed, HTML, Google Drive, Figma, Miro, Loom, Airtable,
  Calendly, GitHub Gist, CodeSandbox, draw.io, Excalidraw (that row inserts a drawing block — a pasted
  excalidraw.com link still embeds), each by its Simple Icons mark (`simple-icons`, one named
  import per logo, `apps/editor/src/components/brand-logos.tsx`), in its brand colour (near-black ones in the row's text colour) at the icons' size.
  `embedFromURL` turns a pasted link into the provider's embeddable URL (YouTube, Vimeo, Figma's embed.figma.com, Maps,
  Drive/Docs, gists as a script snippet, tweets via platform.twitter.com, CodePen, draw.io's viewer, Loom, Excalidraw,
  Miro's live embed, Airtable views, Spotify, CodeSandbox, Calendly, Typeform) — services without a row still embed
  through Embed. Frames and link cards sit in one card (border, `rounded-xl`, `bg-card`; the height handle inside its
  foot). A gist's frame (`apps/editor/src/lib/gist-embed.ts`) gets our stylesheet over GitHub's — page fonts, no box of
  its own, `syntax-*` colours for the `pl-*` classes, the "hosted by" bar cut to name + view raw — with the page's
  tokens inlined (`readEmbedTheme`: a `srcdoc` frame can't read the page's variables), re-sent on a light/dark change
  without a reload, and reports its content's height (`postMessage`), so the frame fits it up to the block's height.
  Any other page is a link card instead of a frame (most sites refuse to be
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
  (`/embed/youtube/<id>`, `apps/bff/src/index.ts`) and the player sees that as its referrer.
- **Home** (`Hikki/Sources/HomeView.swift`) is a database of every page (Notion's): a native `Table` (Name, Location,
  Created, Edited, Words, Favorite — click a header to sort, double-click or Return opens) or a gallery of cards, with
  a filter and New Page on top; iPhone gets a list, and so does a Home narrower than the table's columns
  (`Size.homeNarrow`: a side of a split view), its filter on a line of its own. Sorting is `HomeSort` (Sendable, for Swift 6's table). The sidebar
  shows Home and Trash as Notion's row of icons (the open one widens into a pill with its name) and no section title.
  Trash has the same layout (table: deleted, deleted for good, Restore/Delete). Move to Trash asks first wherever it
  is chosen — page menus set `Navigator.trashRequestID` and ContentView presents `TrashConfirmation`
  (`Hikki/Sources/SidebarView.swift`: the title, the subpages going along — `PageTree.subpageCount`; the iPhone's ⋯
  sheet presents its own over itself) — as deleting for good and emptying the Trash do. Settings → Workspace → Keep deleted pages
  (7/30/90 days or until emptied, default 30; `TrashPreferences`) purges older trash at launch and activation
  (`DocumentStore.purgeTrash`); the deletion reaches other devices through the workspace folder.
- **Tabs** are the Mac's (`Navigator.usesTabs`): iPad and an unfolded iPhone Duo have no bar over the page — no tab
  strip and no title, the page's glass buttons float over its cover (no scroll-edge band, `EditorView.hidesTopEdgeEffect`;
  the Duo's go into its vertical bar) — and show one page at a time, as the iPhone does: a sidebar pick opens in place,
  back / forward walk that one tab, and a window keeps no tab but its split's two (`NavigationTabs.keepActiveOnly`).
  On the Mac a sidebar row focuses the tab already showing its page, or opens it as a new tab
  at the end; past `Navigator.recentTabLimit` the least recently focused tab closes (`NavigationTabs.openRecent`,
  recency kept in the saved tabs). A link in a page to another page opens it in a tab of its own
  (`Navigator.openLink` → `NavigationTabs.openLink`: that page's tab is focused, else a new tab right after the link's —
  from a side of a split, after the split, which stays whole — under the same limit); a link to a block of the page
  itself scrolls there; without tabs (iPhone, iPad) a link opens in place, in its side. A page has one tab: opening
  it from anywhere (search, Spotlight, a hikki:// link from outside, Open in New Tab, a drop onto a tab) focuses the
  tab showing it (`NavigationTabs.open` / `tab(showing:)`) — only Home may repeat, and Duplicate is the explicit
  exception; Open in Split View joins a page's own tab; separating a split on one page leaves one tab; tabs saved with
  repeats keep one each when restored (`closeDuplicates`). Back / forward (the toolbar's arrows, ⌘[ ⌘]) walk the
  window's history of pages shown, across tabs (`NavigationTabs.visits`): back returns to the page shown before, focusing
  its tab — a page opened from the sidebar goes back to where the reader was; closed tabs and gone pages are passed over. A tab dragged along the strip moves
  there, Chrome's way (`TabStrip`'s `onMove` → `NavigationTabs.move`: a split's two tabs move together, a gap between
  them means after them); the drag carries the page's link as before plus the tab's id as `app.yancey.hikki.tab`
  (in-process only, declared in Project.swift's Info.plist), which is how the strip tells a reorder from a page drop. A tab's context menu is
  Chrome's (`TabStripMenu` / `TabStripCommand` in `HikkiUI/Sources/TabStrip.swift`, the commands chosen by
  `NativeDetailToolbar` in ContentView): New Tab to the Right (Home), Open in Split View (where the window splits),
  Duplicate (the whole history), Move to New Window (Mac, a page: the "page" window group, then the tab closes — iPad
  has no such scene yet); for a page VS Code's Copy Link (`PageLink`) and Reveal in Sidebar (`Navigator.sidebarReveal`:
  parents expanded, the sidebar shown and scrolled to the row); then Close, Close Other Tabs, Close Tabs to the Right,
  Close All Tabs (one new tab on Home) — the rules in `NavigationTabs`.
- **Page links** (`apps/editor/src/extensions/page-links.ts`): `hikki://page/<id>#<block>`. The native side feeds the editor
  the page index (`window.hikki.setPages`) so pasted links get titles; "Copy link to block" puts a ready `<a>` plus the
  URL on the clipboard; a plain-text paste of a link becomes a labelled hyperlink, and so does a dropped one: a
  sidebar row's drag carries the page's link (`PageLink.dragItem`), the editor's `handleDrop` inserts it where it
  lands, and the toolbar's `TabStrip` (`TabStripDrop`, `HikkiUI/Sources/TabStrip.swift`) opens it — between tabs
  as a new tab (or that page's tab is focused), onto a tab in that tab. Clicks go through the bridge
  (`openPage` with the block — another page in its own tab on the Mac, see Tabs —, `openLink` for the web) and `window.hikki.scrollToBlock` lands on the block; a link to a
  page in the Trash toasts that with Restore, one to a page that is gone `pageLinkMissing` (ContentView's
  `followLink`) — a link never does nothing.
- **Mentions, emoji, typography**: "@" mentions a page (`apps/editor/src/extensions/page-mention.ts`, Tiptap's Mention: a
  `mention` node with the page id and its title at the time as `label`; the chip is a `hikki://page/<id>` link drawn
  with the page's current icon and title from the index, the label only a fallback). ":" suggests emoji
  (`apps/editor/src/extensions/emoji-suggestion.ts`, Tiptap's Suggestion over the icon picker's emojibase data) and inserts
  the plain character — not Tiptap's Emoji node, whose plugin rewrites every emoji in a page into nodes. Both menus
  are `suggestionMenu` (`apps/editor/src/extensions/suggestion-menu.ts`) over the shared `CommandList`. Typography turns
  -- … -> (c) into their characters; quotes, fractions and × stay as typed. Text extraction (search, word counts)
  treats mentions, ruby and inline math as part of the line.
- **Dates and reminders** (Notion's "@" dates): the "@" menu lists a Date group above the pages — what the words
  read as (`parseDateQuery` in `apps/editor/src/lib/dates.ts`, our own parser: English, Chinese and Japanese words,
  weekdays with Monday-first weeks, month names, M/D, ISO, "in 3 days", 3天后, times like 3pm / 下午3点半 / 午後3時)
  and the same as a reminder; the menu keeps spaces only while the words can still become a date (`datePrefix`).
  It puts a `dateMention` chip (`apps/editor/src/extensions/date-mention.ts`: an inline atom with `id`, `date`,
  `time` — wall-clock, "09:00" is 9:00 wherever the reader is — `remind` in minutes before, at 9:00 on a whole day,
  `done` and `snoozed`), drawn relative to today (`dateLabel`, redrawn each minute) by
  `apps/editor/src/components/date-chip.tsx`, blue with a reminder, red once it has rung until Mark done. A click
  opens its popover (typed words, shadcn `Calendar`, Include time, Remind, Mark done, Remove); in the iPhone layout
  HikkiUI's `DateSheet` instead (`setNativeDates`, the `dateSheet` request, `window.hikki.applyDate` — one answer per
  opening, sent when the sheet closes; `Hikki/Sources/DateSheetHost.swift`). As text (search, Markdown) a chip is
  "2026-10-22 09:30" (`dateText` / `DateMention.text`, held together by `design/fixtures/content-text.json`); as HTML a
  `<time datetime>`. Natively `HikkiCore/Sources/Store/DateMentions.swift` reads chips out of content (`DateEntry`:
  the line's words and block id), works out when each rings (`fireComponents`, the editor's `fireMoment`) and what
  Home lists (`Upcoming.items`: rung and not done first, then the next 7 days). `Hikki/Sources/Reminders.swift` keeps
  every live page's dates (`pagesWithDates` at launch, then the store's commit feed) and schedules the reminders
  still to ring as local notifications (`ReminderCenter`, at most 64, calendar triggers, the line as the title and
  the page under it; permission asked at the first one), so every device with the workspace rings. Mark done and
  Snooze (15 minutes) on a notification change the chip in its page (`AppModel.updateDate`, the move-blocks way:
  editors flushed, saved, open editors reload); a tap opens the page at the chip's block (`PageOpenRequests`; on
  the Mac through `MenuBarRequests`). A run on its own data folder schedules nothing unless `HIKKI_REMINDERS=1`.
  Home shows Upcoming (`Hikki/Sources/UpcomingSection.swift` over HikkiUI's `UpcomingList`) above the table and,
  on iPhone, after Jump back in; nothing when nothing is coming. No date ranges.
- **Ruby / furigana** (`apps/editor/src/extensions/ruby.ts`): an inline node (`<ruby><rb>…</rb><rt>…</rt></ruby>`, reading as
  an attribute); ⇧⌘R or Format → More → Ruby opens the reading panel, prefilled from the native tokenizer
  (`HikkiCore/Sources/Text/JapaneseReading.swift`, `suggestReading` message): a phrase comes back as kanji runs with
  readings and bare kana (役に立ちます → 役(やく)に立(た)ちます), one ruby per run; "Whole" puts one reading over all of it. The base text
  takes the page's marks (bold, colour…), the reading never does — a mark on the whole ruby moves onto its base text
  (`rubyMarksInside`) — and the reading is never part of a selection (not editable, not painted as selected).
- **Search** (⌘K, `Hikki/Sources/SearchPalette.swift`) is the `HikkiSearch` package: `SearchIndex`
  (`HikkiSearch/Sources/SearchIndex.swift`) keeps its own SQLite file (`search.sqlite` next to the database, WAL so
  searches read beside writes) with every page's title (and pinyin keys) and its text blocks with their ids, stored
  as written and once more folded (`SearchQuery.fold`: no case, no accents — "cafe" finds Café), the folded copy under
  a trigram FTS5 index. `Hikki/Sources/SearchIndexer.swift` feeds it — every committed page change through the
  store's commit observer (a record whose title, icon and edited time the index has is skipped), plus a reconcile at
  launch by edited time (the index is rebuildable; `SearchIndex.version` empties an outdated one). Each page's
  content is read once, natively (`ContentText.extract` in `HikkiCore/Sources/Store/ContentText.swift`: headings,
  blocks, attached files; block text reads as the editor's `apps/editor/src/core/extract.ts` — `design/fixtures/content-text.json` holds
  both to the same answers), for the index and Spotlight both. A search looks each term up on its own — FTS for
  three characters or more, a scan of the folded blocks for shorter ones — so every page holding a term is a
  candidate. `SearchRanker` orders results: whole title, its start, every term at a word start / anywhere, the pinyin
  keys; headings below titles, text below headings, the BM25 order (summed over a page's blocks, headings weighed 3×)
  among text matches, attached files a step below the page's own text, recent pages ahead on ties; an fzf-style
  subsequence of a title counts only when nothing else matched and the query has three letters or more. Attached
  files (inline images and file attachments) have their text read on device — PDFs through PDFKit, images through
  Vision's text recognition (`HikkiSearch/Sources/AttachmentText.swift`) — by one background reader
  (`HikkiSearch/Sources/FileTextReader.swift`), once per file name: the file texts live apart from pages, outlive a
  new index layout and the trash (a launch drops those of files no page — live or trashed — attaches any more,
  `pruneFileTexts`), and a file that can't be read is marked and not tried again (one not on the device
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
- **Split view** (a window at least 800 pt wide, on any device — `DeviceRules.allowsSplit`, `Navigator.splitAllowed`;
  `Hikki/Sources/SplitView.swift`): two tabs side by side, equals — Chrome's split view. `NavigationTabs` joins two
  adjacent tabs into a `Split` (leading, trailing); the window splits while its focused tab is in one, and the strip
  draws the pair as one joined tab with the focused half marked (`TabStripItem.joinedToNext`). Each side is a
  `PaneColumn` — the same view twice, so the sides can't drift apart: its bar (`PaneBar`: what it shows as a chooser —
  recent pages, More… for the picker — then the page's lock / star / ⋯, the panel's outline / comments / AI, swap
  sides, close this side) over its content, its own panel beside it (`Navigator.inspector(side)`, capped at 45 % of the
  side; the panels trade places with the pages on a swap) and its own AI chat (`trailingChat`); not split, the
  page's tools stay in the window toolbar. A click or a tap in a side focuses it before the view under it gets it
  (`PointerDownMonitor`: a local event monitor on the Mac, a touch-began recognizer on the iOS window, against each
  side's frame), so links, sidebar picks, menus and shortcuts (`focusedSceneValue(\.editor)`, ⌥⌘I, ⇧⌘N, Find, Lock…)
  act on the focused side, and back / forward walk the focused side's own history. Editors are by position: the
  window's main one draws the leading side, a second one (made on first use) the trailing; `PaneRoutes` changes load
  them, so focus moving changes nothing and a swap reloads both at their remembered scroll. An empty side is
  `Route.splitPicker` (the other side's PDF attachments, PDFs open in tabs, recent pages; a pick replaces it with no
  history entry; one left outside a split closes). Opened from View → Show Split View (⌘\\, again: the two separate into
  tabs), a page's "Open in Split View" (beside the focused side, or in the other side when split) or a tab's (it joins
  the focused tab; a split tab's menu has Swap Sides and Separate into Tabs). The sides meet at a hairline, each page (a cover too) running up to it; the grip over it is a native view
  (`SplitGrip`: AppKit / UIKit give a press to the topmost view, so it gets the drag over the web views) and drags the
  boundary (fraction remembered, each side at least `Size.splitMin`; a double-click puts it back in the middle);
  the trailing editor never takes the keyboard when its page loads (`window.hikki.setAutoFocus(false)` — an empty
  page's title would otherwise grab it from the page beside). The same page may be on both sides (write on one, read on
  the other — each editor reloads the other's saves, `pageSavedInEditor`). An AI handoff opens the panel of the side
  it came from (`PaneHandoff`). Nothing in a side's structure may depend on whether the window is split (a conditional
  modifier rebuilt the leading page's view and took the window's one web view with it: a blank page) — only the bar is
  an optional child; on iOS `EditorView` hosts the web view in a container of its own and puts it back on every update,
  since a stale wrapper going away still took it along under XCUITest. A saved split comes back without a side that was
  still a picker, and a side whose pages are all gone closes (`NavigationTabs.prune`). By drag: a sidebar row or a page's tab dropped onto a side shows there (`PageDrop`), and
  dropped on the right edge of the leading side — the right quarter, 96–240 pt — opens beside it: native content
  (Home, a PDF) through `EdgeDrop`, a page through the editor's own edge
  (`apps/editor/src/extensions/split-drop.ts`, `openInSplit` bridge message, `window.hikki.setSplitDrop`), since the web
  view takes the drags over it. Split already, that edge replaces the trailing side, so it outlines itself
  whole — as it does for a page held over its own right edge (`splitDropHere`) (`Navigator.splitDropHover`, set by `EdgeDrop` and the editor's `splitDropHover` message) — a half-width zone
  on the left read as a third column. iPadOS keeps the screen's very edge for "open in a new window".
- **PDF viewer**: a PDF attachment clicked in a page opens over it (`Navigator.showDocument` → `DocumentSheet` in
  ContentView: a page-sized sheet on the Mac, a full-screen cover on iOS, Close and Open in Split View in its bar),
  drawn natively by `HikkiUI/Sources/PDFViewer.swift` (PDFKit: continuous pages, zoom/fit, page number, find,
  thumbnails, an unlock prompt for password-protected files — the password is never stored); other attachments still
  open in Quick Look. `Route.file` (a PDF in a tab's pane) remains for the split pane and `HIKKI_OPEN_FILE`;
  `HIKKI_SHOW_FILE=<asset>` opens the sheet (UI tests).
- **Comments** (Notion's): ⇧⌘M or the selection menu's Comment starts a thread on the selected passage. The passage
  carries a `comment` mark with the thread's id (`apps/editor/src/extensions/comments.ts`), so it moves with edits; the
  words live natively in `comments/<page id>.json` in the workspace folder (`HikkiCore/Sources/Store/PageComments.swift`:
  format-versioned, merged by id with tombstones, iCloud conflict versions folded in), written through the
  `commentCreate` / `commentReply` / `commentResolve` / `commentDelete` bridge messages and pushed back with
  `window.hikki.setComments`. A block without text (an image, an embed, a file, a formula) gets a thread on the whole
  block instead — the block menu's Comment, or ⇧⌘M on a selected block: the thread carries `blockId` (an optional
  key in the file and in `commentCreate`; its `quote` is the block's name, "Image · photo.png"), nothing is marked,
  the block is outlined (`hk-comment-block`), and its card / badge / sheet are the passage threads' own. A draft is only a highlight until it is sent; adding or removing the mark is kept out of undo but saved (`SAVE_META`
  — `isUserEdit` in `apps/editor/src/core/bridge.ts` otherwise skips non-undo transactions), and an open thread whose mark is
  missing is marked again where its quote occurs once (`findQuote`). `apps/editor/src/components/comments.tsx` draws
  cards in the right margin when the window is wide (`#page[data-comments]` shifts the page left at ≥ 1240 px), count
  badges with a thread card under the passage otherwise; on a phone (`PHONE_QUERY`: coarse pointer, narrow or short
  window) the open thread or a new comment is a bottom sheet instead (shadcn `Drawer`, `apps/editor/src/components/ui/drawer.tsx`,
  restyled to the motion tokens): grabber, quote, comments with their actions always shown, the reply field at the
  foot riding the software keyboard (`visualViewport`) and clear of the native bottom bar (`--hk-inset-bottom`);
  scrim, swipe down or Escape close it, and neither opening nor closing it focuses the page. In the iPhone layout an open
  thread is native instead: the page only reports which one is open (`commentThread`, once `setNativeComments` says
  so — `PageScreen` does while it shows) and HikkiUI's `CommentThreadSheet` (`Hikki/Sources/CommentThreadHost.swift`:
  the thread read from the store, again on every change) shows it — passage, comments with ⋯ (Edit in place, Copy
  link, Delete), resolve ✓, the reply field; its actions run in the page as its own (`window.hikki.commentAction`),
  so deleting a thread takes its mark along. A tap on a commented
  passage opens its thread without moving the caret (the plugin cancels that touch's click, so no keyboard comes up);
  a click on a Mac still places the caret. Resolved threads lose their highlight. Each comment in an
  open thread shows its actions on hover (the first: resolve ✓; all: ⋯ → Edit in place, Copy link to discussion —
  `hikki://page/<id>#<thread id>`, which `scrollToBlock` turns into opening the thread — and Delete: a reply alone,
  the first comment the whole discussion); `commentEdit` rewrites one (`editedAt`; a merge keeps the newer edit).
  "@" in the field (typed, or its @ button) mentions a page: stored as `[@Title](hikki://page/<id>)` in the text
  (`apps/editor/src/lib/comment-text.ts`), drawn as a chip with the page's current icon and title, "@Title" natively
  (`PageComment.plainBody`). The page column is
  `.hk-column` alone in `apps/editor/index.html` (fixed 96 px side margins).
- **Inspector** (Mac/iPad: a full-height trailing panel inside the detail column — SwiftUI's `.inspector` widened the
  window — with the window title hidden while it is open, as in Photos; on iPad and an unfolded Duo the sidebar hides
  while it is open and comes back as it was, `sidebarBeforeInspector` in ContentView; iPhone: a sheet from the page ⋯ menu):
  `Hikki/Sources/InspectorView.swift`, one mode at a time (`InspectorMode`): the outline, the page's comments (open /
  resolved threads, Reopen) or the AI chat (`AIChatView`, the same conversation as the iPhone sheet, about the page beside it — and the passage selected
  in it, reported by the `selection` bridge message; Notion's composer: attached pictures / PDFs (+, drop, paste; sent as
  base64 — `HikkiAI/Sources/AIAttachments.swift` scales pictures to 1568 px), context chips, @ to add other pages, the
  field, attach · web · model · send). The toolbar's trailing
  end, as Xcode's: [star · ⋯] [outline · comments] [AI in its own circle, `AIGlyph`], the open view marked; View →
  Show Outline (⌥⌘I); no tab bar. The page's facts (location, created, edited, words and
  characters — then where its file lives with the folder's sync state, and whose AI key is in use: `PageFacts`, the
  same on the iPhone sheet) are the last lines of its ⋯ menu. The editor reports the outline and size with `pageInfo` (headings with
  block ids, words — CJK characters count one each — and characters from Tiptap's CharacterCount) and the heading the
  reader is in with `activeHeading` (a scroll-spy in `apps/editor/src/core/bridge.ts`: the last heading past a line under
  the toolbar, the last one at the end; a heading jumped to from an outline stays marked until the reader scrolls).
  The panel's outline puts it on a background that glides from row to row and keeps it in view; the page's own hover rail lights its bar, and its list opens on it (the shared `GlidingHighlight`, following the hovered row meanwhile). A heading
  picked in the outline lands at the top (`window.hikki.jumpToHeading`). While the inspector shows the outline the
  page's hover rail hides (`window.hikki.setOutlineRail`).
- **Tabs keep their place**: the editor reports where the page is scrolled (`scroll` message, throttled); ContentView
  remembers it per tab when another tab takes over and, when a tab is shown again, loads its page and scrolls back
  (`window.hikki.restoreScroll`, in the same JavaScript call as `loadDocument` and at once, so no frame of the page at
  its top is painted before the jump). Another page opened inside a tab starts at its top (`loadDocument`).
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
  key). Ask AI keeps one conversation per page (`HikkiCore/Sources/Store/PageChats.swift`: `ai/<page id>.json` in the
  workspace folder, synced and merged like comments — turns joined by id, New chat a `clearedAt` that keeps cleared
  turns from coming back; a conversation from Home, about no page, isn't kept): moving to another page shows its
  conversation, New chat (the panel's header, the iPhone sheet's bar, ⇧⌘N) empties it with an Undo toast, Settings →
  AI keeps them 30 / 90 days (default) / forever (`ChatRetention`, pruned at launch) or deletes them all, and a page
  deleted for good takes its conversation along (`onDeleted`). Past ~12k tokens since the last summary, the older turns
  are summarized by the model first (`HikkiAI/Sources/ChatCompaction.swift`, `AIPrompts.summarizeChat`) and sent as
  that summary in the instructions; the turns stay on screen. The model menu (`AIModelButton` in `Hikki/Sources/AISettings.swift` over `HikkiUI/Sources/ModelPickerList.swift`;
  the chat's composer and Settings → AI) is Notion's: Auto, starred models under Favorites, Recommended, Other
  models — a star on each row (`AIModelFavorites` in `HikkiAI/Sources/AIModelFavorites.swift`, UserDefaults
  `ai.favoriteModels`); a pick in the chat is also the default, which the page's Ask AI runs on. Each provider may have a base URL (blank: its own API; `HikkiAI/Sources/AIEndpoint.swift` — OpenAI's base
  includes `/v1`, Anthropic's doesn't, as in their SDKs; https, or http only to loopback). Keys live in the Keychain
  (`AIPreferences`, `Hikki/Sources/AISettings.swift`), one per provider and origin (`AIEndpoint.keyAccount`), so a key
  only ever goes to the address it was entered for. The editor asks through `aiRequest` / `aiCancel` (selected parts of blocks as inline HTML + nearby
  text) and gets `window.hikki.aiEvent`s back. `Hikki/Sources/AIService.swift` runs them (one per window, both
  editors) with the prompts in `HikkiAI/Sources/AIPrompts.swift`: an edit asks for JSON
  `{"blocks":[{id, html}],"notes":["…"]}` — the blocks hold only what belongs in the page (same ids, inline tags only:
  the edited text, a translation added after each sentence), `notes` everything said to the user (Markdown: answers, a
  check's verdict, why — reasons too, when asked; the per-change `explain` of the retired card style is gone) — an
  answer for short Markdown with web search; page text is wrapped in tags as data. In the page: the selection menu's
  "Ask AI" (`apps/editor/src/components/ai-panel.tsx`) runs a preset or the user's words, on the default model or
  one picked in the panel for that request (its chip opens the list in the panel's place: Auto, then the chat menu's
  groups with only the models that have a key — `PageModelMenu` in HikkiAI, sent with `window.hikki.setAIModels`,
  keys re-read as Settings opens or closes; `aiRequest.model`, kept by a retry or a follow-up);
  `apps/editor/src/extensions/ai-review.ts` shows an edit in the review style picked in Settings → AI (thumbnails:
  `ReviewStyleThumbnail` / `ThumbnailOption` in HikkiUI; `ai.reviewStyle`, sent with `window.hikki.setAIReviewStyle`; a
  stored `bubble` reads as `inline`): A `inline` (default) — removals struck through and additions as widgets in the
  page (decorations only, the document untouched) under a bar from `apps/editor/src/components/ai-review.tsx` (Accept ↵
  in one undo step, Discard esc, Retry, a follow-up); B `diff` — − / + lines in the bar
  (`apps/editor/src/components/ai-review-styles.tsx`). Either way the notes are a card under the bar (`NotesCard`), each
  drawn as page blocks with Copy and Insert below: inserting puts it after the selection's block (after notes inserted
  before) and keeps the edit under review (the insertion carries the review's meta, so it doesn't close it); Accept
  never inserts notes and leaves the card open over the accepted text; notes with no change (a check that found
  nothing) are the card alone. **Handoff**: a request in the user's own words (`custom`, `ask` — never a preset or a
  picture's question: `AITask.mayHandOff`, `mayHandOff` in the editor) may come back as `{"handoff":{"reason"}}` when it
  is no local edit or short answer (several steps, research, a lot of new writing, changes beyond the selection, a
  back-and-forth; the prompt lists the everyday edits that never hand off). An answer that starts like JSON is held back
  meanwhile. The editor closes its review and posts `aiHandoff {docId, instruction, selection}`; ContentView opens the
  chat by `AIHandoff.placement` (HikkiCore) — the inspector in AI mode (opened, or switched from outline / comments) on
  Mac and a wide iPad — in a split window, the panel of the side that handed off — the Ask AI sheet on iPhone — then sets the passage as the chat's selection and sends the
  instruction as the next turn of that page's conversation. Answers get a card (Insert below, Copy) that draws their
  Markdown as page blocks (`markdownBlocks` / `markdownDOM` in `apps/editor/src/core/convert.ts`: no media, web links only)
  and inserts it as blocks; answers and reasons are written in the app's language (`AIPrompts.languageLine`). The chat's
  answers (`Hikki/Sources/AIAnswerText.swift`) are full GitHub-flavoured Markdown: `AIMarkdown`
  (`HikkiAI/Sources/AIMarkdown.swift`, swift-markdown's cmark-gfm tree, ported from exodus-ios's MarkdownKit) gives
  blocks — headings, nested / numbered / task lists, quotes, fenced code, tables, rules — with inline styles; only
  http(s) links stay links (bare URLs autolinked), pictures show as their description, a lone `~` is not a strike. It
  parses the whole answer on every token: an unclosed fence is code to the end and a half-typed fence line is left out.
  Code blocks are HikkiUI's `CodeBlockView` (language, copy) coloured by `CodeHighlighter`
  (`HikkiAI/Sources/CodeHighlighter.swift`: highlight.js via HighlightSwift, each class mapped to a sentinel CSS grey
  read back as a `CodeToken`, drawn in the `syntax-*` tokens as the editor maps them; it waits for a pause while
  streaming and a growing block keeps its earlier colours); tables are HikkiUI's `TextTable`. HighlightSwift's
  resource bundle is copied into the app; when it's missing (`resourcesFound`) code stays plain rather than trap.
  The chat asks the model to think first (`AIRequest.reasoning`: OpenAI's reasoning summary, Anthropic's extended
  thinking with its own budget) and shows how the answer was worked out above it — HikkiUI's `ThinkingTimeline`
  (actovia's): live, the step it is on shimmering; then "Thought for 12 seconds", opening into the steps (thinking
  titled by its bold first line, `AIThinking`; web searches by query), grown by `ChatTimeline` and kept on the turn
  (`ChatTurn.thinking`). The page's own AI requests don't ask for thinking.
  **Making pictures** (`HikkiAI/Sources/AIPictures.swift`): with an OpenAI key the chat may make pictures — any chat
  model plans them in a hidden fenced `hikki-pictures` block (`{"pictures":[{prompt, shape, detailed, from}]}`, at
  most 4; `from` an earlier picture's id, named to the model as `[picture <id>]`, or `attached`), and
  `OpenAIPictureClient` draws them (OpenAI's Image API: generations, or edits with the source; streamed with
  partial pictures; Flare by default, Sunburst when detailed or changing one; a declined picture is `.refused`),
  two at a time, into the workspace's assets. They are `ChatTurn.pictures` (`ChatPicture`: making / done / stopped /
  failed, merged like turns) drawn by HikkiUI's `PictureTiles` (forming blurred, then Add to page — Replace in page
  when changing one — Use as cover, Try again; Add all), going in where the page asked (`ChatTurn.picturePlace`,
  `insertPictures` in `apps/editor/src/core/pictures.ts`: after the block, in place of an empty line or the picture
  changed, else at the caret, one undo step). The page has no entry of its own for pictures (no "/" row, no Make in Ask AI): the chat makes them when the
  user asks for them in their words — the `make_picture` tool (`AIPictures.tool`; `hikki-pictures` fences in older
  answers are only hidden now). Ask AI in the page has no Translate either.
  **Tools** (the chat only): `AIRequest.tools`; `AIToolLoop` (`HikkiAI/Sources/AIToolLoop.swift`) streams a round,
  runs the calls, sends their results back with the answer as the provider sent it (`AIMessage.Part.carried`: OpenAI's
  output items with encrypted reasoning, Anthropic's blocks with thinking signatures) and goes on, at most
  `maxRounds` (the last must answer in words). Besides `make_picture` there are actovia's file tools,
  `WorkspaceFiles` (`HikkiAI/Sources/WorkspaceFiles.swift`): list_directory, read_file, find_files, grep, write_file,
  edit_file, by paths relative to the workspace folder (`AppModel.filesFolder`) — no `..`, hidden files or links,
  coordinated reads and writes, a file still in iCloud starts downloading; Hikki's own data (`pages/`, `history/`,
  `comments/`, `ai/`, `drawings/`, `assets/`, workspace.json) is never written and left out of searches from the
  top. A write or edit waits on its card for Allow (`AIChat.runTool`); each call is a `ChatToolCall` on the turn
  (`ChatTurn.tools`), drawn by HikkiUI's `ToolCallCards` (diffs: `LineDiff` in HikkiCore; mapping in
  `Hikki/Sources/AIChatTools.swift`). Settings → AI → Use files in the workspace folder (`AIPreferences.usesFiles`,
  off by default: a file read goes to the model and may carry instructions meant to send it on) turns them on. The
  card asks with the whole change (texts are capped only when the turn is kept, `ChatToolCall.kept`), and a change
  too large to diff is refused, not asked about; protected names are compared folded (case, width, accents) and by
  their name on disk (`WorkspaceFiles.isProtected`).
  With web search on, the chat also asks OpenAI's search for pictures (`AIRequest.imageResults`: `search_content_types` + `include: web_search_call.results`, read from the search call's `image_result`s as `.image`) and shows them under the answer (HikkiUI's `ImageResultStrip`, kept as `ChatTurn.images`): Add to page fetches one into the assets (`WebImage`, `HikkiCore/Sources/Text/WebImage.swift`: LinkPreview's public-host rules) and puts it at the caret (`EditorController.insertWebImage`). While the model works the chat's "Thinking…" / "Searching the web…" line is HikkiUI's `ShimmerText` (a foreground
  band sweeping the muted text once per `Motion.loop`; still under Reduce Motion, which gets a spinner instead). Model output is untrusted: the reply is parsed tolerantly (`apps/editor/src/lib/ai-content.ts`;
  sanitized inline HTML through the schema, unknown keys dropped, an unreadable reply is an error), citations must be
  http(s), and any change to the page closes the review. On a picture stored in the workspace or a PDF attachment, the
  block menu's Ask AI asks about the file (Describe, Extract text, Explain, Summarize, or a question — answers only):
  `aiRequest.media` names the asset, `AIService` reads it off the main thread and sends it as an image part (scaled by
  `AIAttachments`) or a PDF document part, `AIPrompts.mediaMessages` puts it beside the task, and the answer card
  inserts below the block; an unreadable file is `aiMediaUnreadable`. Web pictures, video and audio get no AI (nothing
  reads or transcribes them on the device). **Ask AI edits the page** (Notion's review cards): the chat
  sends the open page as blocks with their ids (`window.hikki.aiPageBlocks`, `AIPageEdits.pageJSON`) and an answer
  that changes it ends with a fenced `hikki-changes` JSON block — rewrite / insert / move / delete, one block each —
  hidden from the chat and checked against those ids (`HikkiAI/Sources/AIPageEdits.swift`). The changes
  (`AIPageChange`, kept on the answer's `ChatTurn`) are HikkiUI's `AIChangeReview` under it: a card per pending change
  (a tap shows it in the page — `window.hikki.aiFocusChange`; ✓ / ✕ decide there), Approve all, and the reviewed ones
  in a stack of cards (newest on top, the AI's words green, a tap spreads it). In the page
  (`apps/editor/src/extensions/ai-changes.ts`, bar `apps/editor/src/components/ai-change-bar.tsx`) the focused change
  is drawn as tracked changes with Edit · Skip ⌫ · Approve ↵; each verdict moves to the next and goes back as
  `aiChange` (with the block's text before and after); an approval is one undo step, Approve all one step for all;
  editing a block makes only the changes naming it stale.
- **Find, spelling, insets**: find and replace is `apps/editor/src/extensions/find.ts` (Tiptap's extension, RE2 regex) with
  `apps/editor/src/components/find-panel.tsx`; the page handles ⌘F/⌥⌘F/⌘G itself, the native Edit menu and the page ⋯ menu ("Find
  in Page", the only way on a phone) call `window.hikki.find`. Spellcheck is WebKit's (Settings → Editor,
  `window.hikki.setSpellcheck`). `window.hikki.setInsets` gives the page the toolbar height for fixed panels and, on
  iPhone, the floating bar's room at the foot (`--hk-inset-bottom`, 0 while the keyboard is up).
- **Keyboard bar (iOS)**, Notion's (`Hikki/Sources/KeyboardToolbar.swift`): native SwiftUI over the software keyboard
  as the web view's input accessory (a runtime subclass of WebKit's content view, no private API) — one Liquid Glass
  capsule (HikkiUI's `KeyboardAccessoryBar`: tools scroll inside it, the keyboard button pinned at its end). With a
  caret: AI · + · Aa · file · photo · turn into · undo · emoji · comment · @ · delete · indent · outdent · move up ·
  move down · ⋯; with a selection: Aa · B · I · U · S · colour · AI · link · comment · ⋯ — the page's floating
  selection menu stays away meanwhile (`window.hikki.setKeyboardBar`). +, Aa and turn into open a panel in the
  keyboard's place at its height (the same subclass's `inputView`, swapped with `reloadInputViews`, the caret staying
  put): HikkiUI's `KeyboardBlockPanel` (the "/" catalog as flat two-column rows; turn into marks the current kind) and
  `KeyboardFormatPanel` (marks, Turn into, text colour and background — `Content`: the marks row only while the bar
  doesn't show those marks itself, and the bar's colour tool opens the colours alone, `Panel.color`); the bar's end
  button brings the keyboard back; a swipe down on a panel is only ever its scroll, never a close. The bar's tools are `ToolbarIconButton`'s `quiet` style
  (muted glyphs, the open tool's glyph in the tone, no box — Notion's), each a full `Size.touchTarget` (44 pt) square,
  as are the panels' rows. The page's floating bar steps aside while the keyboard bar is on screen (`KeyboardBar.shown`,
  set by the bar's own view: a hardware keyboard shows the bar alone at the screen's foot without the keyboard
  notifications). The panel's height is the software keyboard's, read from where the bar sits as the
  panel opens (room under it: `keyboardUnderBar`; the keyboard's frame notifications misled on a phone, and
  `GCKeyboard` says nothing about the software keyboard); with a hardware keyboard the system shows the panel all the
  same, at the last height. The content view is found by walking its class chain (`editingContent`): once it carries
  our runtime subclass its own name is `Hikki_WKContentView`, and a lookup by name alone found nothing — Aa then never
  swapped the keyboard. However the keyboard goes away (✕, a swipe, a tap elsewhere) the page's
  selection collapses (`keyboardWentAway`; WebKit would keep painting it greyed out), except under an AI edit just
  sent from the bar; ✕ on a native field gives the page its keyboard back, selection kept. AI, link and comment open a native glass
  field over the keyboard (HikkiUI's `KeyboardAIComposer` / `KeyboardLinkComposer` / `KeyboardCommentComposer`, drawn
  by `PageScreen`) on what `touchPrepare` / `touchCommentQuote` pointed at — the selection, or with none the caret's
  whole block for AI and comments (`selectBlockAtCaret`) and the word at the caret for a link; a comment is started and sent in one step
  (`touchComment`), so the page's own comment sheet stays shut — focusing its field scrolled the page to its end. ⋯
  is HikkiUI's `BlockActionsSheet` (the caret's block: Turn into, Color, Insert below; Copy link, Duplicate, Move to, Delete;
  Comment; Ask AI; its words). Photo, file and the "+" panel's media blocks open our own sheet (HikkiUI's
  `MediaSourceSheet`, hosted by `Hikki/Sources/MediaPicker.swift`: Camera and Photos tiles, Files, Scan document
  through VisionKit as one PDF); picks move into the workspace's assets natively (`EditorController.insertMedia`) and
  go in at the caret (`touchInsertMedia`). Contents and tools come from the page (`apps/editor/src/core/touch-tools.ts`:
  the catalog with Phosphor icon names the native `Icon` set shares, `touchState`, `touchRun`…). The page's web view
  ignores the keyboard's safe area (`PageScreen`), so the keyboard coming and going never resizes it (it juddered).
  The page paints its own selection (`apps/editor/src/extensions/selection-paint.ts`), so UIKit's highlight under it — whole line boxes in the
  tint, a grey band above the words — is swapped for an empty view (`hideSystemSelectionHighlight`: the public
  `UITextSelectionDisplayInteraction.highlightView`; caret and handles stay the system's; `testOnlyThePagePaintsASelection`).
- **Screen titles (iOS)**: each screen names itself (`.screenTitle(_:)`, `Hikki/Sources/ScreenTitle.swift`, the
  frontmost by depth through `ScreenTitleStack` in HikkiCore) and the root publishes it as the scene's
  `NSUserActivity` title (`app.yancey.hikki.viewing`), which iOS uses to name a screenshot — actovia's way.
- **iOS input zoom**: fields under 16px make iOS zoom the page on focus (fixed panels then sit off screen); touch
  devices get 16px fields via an unlayered rule in `apps/editor/src/style.css` (the page title is exempt). The
  viewport (`apps/editor/index.html`) allows no pinch zoom either: `maximum-scale=1, user-scalable=no`, which WKWebView
  honours (`testPinchDoesNotZoomThePage`).
- **Dynamic Type (iOS)**: `Font.hk` scales every token size by the Body style's metrics (`TextSize.scaled`; one size
  on the Mac), and the page's own words follow the same factor — `window.hikki.setTextScale` (sent on ready and on
  `UIContentSizeCategory.didChangeNotification`; `--hk-text-scale`, clamped 0.85–2, on `.tiptap` and the title
  `.hk-title`; the UI around them keeps its size). `testPageFollowsTheSystemTextSize` launches at XXXL.
- **Editor content safety**: content that doesn't fit the schema (corrupt, or from a newer Hikki) opens read-only and
  is never saved (`enableContentCheck`); housekeeping transactions (`addToHistory: false` — UniqueID stamping
  block ids, remote reloads) never count as edits; continuous typing still saves every 2 s (`maxWaitMs`).
- **Trial and unlock** (StoreKit 2, `Hikki/Sources/Purchases.swift`): free for `Access.trialDays` (14) days from the
  first download (`AppTransaction.originalPurchaseDate`; this install's first launch where the store can't say), then
  one non-consumable, `app.yancey.hikki.unlock` (universal purchase: iPhone, iPad and Mac). Past the trial without it
  the app is read only (`Access`, `HikkiCore/Sources/Store/Access.swift`): every editor is locked the way a locked page
  is (`EditorController.readOnly`, `EditorPageState.lockChange(…readOnly:)`), a `ReadOnlyBar` sits over the detail
  column, and every way to write — new pages, imports, restores, AI — goes through `Purchases.allowsWriting()`, which
  brings up HikkiUI's `UnlockSheet` instead (also Settings → About → Purchase, with Restore Purchases). Reading,
  search, copy and export stay open. Debug runs are unlocked unless `HIKKI_ACCESS=trial|expired|unlocked|store`;
  `store` asks StoreKit itself — the `Hikki-StoreKit` scheme runs with `Hikki/Hikki.storekit`.
- **Lock page** (Page menu ⇧⌘L, the page ⋯ menu, the sidebar context menu): `lockedAt` on the page
  (`DocumentStore.setLocked`; it bumps `updatedAt` like icon/cover so other devices pick it up). The load payload
  carries `locked`, `window.hikki.setLocked` flips it while open (each editor, split pane included, for the page it
  shows — `EditorController.setPages`); title, body, icon and cover refuse changes meanwhile
  (`EditorBridge.frozen`; words typed just before the lock are saved at the lock, not by a later debounce) and a toolbar lock (`LockIndicator`) unlocks.
- **Workspace**: first launch shows `Hikki/Sources/OnboardingView.swift` (iCloud or this device only) until the
  workspace file (`AppPaths.workspace`) exists (`HikkiCore/Sources/Store/Workspace.swift`). A workspace from before
  CloudKit may still name a folder by a security-scoped bookmark (`HikkiCore/Sources/Store/FolderBookmark.swift`)
  until it has moved into the app (see iCloud).
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
- **BFF on Vercel** (project root `apps/bff/`) compiles `src/` per file and runs it as Node ESM: relative imports need
  `.js` extensions (enforced by `NodeNext` in `apps/bff/tsconfig.json`), and `src/` must not rely on Bun/Node ambient
  types (read env through Hono's `env(c)` adapter); tests get Bun types from `apps/bff/tsconfig.test.json`.
- **Demo recordings** (macOS): `HikkiUITests/UnsplashDemoRecording.swift` drives a flow at a watchable pace when run
  with `TEST_RUNNER_HIKKI_RECORD=1`; record with `screencapture -v -V <s>` meanwhile. UI tests paste text rather than
  type it on macOS when spaces matter — synthesized keys go through the active input method (a Chinese IME eats them).
- **Colour tone**: one for now — `ColorTone.standard` (Kurenai, `design/tokens.json` `tone.default`); the other
  palettes stay in the tokens and `[data-tone]` CSS for when a picker returns. `make tokens` also writes the app's
  `AccentColor.colorset` from it, so system menus, selection and controls take the tone (where the user's system
  accent is "Multicolor" — a chosen system accent overrides every app's).
- **Settings** (`Hikki/Sources/SettingsView.swift`): pages (`SettingsPage`: General — appearance, language, editor,
  menu bar — then Workspace, Shortcuts, Search, AI, About; Shortcuts only with a keyboard: `GCKeyboard`) in a modal
  dialog over the window, Notion's: the pages in a sidebar, the open one's form beside it, a close button and Escape
  (HikkiUI's `SidebarDialog`, `Size.settings*`) — a sheet on the Mac (no separate Settings scene: the app menu's
  Settings… ⌘, and every other way in set `Navigator.isShowingSettings`; with no window in front the main window comes
  up first, through `MenuBarRequests`), a page-sized sheet on a regular-width iPad, the hub list in a sheet on iPhone.
  Each page is a grouped form of sections, the last page opened is remembered; ⌘W closes Settings, not the tab under
  it. `HIKKI_OPEN_SETTINGS=<page>` opens that page (screenshots). Optional integrations get pages here with a
  detected/not-detected status, exodus's way.
- **Appearance** (Settings → General → Theme) is applied app-wide (`NSApp.appearance` / window `overrideUserInterfaceStyle`),
  not with `preferredColorScheme`, which left parts of windows in the old scheme after switching back.
- **Mac sandbox** (the Mac App Store takes nothing else): `Hikki/Hikki.entitlements` (Release) — App Sandbox, network
  out, folders the user picks (read-write) with app-scoped bookmarks — and `Hikki/Hikki-Debug.entitlements`, the same
  plus the temporary folders (`/private/tmp`, `/private/var/folders`) where UI tests and demo runs keep their data
  (`HIKKI_DATA_DIR`); set per configuration with `CODE_SIGN_ENTITLEMENTS[sdk=macosx*]`, iOS has none. The app's data
  lives in its container; `Hikki/Resources/Mac/container-migration.plist` moves a Mac's data from before the sandbox
  (`~/Library/Application Support/Hikki`, the preferences) in on the first sandboxed launch. A workspace folder whose
  bookmark the sandbox won't open (made before it, or a revoked grant — `WorkspaceFolder.accessDenied`) syncs nothing
  and asks for the folder again (`workspaceFolderAccess`, its toast's Choose Folder… → `FolderAccessPanel`); the same
  folder picked again keeps everything (`AppModel.grantFolderAccess`), another one is a change of location.
- **macOS windows**: closing the last main window only hides it (Dock click restores it), its Settings sheet with it —
  `Hikki/Sources/WindowLifecycle.swift`.
- **Menu bar extra** (`Hikki/Sources/MenuBarExtra.swift`, macOS, Settings → General → Menu bar): its menu has no
  focused window, so New Page / Search / Settings post `MenuBarRequests.shared.pending` (`post` brings the main window
  up first) and that window's ContentView performs it (`MainWindows.requestTarget`). The glyph is `Hikki/Resources/Assets.xcassets` → MenuBarIcon (template PNGs at 1x/2x rasterized from
  `design/icon/hi-star/menubar.svg` — as an SVG asset the label rendered empty). The preference key has no dot (a
  dotted `@AppStorage` key on `MenuBarExtra(isInserted:)` looped the main menu).
- Simulators sometimes fail with "Busy (Application failed preflight checks)": `xcrun simctl shutdown all`, boot again.
