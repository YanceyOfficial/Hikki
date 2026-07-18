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
- **Rust** (`src-tauri/src/`): `vault.rs` (settings/layout), `document.rs` (fs CRUD, soft delete), `index.rs` (FTS5 search/reconcile), `commands.rs` (`*_impl` testable core + `#[tauri::command]` wrappers), `error.rs` (`HK-XXXX` codes, serialized as `{code, message}`).
- **Frontend backend layer:** components use only `backend` from `#lib/backend/index` — `TauriBackend` (IPC) in Tauri, `MemoryBackend` in plain browsers (dev + Playwright). Never call `invoke` outside `src/lib/backend/`.
- **State:** Jotai (`#lib/store`), doc tree built by pure `buildTree` (`#lib/tree`).
- **Routing:** `createHashRouter` — `/` dashboard, `/doc/:id` editor; `AppShell` owns the macOS titlebar (drag region + traffic-light inset via `useTrafficLightInset`).

## Conventions

- TDD: failing test first (Vitest / cargo test / Playwright), then implement.
- `data-testid` on every interactive element (kept in dev, will be stripped in prod builds).
- shadcn/ui first — install missing primitives with `pnpm dlx shadcn@latest add <name>`, never hand-roll.
- Import aliases: `#components/*`, `#lib/*`, `#lib/backend/*`, `#hooks/*`, `#pages/*` (package.json `imports`).
- IPC payloads are camelCase; Rust uses `serde(rename_all = "camelCase")`.
- Conventional commits; husky runs oxlint/oxfmt — never `--no-verify`.
