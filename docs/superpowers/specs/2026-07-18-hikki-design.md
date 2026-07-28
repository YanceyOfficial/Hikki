# Hikki — Product & Technical Design

**Date:** 2026-07-18
**Status:** Approved (design review with user)
**Source spec:** `INIT_PROMPT.md`

Hikki is a Notion-like, local-first note-taking app for macOS built on Tauri 2, React 19, BlockNote, shadcn/ui, Jotai, and Rust.

---

## 1. Decisions made during design review

| Decision              | Choice                                                                     | Rationale                                                                                                                                                                        |
| --------------------- | -------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Storage architecture  | **Hybrid local-first**: files are source of truth, SQLite index is derived | User owns data; iCloud-safe; index rebuildable; clean future cloud path                                                                                                          |
| DB files over iCloud? | **No**                                                                     | SQLite/PGlite files are opaque binaries with WAL side-files; iCloud whole-file sync causes corruption/conflict copies. Sync plain files; keep DB as non-synced rebuildable cache |
| Voice STT provider    | **OpenAI** (`gpt-4o-transcribe` family)                                    | Reuses the OpenAI key already configured for AI features; no third provider                                                                                                      |
| API key storage       | **macOS Keychain** via Rust `keyring` crate                                | Keys never on disk in plaintext                                                                                                                                                  |
| Hierarchy encoding    | Flat folders + `parentId` in `document.json`                               | Moves are metadata edits; unlimited nesting without directory moves                                                                                                              |

## 2. App shape & navigation

- Single window; `createHashRouter` (desktop requirement) with routes:
  - `/` — Dashboard
  - `/doc/:id` — Document editor
- **Left sidebar** (existing template, repurposed): document tree with unlimited nesting and drag-to-reorder, Favorites, Recents, quick-search trigger, Dashboard link, Settings + user footer.
- **Right sidebar**: contextual panel per document — backlinks and document info (word count, created/updated). Toggleable.
- **Settings** is a dialog (`src/components/settings-dialog.tsx`), opened via sidebar footer or `⌘,`.
- **Command palette** (`⌘K`, cmdk): quick search (FTS-backed), navigation, commands (new doc, toggle theme, open settings…).
- **`AppShell` layout component** owns macOS window chrome:
  - `data-tauri-drag-region` on the header,
  - reserved left padding for traffic lights in windowed mode (config: `titleBarStyle: Overlay`, `trafficLightPosition {16,16}`),
  - padding collapses in fullscreen (traffic lights hide), listening to window fullscreen events,
  - reusable by every page.

## 3. Data model & storage

### Vault (user data, source of truth, syncable)

Default `~/Hikki`; location changeable in Settings (e.g. into iCloud Drive). Structure:

```
vault/
├── documents/
│   └── <uuid>/
│       ├── document.json    # meta + BlockNote blocks
│       └── assets/          # uuid-named images/attachments
└── vault.json               # tree order, favorites, vault-level prefs
```

`document.json` schema (v1):

```jsonc
{
  "schemaVersion": 1,
  "id": "uuid",
  "parentId": "uuid | null", // null = top-level
  "title": "string",
  "icon": "emoji | null",
  "cover": "asset filename | gradient id | null",
  "blocks": [/* BlockNote document JSON */],
  "createdAt": "ISO-8601",
  "updatedAt": "ISO-8601",
  "deletedAt": "ISO-8601 | null" // soft delete (Trash)
}
```

- Hierarchy: flat storage + `parentId`. Cycles rejected at write time.
- Trash: `deletedAt` set on delete (recursively for children); restore clears it; "Delete permanently" removes the folder.
- Assets: imported via Rust command (copy into `assets/`, uuid filename, original name kept in block props).

### Index (derived, never synced)

`~/Library/Application Support/hikki/index.db` (SQLite via `rusqlite`, bundled):

