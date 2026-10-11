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
- **Reusable UI lives in `HikkiUI`** (no app state: plain values + closures, a `#Preview` each, listed in the DEBUG
  gallery `Hikki/Sources/ComponentGallery.swift`, launch argument `-HikkiGallery`). Native components follow the same
  look as the web's shadcn style (`base-vega`: `Radius.md` controls, `Theme.*` colors).
- **Web UI primitives are shadcn** (style `base-vega`, Base UI primitives, hugeicons; config in `editor/components.json`,
  components in `editor/src/components/ui/`). Add components only with `cd editor && bun run ui:add <name>` — the
  wrapper fixes the CLI's wrong `cn` import under TypeScript 7. Prefer a shadcn component over a hand-rolled one;
  editor-specific pieces live in `editor/src/ui/`.
- **One icon set: Phosphor.** Web uses `@phosphor-icons/react`; native uses the generated `Icon` enum (list icons in
  `design/icons.json`, run `make icons`; `IconView` / `IconLabel` in HikkiUI). No SF Symbols — _enforced by
  `make lint-design`_.
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
  favorite, trash) has its own methods, so a late debounced autosave can never revert it. The editor's `flush()`
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
scripts/gen-tokens.mjs        tokens → Swift + Tailwind theme
scripts/lint-design.sh        no literal colors/fonts/spacing/radii in view code
Configs/Version.xcconfig      MARKETING_VERSION / CURRENT_PROJECT_VERSION
Project.swift                 Tuist manifest (targets: Hikki, HikkiCore, HikkiUI, HikkiCoreTests, HikkiUITests)
Hikki/Sources/                app: SwiftUI shell, navigation (tabs), sidebar, page bar, search, editor host
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
- **macOS title bar**: SwiftUI re-installs a window toolbar on navigation changes. `Hikki/Sources/WindowChrome.swift`
  removes it via KVO and keeps the traffic lights centred in the header bar (`Size.tabBar`) via a `layout()` hook on AppKit's title-bar
  view (isa-swizzled subclass), because AppKit re-lays them out on its own (e.g. sidebar toggles). Rejected:
  SwiftUI's toolbar (covered the tab strip), an own `NSToolbar` (crashed), a titlebar accessory (covered the strip),
  frame-change notifications (async showed a jump; sync fought AppKit — the zoom button bounced ~100×/s), sliding
  the container (AppKit snapped it back, runaway). Verify with `HIKKI_DEBUG_SIDEBAR` + sampled button positions.
- **Data directory**: `HIKKI_DATA_DIR` overrides it (UI tests, demos). DEBUG hooks: `HIKKI_OPEN_TABS=a,b`,
  `HIKKI_OPEN_SEARCH`, `HIKKI_DEBUG_NAV=a,b,c`, `HIKKI_DEBUG_SIDEBAR` (hide + show the sidebar), `HIKKI_OPEN_SETTINGS`, `HIKKI_WORKSPACE=<name>` (seeds a device workspace, skips onboarding;
  UI tests set it by default — pass `workspace: nil` to `launch()` to test onboarding).
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
- Simulators sometimes fail with "Busy (Application failed preflight checks)": `xcrun simctl shutdown all`, boot again.
