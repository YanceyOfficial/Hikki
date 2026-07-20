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
- **Editor:** BlockNote (`#components/editor`) inside `src/pages/document-page.tsx`; block changes flow through the same debounced `save_document` autosave as the title. jsdom can't render BlockNote — unit tests mock `#components/editor`; real editor behavior is covered by Playwright.
- **Frontend backend layer:** components use only `backend` from `#lib/backend/index` — `TauriBackend` (IPC) in Tauri, `MemoryBackend` in plain browsers (dev + Playwright). Never call `invoke` outside `src/lib/backend/`.
- **Sidebar:** document tree metadata served from SQLite `documents` table via `Index::list_metas`; frontend renders the tree view in the left sidebar, supports collapse/expand, delete via dropdown, and hierarchical nesting via `parentId` (drag-to-reorder arrives in a later phase).
- **State:** Jotai (`#lib/store`), doc tree built by pure `buildTree` (`#lib/tree`).
- **Routing:** `createHashRouter` — `/` dashboard, `/doc/:id` editor; `AppShell` owns the macOS titlebar (drag region + traffic-light inset via `useTrafficLightInset`).
- **Version history:** `history.rs` writes rolling snapshots to `documents/<uuid>/history/` on save (10-min coalescing, 50 kept); history UI arrives in Phase 6.

## Conventions

- TDD: failing test first (Vitest / cargo test / Playwright), then implement.
- `data-testid` on every interactive element (kept in dev, will be stripped in prod builds via `@rolldown/plugin-babel` with `react-remove-properties`; see `vite.config.ts`).
- shadcn/ui first — install missing primitives with `pnpm dlx shadcn@latest add <name>`, never hand-roll.
- Import aliases: `#components/*`, `#lib/*`, `#lib/backend/*`, `#hooks/*`, `#pages/*` (package.json `imports`).
- IPC payloads are camelCase; Rust uses `serde(rename_all = "camelCase")`.
- Conventional commits; husky runs oxlint/oxfmt — never `--no-verify`.
- Design language: soft Notion-like aesthetic per spec §14 — warm low-contrast tokens in `src/assets/globals.css`, `--radius: 0.625rem`, muted chrome, 150–200ms transitions. Match it in all new UI.