- `documents(id, parent_id, title, icon, word_count, created_at, updated_at, deleted_at)`
- `document_fts` — FTS5 over title + extracted block text
- `links(source_id, target_id)` — extracted from blocks; powers backlinks
- `activity(id, doc_id, kind, word_delta, at)` — edit events; powers dashboard stats
- `meta(key, value)` — schema version, last full index time

Properties:

- Fully rebuildable by scanning the vault (startup reconciliation + Settings "Rebuild index" action).
- A Rust file-watcher (`notify` crate) detects external changes (iCloud sync from another device, manual edits) and re-indexes changed documents, emitting an event so open views refresh.

### Version history (snapshots)

Every document keeps a rolling history of full snapshots so users can review and restore earlier versions:

- Storage: `documents/<uuid>/history/<UTC-timestamp>.json` — a full copy of `document.json` taken **before** an overwrite. Plain files → syncs with the vault, rebuild-free.
- Write policy: on `save_document`, snapshot the current on-disk version if the newest snapshot is older than **10 minutes** (or none exists). Rapid autosaves therefore coalesce into at most one snapshot per interval.
- Retention: keep the newest **50** snapshots per document; prune oldest on write.
- Restore: snapshot the current state first, then copy the chosen version over `document.json`, bump `updatedAt`, reindex. Restore never destroys the pre-restore state.
- Phasing: snapshot writing starts in Phase 2 (so history accumulates from day one); the history UI (browse versions with relative times, preview, Restore) ships with Phase 6 extras.

## 4. Rust backend (Tauri)

Rust owns all I/O; the webview never touches the filesystem directly.

**Command surface (IPC):**

- Vault: `get_vault_info`, `set_vault_path`, `rebuild_index`
- Documents: `list_documents` (tree), `load_document`, `save_document` (debounced autosave from frontend), `create_document`, `move_document`, `delete_document` (soft), `restore_document`, `purge_document`
- Assets: `import_asset(docId, bytes|path)` → returns `asset://` URL
- Queries: `search(query)`, `backlinks(docId)`, `recent_documents`, `dashboard_stats`
- Secrets: `get_api_key(provider)`, `set_api_key(provider)`, `delete_api_key(provider)` (`keyring` crate)
- Logs: `append_log(entry)`, `read_logs(filter)`, `clear_logs` (JSONL, rotating, in app-data `logs/`)
- Updater: via `tauri-plugin-updater` JS API

**Asset serving:** custom `asset://` protocol handler scoped to the vault directory (path-traversal-checked), so images/files render in the editor without exposing broad fs access. CSP configured accordingly (currently `null` in `tauri.conf.json` — will be tightened to allow only app origin, `asset://`, and provider API hosts).

**Frontend state:** Jotai atoms fed by a typed IPC layer (`src/lib/ipc.ts`) wrapping `invoke` with zod-ish runtime validation and error mapping. Components never call `invoke` directly.

## 5. Editor (BlockNote)

- `@blocknote/react` + `@blocknote/shadcn` so the editor inherits shadcn theming.
- Enabled: full default block set, slash menu, side menu, formatting toolbar, image blocks, file blocks, embeds (video/audio/web).
- Image upload / file attachment → Rust `import_asset` → `asset://` URL stored in block props.
- Custom slash-menu items: AI actions (Continue writing, Summarize page), template insertion.
- Title, icon (emoji picker), and cover edited above the BlockNote editor (Notion-style page header).
- Autosave: debounced (~800 ms) `save_document`; flush on navigation/blur/close.
- `data-testid` attributes at all interaction points; stripped from production bundles via a babel plugin in the Vite React plugin config (dev/test keep them).

## 6. AI layer — Writing Tools

**Interaction (modeled on Apple Intelligence Writing Tools, ref `IMG_6065.jpeg`):**

- Select text → "Writing Tools" entry in the formatting toolbar (and `⌘J`) → floating popover:
  - free-form "Describe your change" input,
  - primary actions: **Proofread**, **Rewrite**,
  - tone chips: **Friendly**, **Professional**, **Concise**,
  - transforms: **Summary**, **Key Points**, **List**, **Table**,
  - **Compose** (generation; also available with empty selection / from slash menu).
