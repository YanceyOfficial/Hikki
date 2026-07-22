# Hikki

Notion-like local-first note app. Tauri 2 + React 19 + BlockNote + shadcn/ui + Jotai; Rust owns all I/O.

## Commands

- `pnpm dev` — Vite dev server (browser mode uses in-memory backend)
- `pnpm tauri dev` — full desktop app
- `pnpm test` / `pnpm test:watch` — Vitest (jsdom)
- `cargo test --manifest-path src-tauri/Cargo.toml` — Rust tests
- `pnpm e2e` — Playwright against Vite dev server (MemoryBackend)
- `pnpm lint` / `pnpm fmt` — oxlint / oxfmt (also run by husky on commit)
- `pnpm exec tsc --noEmit` — typecheck

## Architecture

- **Storage (hybrid local-first):** vault dir (default `~/Hikki`) holds `documents/<uuid>/document.json` + `assets/`; source of truth, iCloud-syncable. Derived SQLite FTS5 index in app-data (`index.db`) — rebuildable, never synced. See `docs/superpowers/specs/2026-07-18-hikki-design.md`.
- **Rust** (`src-tauri/src/`): `vault.rs` (settings/layout), `document.rs` (fs CRUD, soft delete), `index.rs` (FTS5 search/reconcile), `asset.rs` (asset import + `hikki-asset://` URL resolution, traversal-checked), `fsx.rs` (atomic temp+rename writes), `history.rs` (snapshots), `commands.rs` (`*_impl` testable core + `#[tauri::command]` wrappers), `error.rs` (`HK-XXXX` codes, serialized as `{code, message}`).
- **Assets:** imported via `import_asset` command into `documents/<uuid>/assets/`, served by the custom `hikki-asset://` protocol (vault-scoped, UUID + single-component filename validation). Frontend builds URLs with `backend.assetUrl()` and `#lib/asset-url`.
- **Editor:** BlockNote (`#components/editor`) inside `src/pages/document-page.tsx`; block changes flow through the same debounced `save_document` autosave as the title. jsdom can't render BlockNote — unit tests mock `#components/editor`; real editor behavior is covered by Playwright. Re-skinned via the `shadCNComponents`/`theme` props (wired to our own `Button`/`Tooltip`/`Popover` and `next-themes`' `resolvedTheme`) plus a retargeted `--bn-colors-*` variable layer in the `.bn-root` block of `src/assets/globals.css` (`!important`-forced — `@blocknote/shadcn` ships an equal-specificity `.bn-root` rule that loads after ours); `.bn-editor{padding-inline:0; background-color:transparent}` lets our own wrapper own horizontal spacing, and `.bn-trailing-block{min-height:240px}` widens the click-to-continue-typing zone below the last block. Code blocks are shiki-highlighted (plain `shiki` package, ~26 languages, `min-light`/`min-dark` themes) with best-effort paste language detection (`#lib/guess-language`) and a copy-to-clipboard overlay (`src/components/code-block-copy-overlay.tsx`, a DOM-sibling of `BlockNoteView` — ProseMirror reverts DOM writes made directly inside its contentEditable tree). The custom `chooseVerticalPlacement` floating-ui middleware in `editor.tsx` fixes the "/" suggestion menu compressing instead of flipping upward near the viewport bottom (a feedback loop between `size()` and `autoPlacement`).
- **Comments:** `VaultThreadStore` (`#lib/vault-thread-store`) implements BlockNote's open-source `ThreadStore` abstract class, backed by `Doc.threads: unknown` (mirrors the opaque `Doc.blocks` pattern; Rust never interprets it, see `src-tauri/src/document.rs`); wired into the editor via `CommentsExtension` in `#components/editor`. Rendered as a right-side rail: `src/components/comment-threads-sidebar.tsx` mounts inside `<BlockNoteView>` (to read `BlockNoteContext`/`ComponentsContext`) but portals its painted output via `ReactDOM.createPortal` into the shared `page-rail` container that `src/pages/document-page.tsx` renders alongside the reading column (visible at `2xl` and up).
- **Table of contents:** `src/components/table-of-contents.tsx` (`react-fluid-toc`) derives heading items from `editor.document` rather than DOM-scanning (BlockNote headings are plain `div`s, not semantic `<h1>`-`<h6>`), stacked in the same `page-rail` container above the comments rail. `src/components/heading-anchor-overlay.tsx` renders real anchor elements (same DOM-sibling-overlay pattern as the code-block copy button) since setting `.id` directly on BlockNote's heading DOM gets reverted by ProseMirror's own DOM-integrity observer.
- **Theming:** `next-themes` (`#components/theme-provider`, `attribute="class"`, `storageKey="hikki-theme"`) drives light/dark across the app, including native window-chrome sync via `getCurrentWindow().setTheme()`; toggled from `title-bar.tsx`'s theme button. Base UI-backed `Tooltip`/`Popover`/`DropdownMenu` primitives (`src/components/ui/{tooltip,popover,dropdown-menu}.tsx`, built on `@base-ui/react`) are softened to match; `TooltipTrigger`/`PopoverTrigger` bridge a Radix-style `asChild` prop onto Base UI's own `render` prop, since BlockNote's bundled toolbar/badge/link buttons pass `asChild` and would otherwise render as nested `<button>`s.
- **Emoji picker:** `frimousse`'s `EmojiPicker` (`src/components/page-header.tsx`), self-hosted — `scripts/copy-emojibase-data.mjs` copies `emojibase-data`'s `en/{data,messages}.json` into `public/emojibase-data` ahead of `dev`/`build` so `emojibaseUrl="/emojibase-data"` never depends on frimousse's CDN default.
- **Frontend backend layer:** components use only `backend` from `#lib/backend/index` — `TauriBackend` (IPC) in Tauri, `MemoryBackend` in plain browsers (dev + Playwright). Never call `invoke` outside `src/lib/backend/`.
- **Sidebar:** document tree metadata served from SQLite `documents` table via `Index::list_metas`; frontend renders the tree view in the left sidebar, supports collapse/expand, delete via dropdown, and hierarchical nesting via `parentId` (drag-to-reorder arrives in a later phase).
- **State:** Jotai (`#lib/store`), doc tree built by pure `buildTree` (`#lib/tree`).
- **Routing:** `createHashRouter` — `/` dashboard, `/doc/:id` editor; `AppShell` owns the macOS titlebar (drag region + traffic-light inset via `useTrafficLightInset`). `src-tauri/tauri.conf.json` sets `transparent: false`/`dragDropEnabled: false` — a transparent window conflicted with the titlebar drag region.
- **Page header:** `src/components/page-header.tsx` — full-width cover image (container-query technique, `w-[100cqw]`/`@container`) and a last-updated timestamp (`date-fns`' `formatDistanceToNow`).
- **Version history:** `history.rs` writes rolling snapshots to `documents/<uuid>/history/` on save (10-min coalescing, 50 kept); history UI arrives in Phase 6.

## Conventions

- TDD: failing test first (Vitest / cargo test / Playwright), then implement.
- `data-testid` on every interactive element (kept in dev, will be stripped in prod builds via `@rolldown/plugin-babel` with `react-remove-properties`; see `vite.config.ts`).
- shadcn/ui first — install missing primitives with `pnpm dlx shadcn@latest add <name>`, never hand-roll.
- Import aliases: `#components/*`, `#lib/*`, `#lib/backend/*`, `#hooks/*`, `#pages/*` (package.json `imports`).
- IPC payloads are camelCase; Rust uses `serde(rename_all = "camelCase")`.
- Conventional commits; husky runs oxlint/oxfmt — never `--no-verify`.
- Design language: soft Notion-like aesthetic per spec §14 — warm low-contrast tokens in `src/assets/globals.css`, `--radius: 0.625rem`, muted chrome, 150–200ms transitions. Match it in all new UI.