- Results **stream** into a preview card inside the popover; user chooses **Replace / Insert below / Discard**. Never destructive without confirmation.
- Model selector dropdown in the popover header (persisted default in Settings).

**Backend (`src/lib/ai/`):**

- Thin provider-abstraction client modeled on `@earendil-works/pi-ai`: `AiClient.stream(request) → AsyncIterable<TextChunk>`, providers OpenAI + Anthropic, each provider's current flagship + recommended models registered in one `models.ts`. Concrete model IDs are chosen at implementation time from each provider's current documentation (Anthropic IDs via the claude-api reference) so the defaults ship current, with the dropdown listing flagship + fast tiers per provider.
- HTTP via `@tauri-apps/plugin-http` fetch (bypasses webview CORS). SSE parsed in TS.
- Keys fetched from Keychain via IPC per request; never stored in JS state or localStorage.
- Errors map to standardized error codes (§8) — e.g. missing key → toast with "Open Settings" action.

## 7. Voice input (experimental)

- Gated by an **Experimental** toggle in Settings (AI section).
- Capture: `MediaRecorder` in the webview; `NSMicrophoneUsageDescription` added to the macOS bundle config.
- Transcription: OpenAI STT (`gpt-4o-transcribe` family) through the same plugin-http path with the OpenAI key.
- Entry points:
  1. Dictate into document — mic button in editor header; transcription inserted at cursor.
  2. Dictate a prompt — mic button inside the Writing Tools prompt field.
- UI: recording bar with elapsed time + waveform, using existing `orb.tsx` / ElevenLabs-style visuals (`shimmering-text.tsx` available for status text).

## 8. Settings, toasts, errors, logging

**Settings dialog sections:**

1. **General** — vault location (picker + reveal in Finder), rebuild index.
2. **Appearance** — multi-theme configuration modeled on shadcn's theme editor (`ui.shadcn.com/create`):
   - **Mode**: light / dark / system.
   - **Theme presets**: a gallery of bundled presets (e.g. Default, plus several curated color themes). Each preset is a complete shadcn token set (`--background`, `--foreground`, `--primary`, `--accent`, chart colors, sidebar colors, … in oklch) defining both light and dark variants, implemented as `[data-theme="<preset>"]` CSS blocks in `src/index.css`. Preview swatches in the gallery.
   - **Radius**: none / small / default / large (`--radius`).
   - **Mode management uses `next-themes`** (exodus pattern: `attribute="class"`, `defaultTheme="system"`, `enableSystem`, `disableTransitionOnChange`), with a `NativeThemeBridge` side-effect component syncing the selection to the OS window chrome via `getCurrentWindow().setTheme()` — Tauri's analog of exodus's Electron `nativeTheme` bridge.
   - Theme **preset** is applied as `data-theme` on `<html>` by a thin provider layered above next-themes; both persist (next-themes storageKey + localStorage for preset); editor (`@blocknote/shadcn`) inherits tokens automatically.
3. **AI** — per-provider API key entry (Keychain-backed, masked, test-connection button), default model dropdown, voice-input experimental toggle.
4. **Logs** — table viewer with level filter + text search, export to file, clear.
5. **About & Updates** — app version, latest version, update status, check-now / install buttons.

**Notifications & errors:**

- shadcn **sonner** toaster, single `<Toaster/>` in `AppShell`.
- Central `reportError(code, context)` in `src/lib/errors.ts`:
  - standardized codes `HK-XXXX` grouped by subsystem (1xxx vault/fs, 2xxx index, 3xxx AI, 4xxx voice, 5xxx updater, 9xxx unexpected),
  - each code maps to a user-facing message + severity + optional action (e.g. "Open Settings"),
  - emits toast + structured log entry.
- React `ErrorBoundary` + `window.onunhandledrejection` feed the same funnel.

**Logging:**

- `src/lib/logger.ts`: `log.info/warn/error(scope, message, data)` → console (dev) + Rust `append_log`.
- Rust writes JSONL to app-data `logs/hikki.log` with size-based rotation (keep last N files).
- Logs section in Settings reads via `read_logs` with filters.

## 9. Auto-update

- `tauri-plugin-updater` + `tauri-plugin-process`; artifacts + signatures published to **GitHub Releases** by `.github/workflows/release.yml` (tag-triggered: build, sign with `TAURI_SIGNING_PRIVATE_KEY` secret, create release with `latest.json`).
- CI workflow (`ci.yml`): lint, typecheck, vitest, cargo test, Playwright on PRs/pushes.
- In-app: check on launch (and manual check in Settings); when an update is available, an **upgrade pill in the top-right header** opens a dialog (release notes, install & restart).
- Settings → About shows current version, latest version, and status (up-to-date / available / downloading / error).

## 10. Dashboard (`/`)

Data from SQLite (`dashboard_stats`, `activity`):

- Stat tiles: total documents, total words, current writing streak, docs edited this week.
- Area chart (chart.tsx/Recharts): words written per day, last 30 days.
- Calendar heatmap (calendar.tsx): active days, month view.
- Lists: recently edited, favorites.
- Greeting header with date; quick "New document" action.

## 11. Notion-style extras

- **Covers**: bundled gradient presets or user image (asset import); shown in page header + reposition control.
- **Icons**: emoji picker on page header + sidebar tree.
- **Templates**: bundled templates (Meeting Notes, Journal, Todo, Project Brief) — insertable via slash menu or new-doc menu.
- **Favorites**: star toggle; sidebar section; dashboard list.
- **Backlinks**: right panel listing linking documents with snippet; powered by `links` table.
- **Quick search**: `⌘K` palette with FTS results + recents.
- **Keyboard shortcuts**: `⌘K` palette, `⌘,` settings, `⌘N` new doc, `⌘J` writing tools, `⌘⇧F` search; help sheet listing all.
- **Breadcrumbs**: derived from `parentId` chain in the editor header.
- **Version history UI**: per-document panel listing snapshots (relative times), read-only preview, and Restore — backed by the §3 snapshot store.

## 12. Testing strategy (TDD)

- **Vitest** (unit): `src/lib/**` (errors, logger, AI client with mocked fetch/SSE, IPC layer with `mockIPC` from `@tauri-apps/api/mocks`), Jotai atoms, pure helpers (tree building, link extraction on the TS side if any).
- **cargo test** (unit/integration): vault fs ops in tempdirs, document round-trip, index building, FTS queries, link extraction, watcher reconciliation.
- **Playwright** (e2e): runs against the Vite dev server in a browser with Tauri IPC mocked — WKWebView is not Playwright-driveable, so e2e validates the full web layer (navigation, editor interactions, Writing Tools UI, settings, palette) against mocked IPC; Rust behavior is covered by cargo tests. `data-testid` selectors.
- TDD workflow per feature: failing test → implement → green → refactor.

## 13. Implementation phases

1. **Foundation** — vault fs + SQLite index in Rust, IPC layer, router + `AppShell`, sidebar wired to real tree.
2. **Editor** — BlockNote integration, autosave, assets, page header (title/icon/cover), version-history snapshots (storage side), soft design-language pass (§15).
3. **AI Writing Tools** — provider client, popover UI, streaming preview, model selector.
4. **Settings + errors/toasts/logging** — dialog sections (incl. Appearance multi-theme presets), Keychain, error codes, log pipeline + viewer.
5. **Dashboard** — stats queries + charts + heatmap.
6. **Extras** — favorites, backlinks, templates, `⌘K` palette, shortcuts, trash, version-history UI.
7. **Voice input** — recorder UI + OpenAI STT (experimental flag).
8. **Updater + CI** — release workflow, updater wiring, upgrade pill.

`CLAUDE.md` and `README.md` are updated as each phase lands (commands, architecture, conventions). `IMG_6065.jpeg` deleted after the Writing Tools UI ships.

## 14. Design language

Raw shadcn defaults read generic; Hikki aims for a **soft, calm, Notion-like** feel. This binds all UI work from Phase 2 onward:

- **Color**: warm, low-contrast neutrals — background slightly warm off-white (dark mode: warm dark gray, never pure black), foreground a soft near-black, borders barely-there (`border-border/60`-level contrast), muted icon/chrome colors.
- **Shape**: `--radius` ≈ 0.625rem; popovers/menus with soft, diffuse shadows rather than hard borders.
- **Density & type**: generous whitespace in the editor column; smaller quiet chrome (13px sidebar rows); titles bold but never harsh.
- **Motion**: 150–200ms ease-out color/opacity transitions on hover/active; no abrupt state jumps.
- **Interaction**: hover states are subtle background tints (`bg-muted`-tinted), not outlines; destructive actions styled calmly until confirmed.
- Applied via shadcn token tuning in `src/assets/globals.css` (both modes) plus component-level polish; theme presets (§8 Appearance) build on the same token system.

## 14a. Design/library decisions from Phase-2 user review (2026-07-20)

Amendments locked after visually reviewing Phase 2 against Notion references:

- **Window chrome bug**: `tauri.conf.json` shipped the template's `"transparent": true`, never revisited. Combined with `titleBarStyle: "Overlay"`, macOS window transparency is a known source of drag-region hit-testing and traffic-light rendering glitches. Fix: `"transparent": false` — the app paints its own opaque background via CSS tokens anyway, so nothing is lost visually.
- **Theming pulled forward**: a minimal `next-themes` `ThemeProvider` (+ `NativeThemeBridge` syncing `getCurrentWindow().setTheme()`, per the exodus pattern already agreed in §8) lands now, ahead of Phase 4, specifically so dark mode is reachable and the editor's dark-mode correctness can actually be verified. The full Appearance panel (preset gallery, radius picker) stays in Phase 4 — this is just the provider + a lightweight toggle.
- **BlockNote re-skinning**: `@blocknote/shadcn`'s `BlockNoteView` accepts a `shadCNComponents` prop overriding its internal Button/Tooltip/Popover/DropdownMenu/etc. with our own `src/components/ui/*` instances, and a `theme="light"|"dark"` prop. Both are wired so BlockNote's toolbar, tooltips, and menus render as pixel-identical citizens of our own design system rather than BlockNote's bundled look-alikes. BlockNote's own `--bn-colors-*`/`--bn-border-radius*`/`--bn-shadow-*` CSS variables (scoped under `.bn-root`) are retargeted to reference our tokens for the parts `shadCNComponents` doesn't cover (editor background/text, code block chrome). `.bn-editor`'s built-in `padding-inline: 54px` is reset to 0 — our own page wrapper owns horizontal padding, avoiding the double-indent the built-in gutter caused.
- **Code block syntax highlighting**: BlockNote's `codeBlock` feature is highlight-capable but ships no highlighter by default (only `@shikijs/types`, not the `shiki` runtime). We add `shiki` and wire `codeBlock.createHighlighter`.
- **Emoji picker**: swapped from a hardcoded 30-emoji grid to **frimousse** — a headless, composable, shadcn-native emoji picker (search, categories, keyboard nav, virtualized) — matching our "always use the real component, never reinvent" rule from §1.
- **Table of contents**: **react-fluid-toc** (the user's own package) — headings are derived from `editor.document` (BlockNote doesn't render semantic `<h1-6>` tags, so we assign `id` attributes onto the rendered heading DOM nodes ourselves for anchor/scroll-spy targeting).
- **Comments**: BlockNote ships an **open-source** Comments/Threads system (`ThreadStore` abstract class, `CommentsExtension`, `AddCommentButton`) — distinct from the commercial-only AI package this project already excludes. We implement our own `VaultThreadStore` (satisfying `ThreadStore`'s `createThread`/`addComment`/`resolveThread`/etc.) persisting threads as a new field on `Doc`, saved through the existing autosave path — no new Rust IPC surface needed for v1. Single local user: `resolveUsers` returns a fixed local identity, no auth/roles.

## 14b. AI Writing Tools — Phase 3 kickoff decisions (2026-07-29)

Amendments locked during Phase 3 brainstorming, refining §6 now that the actual provider library has been evaluated directly (superseding §6's "modeled on `@earendil-works/pi-ai`" language — this phase uses the real package, not something inspired by it):

- **Provider library**: `@earendil-works/pi-ai` (real package, verified API — not hand-rolled). Gives a `Models` collection with one subpath-import factory per provider (`@earendil-works/pi-ai/providers/openai`, `/anthropic` — small bundles, code-split, no unused provider SDKs pulled in), a unified `stream()`/`complete()` returning typed events (`text_delta`, `done`, `error`, …, so no raw-SSE parsing is needed — §6's "SSE parsed in TS" is no longer necessary, pi-ai already does this), and its own live model catalog (context window, vision support, reasoning flag per model) — the model-selector dropdown queries this directly instead of Hikki hand-maintaining a `models.ts` list that would go stale.
- **API keys**: fetched via a new Rust `ai.rs` module (`get_api_key(provider)`/`set_api_key`/`delete_api_key`, backed by the `keyring` crate per §1's decision) before each request, passed to pi-ai as an explicit `{ apiKey }` request option — never persisted in JS state/localStorage, matching §6's original intent exactly. (Considered: implementing pi-ai's full `CredentialStore` interface instead — rejected as more machinery than this single-user, no-OAuth use case needs.)
- **CORS/networking**: pi-ai has no fetch-injection hook, so `@tauri-apps/plugin-http`'s fetch replaces the global `window.fetch` once at app startup — every library's HTTP calls, including pi-ai's internal SDK calls, transparently route through Tauri's native HTTP from then on, bypassing webview CORS restrictions without per-library wiring.
- **Testing**: pi-ai ships `fauxProvider()` — an in-memory provider with scripted, streaming-capable responses, purpose-built for tests — used both in unit tests (prompt-construction, client-wrapper logic) and registered in place of real providers for the dev/e2e build (mirroring how `MemoryBackend` already substitutes for real Tauri IPC in browser/dev mode), so Playwright can drive the real popover UI and real BlockNote apply-flow with deterministic output, no real API calls or costs in CI.
- **Phase-4 pull-forward scope, kept deliberately minimal** (same pattern as Phase 2 pulling forward a minimal `next-themes` provider ahead of the full Phase 4 Appearance panel, per §14a): only `ai.rs`'s Keychain commands, one small standalone API-key/default-model dialog (not the full 5-section Settings shell from §8), and plain `sonner` toasts for AI errors (not the full `HK-XXXX` code + structured-logger pipeline from §8). The full Settings dialog, Logs viewer, and error-code system remain Phase 4's own scope.
- **Document writes**: AI-generated content is applied exclusively through BlockNote's standard `editor.replaceBlocks`/`editor.insertBlocks` APIs, never raw `Doc.blocks` JSON mutation — these are the same collaboration-safe operations a future Yjs-backed document model would already require, so no rework is anticipated if/when real-time collaboration (currently out of scope per §16) is revisited. No other multiplayer-specific design work (concurrent-edit handling, selection-range invalidation, etc.) is in scope for this phase.

## 15. Future roadmap (post-v1 backlog, not scheduled)

Captured for later; explicitly **not** part of phases 1–8:

- **Database features** (Notion-style): table view, list view, board, forms; typed properties/fields on documents; views saved per page.
- **Template authoring & import**: create templates from existing pages; import/export template files (beyond the bundled templates in Phase 6).
- Cross-platform asset-URL portability pass (stored `hikki-asset://` URLs are platform-shaped).

## 16. Out of scope (v1)

- Real-time collaboration, sharing, cloud accounts.
- Mobile targets.
- Non-macOS polish (app must still build on other platforms, but window-chrome work targets macOS).
- BlockNote commercial AI package (explicitly excluded by spec).
