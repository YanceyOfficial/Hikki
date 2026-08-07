# Phase 4: Settings, Errors, Logging — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the real 4-section Settings dialog (General, Appearance, AI, Logs — About & Updates is a 5th, static-only section), a central `reportError`/`HK-XXXX` error+toast funnel, and a Rust-backed JSONL logging pipeline with a Logs viewer — superseding the Phase 2 theme-toggle and Phase 3 `AiSettingsDialog` placeholders.

**Architecture:** A new `SettingsDialog` (sidebar-nav-inside-a-wide-Dialog) replaces the unused shadcn scaffold at `src/components/settings-dialog.tsx`. Each of its 4 real sections is its own small component under `src/components/settings/`. A new Rust `logging.rs` module (JSONL append + size-based rotation, mirroring `history.rs`'s rotation-by-cap pattern) backs a `Logs` section; `src/lib/errors.ts`'s `reportError(code, context)` is the single place that maps an `HK-XXXX` code to a user-facing toast and a structured log entry, and both an `ErrorBoundary` and `window.onunhandledrejection` feed into it, alongside three existing Phase 3 call sites retrofitted onto it.

**Tech Stack:** React 19, Jotai, Base UI (`Dialog`), sonner, Rust/Tauri 2, `@tauri-apps/plugin-dialog` (new).

## Global Constraints

- IPC payloads are camelCase; Rust uses `serde(rename_all = "camelCase")` (existing project convention).
- `data-testid` on every interactive element.
- Never call `invoke` outside `src/lib/backend/` for **this app's own custom commands**. Official Tauri plugin JS SDKs (like `@tauri-apps/plugin-dialog`'s `open`/`save`) are called directly at their use site instead — same precedent as `@tauri-apps/plugin-http`'s `fetch` in Phase 3, which was never funneled through `Backend`.
- Every new optional Rust struct field needs `#[serde(default)]` for backward compatibility (established rule from a real incident in Phase 2/3).
- Rust `*_impl` testable-core functions, thin `#[tauri::command]` wrappers, following `ai.rs`'s existing split.
- HK-XXXX codes grouped by subsystem per spec §8: 1xxx vault/fs, 2xxx index, 3xxx AI, 4xxx voice (not used this phase), 5xxx updater (not used this phase), 9xxx unexpected. This phase adds a new 6xxx group for Settings/Logs (not itself vault/fs, index, or AI) — noted explicitly since spec §8 doesn't reserve a number for it.
- TDD: failing test first, then implement.
- No new HTTP/network dependencies needed this phase.
- The user has separate, unrelated, uncommitted work sitting in the working tree throughout this phase (modified `package.json`/`pnpm-lock.yaml`/`src/assets/globals.css`, untracked `src/components/app-sidebar.tsx` and `src/components/ui/{combobox,input-group,table,textarea}.tsx`). Every task's commit must stage only the files that task itself touches — never a blanket `git add -A`/`.` — and must verify via `git status`/`git diff` before and after that this unrelated state is untouched.

---

### Task 1: Rust logging module

**Files:**

- Create: `src-tauri/src/logging.rs`
- Modify: `src-tauri/src/commands.rs` (register `#[tauri::command]` wrappers), `src-tauri/src/lib.rs` (register the `logging` module + new commands in the invoke handler)

**Interfaces:**

- Produces: `logging::append_log_impl(app_data_dir: &Path, entry: LogEntry) -> Result<()>`, `logging::read_logs_impl(app_data_dir: &Path, filter: LogFilter) -> Result<Vec<LogEntry>>`, `logging::clear_logs_impl(app_data_dir: &Path) -> Result<()>`, each wrapped as `#[tauri::command]` `append_log`/`read_logs`/`clear_logs`. `LogEntry { level: String, scope: String, message: String, data: Option<serde_json::Value>, timestamp: String }` (camelCase via `serde(rename_all = "camelCase")`, `timestamp` an RFC3339 string). `LogFilter { level: Option<String>, query: Option<String> }`.

- [ ] **Step 1: Write the failing tests**

Create `src-tauri/src/logging.rs`:

```rust
use std::fs;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::error::Result;

pub const MAX_LOG_BYTES: u64 = 5 * 1024 * 1024;
pub const MAX_ROTATED_FILES: usize = 5;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct LogEntry {
    pub level: String,
    pub scope: String,
    pub message: String,
    #[serde(default)]
    pub data: Option<serde_json::Value>,
    pub timestamp: String,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LogFilter {
    #[serde(default)]
    pub level: Option<String>,
    #[serde(default)]
    pub query: Option<String>,
}

fn log_dir(app_data_dir: &Path) -> PathBuf {
    app_data_dir.join("logs")
}

fn log_path(app_data_dir: &Path) -> PathBuf {
    log_dir(app_data_dir).join("hikki.log")
}

fn rotated_path(app_data_dir: &Path, n: usize) -> PathBuf {
    log_dir(app_data_dir).join(format!("hikki.log.{n}"))
}

fn rotate_if_needed(app_data_dir: &Path) -> Result<()> {
    let current = log_path(app_data_dir);
    let size = fs::metadata(&current).map(|m| m.len()).unwrap_or(0);
    if size < MAX_LOG_BYTES {
        return Ok(());
    }
    // Shift hikki.log.(N-1) -> hikki.log.N, oldest beyond the cap is dropped.
    for n in (1..MAX_ROTATED_FILES).rev() {
        let from = rotated_path(app_data_dir, n);
        if from.exists() {
            fs::rename(&from, rotated_path(app_data_dir, n + 1))?;
        }
    }
    fs::rename(&current, rotated_path(app_data_dir, 1))?;
    Ok(())
}

pub fn append_log_impl(app_data_dir: &Path, entry: LogEntry) -> Result<()> {
    let dir = log_dir(app_data_dir);
    fs::create_dir_all(&dir)?;
    rotate_if_needed(app_data_dir)?;
    let mut line = serde_json::to_string(&entry)?;
    line.push('\n');
    use std::io::Write;
    let mut file = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(log_path(app_data_dir))?;
    file.write_all(line.as_bytes())?;
    Ok(())
}

pub fn read_logs_impl(app_data_dir: &Path, filter: LogFilter) -> Result<Vec<LogEntry>> {
    let path = log_path(app_data_dir);
    if !path.exists() {
        return Ok(vec![]);
    }
    let content = fs::read_to_string(&path)?;
    let query = filter.query.as_ref().map(|q| q.to_lowercase());
    let mut entries: Vec<LogEntry> = content
        .lines()
        .filter_map(|line| serde_json::from_str::<LogEntry>(line).ok())
        .filter(|e| filter.level.as_deref().is_none_or(|lvl| e.level == lvl))
        .filter(|e| {
            query
                .as_ref()
                .is_none_or(|q| e.message.to_lowercase().contains(q))
        })
        .collect();
    // Newest first - matches how the Logs UI wants to display them.
    entries.reverse();
    Ok(entries)
}

pub fn clear_logs_impl(app_data_dir: &Path) -> Result<()> {
    let path = log_path(app_data_dir);
    if path.exists() {
        fs::remove_file(&path)?;
    }
    for n in 1..=MAX_ROTATED_FILES {
        let rotated = rotated_path(app_data_dir, n);
        if rotated.exists() {
            fs::remove_file(&rotated)?;
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(level: &str, message: &str) -> LogEntry {
        LogEntry {
            level: level.to_string(),
            scope: "test".to_string(),
            message: message.to_string(),
            data: None,
            timestamp: "2026-08-04T00:00:00Z".to_string(),
        }
    }

    #[test]
    fn append_then_read_round_trips() {
        let dir = tempfile::tempdir().unwrap();
        append_log_impl(dir.path(), entry("info", "hello")).unwrap();
        append_log_impl(dir.path(), entry("error", "boom")).unwrap();
        let logs = read_logs_impl(dir.path(), LogFilter::default()).unwrap();
        assert_eq!(logs.len(), 2);
        // Newest first.
        assert_eq!(logs[0].message, "boom");
        assert_eq!(logs[1].message, "hello");
    }

    #[test]
    fn read_logs_filters_by_level() {
        let dir = tempfile::tempdir().unwrap();
        append_log_impl(dir.path(), entry("info", "one")).unwrap();
        append_log_impl(dir.path(), entry("error", "two")).unwrap();
        let filter = LogFilter { level: Some("error".to_string()), query: None };
        let logs = read_logs_impl(dir.path(), filter).unwrap();
        assert_eq!(logs.len(), 1);
        assert_eq!(logs[0].message, "two");
    }

    #[test]
    fn read_logs_filters_by_text_query_case_insensitively() {
        let dir = tempfile::tempdir().unwrap();
        append_log_impl(dir.path(), entry("info", "Vault reindexed")).unwrap();
        append_log_impl(dir.path(), entry("info", "AI request failed")).unwrap();
        let filter = LogFilter { level: None, query: Some("vault".to_string()) };
        let logs = read_logs_impl(dir.path(), filter).unwrap();
        assert_eq!(logs.len(), 1);
        assert_eq!(logs[0].message, "Vault reindexed");
    }

    #[test]
    fn read_logs_on_missing_file_is_empty_not_an_error() {
        let dir = tempfile::tempdir().unwrap();
        let logs = read_logs_impl(dir.path(), LogFilter::default()).unwrap();
        assert_eq!(logs.len(), 0);
    }

    #[test]
    fn clear_logs_removes_current_and_rotated_files() {
        let dir = tempfile::tempdir().unwrap();
        append_log_impl(dir.path(), entry("info", "one")).unwrap();
        fs::write(rotated_path(dir.path(), 1), "old\n").unwrap();
        clear_logs_impl(dir.path()).unwrap();
        assert!(!log_path(dir.path()).exists());
        assert!(!rotated_path(dir.path(), 1).exists());
        // Still readable (empty), not broken.
        assert_eq!(read_logs_impl(dir.path(), LogFilter::default()).unwrap().len(), 0);
    }

    #[test]
    fn rotate_if_needed_shifts_files_once_the_current_log_exceeds_the_cap() {
        let dir = tempfile::tempdir().unwrap();
        fs::create_dir_all(log_dir(dir.path())).unwrap();
        // Write a file already past MAX_LOG_BYTES so the next append rotates first.
        fs::write(log_path(dir.path()), vec![b'a'; (MAX_LOG_BYTES + 1) as usize]).unwrap();
        append_log_impl(dir.path(), entry("info", "fresh")).unwrap();
        assert!(rotated_path(dir.path(), 1).exists());
        let logs = read_logs_impl(dir.path(), LogFilter::default()).unwrap();
        // The rotated-away giant file isn't valid JSONL, so it contributes nothing;
        // only the fresh entry in the new current log is readable.
        assert_eq!(logs.len(), 1);
        assert_eq!(logs[0].message, "fresh");
    }
}
```

Note: `Option::is_none_or` requires Rust 1.82+ (stable well before this project's toolchain, matching the rest of the codebase's use of recent stdlib APIs) — if `cargo build` reports it's unavailable, replace both `is_none_or` calls with the equivalent `.map_or(true, |x| ...)` form instead; don't guess, check the actual compiler error if one appears.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cargo test --manifest-path src-tauri/Cargo.toml logging::`
Expected: FAIL — the module isn't registered in `lib.rs` yet (compile error).

- [ ] **Step 3: Register the module**

In `src-tauri/src/lib.rs`, add `mod logging;` near the other `mod` declarations.

Run: `cargo test --manifest-path src-tauri/Cargo.toml logging::`
Expected: PASS (6 tests).

- [ ] **Step 4: Add the IPC command wrappers**

In `src-tauri/src/commands.rs`:

```rust
#[tauri::command]
pub fn append_log(state: State<AppState>, entry: crate::logging::LogEntry) -> Result<()> {
    crate::logging::append_log_impl(&state.app_data_dir, entry)
}

#[tauri::command]
pub fn read_logs(
    state: State<AppState>,
    filter: crate::logging::LogFilter,
) -> Result<Vec<crate::logging::LogEntry>> {
    crate::logging::read_logs_impl(&state.app_data_dir, filter)
}

#[tauri::command]
pub fn clear_logs(state: State<AppState>) -> Result<()> {
    crate::logging::clear_logs_impl(&state.app_data_dir)
}
```

Find `lib.rs`'s `tauri::generate_handler![...]` macro invocation and add `append_log, read_logs, clear_logs` to that list — read the exact current formatting first rather than guessing.

- [ ] **Step 5: Run the full Rust suite**

Run: `cargo test --manifest-path src-tauri/Cargo.toml`
Expected: all pass (existing tests + the new 6 `logging::` tests), no warnings about unused fields.

- [ ] **Step 6: Commit**

```bash
git add src-tauri/src/logging.rs src-tauri/src/commands.rs src-tauri/src/lib.rs
git commit -m "feat(rust): JSONL logging module with size-based rotation

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: `@tauri-apps/plugin-dialog` wiring

**Depends on:** none (independent of Task 1).

**Files:**

- Modify: `src-tauri/Cargo.toml`, `src-tauri/src/lib.rs`, `src-tauri/capabilities/default.json`, `package.json`

**Interfaces:**

- Produces: native folder-picker and save-file dialogs available to the frontend via `@tauri-apps/plugin-dialog`'s `open`/`save` functions, called directly from component code (never through `Backend` — same precedent as `@tauri-apps/plugin-http`'s `fetch` in Phase 3).

- [ ] **Step 1: Add the Rust plugin dependency and register it**

In `src-tauri/Cargo.toml`, add under `[dependencies]`:

```toml
tauri-plugin-dialog = "2"
```

In `src-tauri/src/lib.rs`, find the existing `.plugin(tauri_plugin_http::init())` call in the `tauri::Builder` chain and add a sibling line directly after it:

```rust
        .plugin(tauri_plugin_dialog::init())
```

Run `cargo build --manifest-path src-tauri/Cargo.toml` to confirm it compiles.

- [ ] **Step 2: Add the dialog permission to the app's capability**

Read `src-tauri/capabilities/default.json` first (it currently has an object-form `http:default` entry with an `allow` scope, plus `core:default`/`opener:default`). Add `"dialog:default"` as a new plain-string entry to the `"permissions"` array. After building once (Step 1 already did this), check the generated `src-tauri/gen/schemas/acl-manifests.json` for a `"dialog"` key — confirm `"dialog:default"` is the real identifier and that it doesn't need its own scope (unlike `http:default`, file-system dialogs are typically ungated by origin scope since they're user-driven native pickers, not automatic requests — verify this against the actual generated schema doc string rather than assuming, since `http:default`'s own doc string held a real surprise in Phase 3).

- [ ] **Step 3: Add the JS dependency**

```bash
pnpm add @tauri-apps/plugin-dialog
```

- [ ] **Step 4: Verify the real API before Task 8/11 need it**

Read the installed package's type declarations (`node_modules/@tauri-apps/plugin-dialog` or its pnpm-nested path) for `open`/`save`'s exact signatures. Confirm (don't assume) whether `open({ directory: true })` returns `string | string[] | null` (v2's API allows `multiple` to change the return shape) and what `save`'s options/return type actually are. Note your findings in the report — Task 8 (General section's folder picker) and Task 11 (Logs section's export) both need this confirmed, not guessed.

- [ ] **Step 5: Run the full frontend check set**

Run: `pnpm test && pnpm exec tsc --noEmit`
Expected: all green (this task adds no new frontend logic yet, just the dependency + verification).

- [ ] **Step 6: Commit**

```bash
git add src-tauri/Cargo.toml src-tauri/Cargo.lock src-tauri/src/lib.rs src-tauri/capabilities/default.json package.json pnpm-lock.yaml
git commit -m "feat: wire up tauri-plugin-dialog for native folder/file pickers

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Extend `Backend` with vault-path change + logging IPC

**Depends on:** Task 1 (`append_log`/`read_logs`/`clear_logs` commands must exist).

**Files:**

- Modify: `src/lib/types.ts`, `src/lib/backend/backend.ts`, `src/lib/backend/tauri-backend.ts`, `src/lib/backend/memory-backend.ts`
- Test: `src/lib/backend/memory-backend.test.ts`

**Interfaces:**

- Consumes: Rust commands `set_vault_path(path: string): VaultInfo` (already exists, unused by the frontend today), `append_log`/`read_logs`/`clear_logs` (Task 1).
- Produces: `Backend.setVaultPath(path: string): Promise<VaultInfo>`, `Backend.appendLog(entry: LogEntry): Promise<void>`, `Backend.readLogs(filter: LogFilter): Promise<LogEntry[]>`, `Backend.clearLogs(): Promise<void>`. New types `LogLevel = 'info' | 'warn' | 'error'`, `LogEntry { level: LogLevel; scope: string; message: string; data?: unknown; timestamp: string }`, `LogFilter { level?: LogLevel; query?: string }`. Note `Backend.rebuildIndex(): Promise<number>` **already exists** in both implementations — nothing to add there.

- [ ] **Step 1: Add the new types**

In `src/lib/types.ts`, add:

```ts
export type LogLevel = 'info' | 'warn' | 'error'

export interface LogEntry {
  level: LogLevel
  scope: string
  message: string
  data?: unknown
  timestamp: string
}

export interface LogFilter {
  level?: LogLevel
  query?: string
}
```

- [ ] **Step 2: Write the failing test**

In `src/lib/backend/memory-backend.test.ts`, add:

```ts
test('setVaultPath returns updated vault info, and later getVaultInfo calls reflect it too', async () => {
  const backend = new MemoryBackend()
  const info = await backend.setVaultPath('/tmp/some-vault')
  expect(info.vaultPath).toBe('/tmp/some-vault')
  expect((await backend.getVaultInfo()).vaultPath).toBe('/tmp/some-vault')
})

test('appendLog/readLogs/clearLogs round-trip in memory', async () => {
  const backend = new MemoryBackend()
  await backend.appendLog({
    level: 'error',
    scope: 'test',
    message: 'boom',
    timestamp: new Date().toISOString()
  })
  const logs = await backend.readLogs({})
  expect(logs).toHaveLength(1)
  expect(logs[0].message).toBe('boom')

  const filtered = await backend.readLogs({ level: 'info' })
  expect(filtered).toHaveLength(0)

  await backend.clearLogs()
  expect(await backend.readLogs({})).toHaveLength(0)
})
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `pnpm test memory-backend`
Expected: FAIL — `setVaultPath`/`appendLog`/`readLogs`/`clearLogs` don't exist on `Backend`/`MemoryBackend` yet (TypeScript compile error surfaces as a Vitest transform failure).

- [ ] **Step 4: Extend the `Backend` interface**

In `src/lib/backend/backend.ts`, add to the `Backend` interface (alongside the existing `rebuildIndex(): Promise<number>`):

```ts
  setVaultPath(path: string): Promise<VaultInfo>
  appendLog(entry: LogEntry): Promise<void>
  readLogs(filter: LogFilter): Promise<LogEntry[]>
  clearLogs(): Promise<void>
```

Add `LogEntry`, `LogFilter` to the existing `import type { ... } from '#lib/types'` block at the top of the file.

- [ ] **Step 5: Implement in `TauriBackend`**

In `src/lib/backend/tauri-backend.ts`, add (alongside the existing `rebuildIndex()` method), and add `LogEntry`/`LogFilter` to its own `import type` block:

```ts
  setVaultPath(path: string) {
    return invoke<VaultInfo>('set_vault_path', { path })
  }
  appendLog(entry: LogEntry) {
    return invoke<void>('append_log', { entry })
  }
  readLogs(filter: LogFilter) {
    return invoke<LogEntry[]>('read_logs', { filter })
  }
  clearLogs() {
    return invoke<void>('clear_logs')
  }
```

- [ ] **Step 6: Implement in `MemoryBackend`**

In `src/lib/backend/memory-backend.ts`, add two private fields alongside the existing ones (`private vaultPath = '(in-memory)'`, `private logs: LogEntry[] = []`), add `LogEntry`/`LogFilter` to its `import type` block, and add:

```ts
  async setVaultPath(path: string): Promise<VaultInfo> {
    this.vaultPath = path
    return { vaultPath: this.vaultPath, documentCount: this.docs.size }
  }

  async appendLog(entry: LogEntry): Promise<void> {
    this.logs.push(entry)
  }

  async readLogs(filter: LogFilter): Promise<LogEntry[]> {
    return this.logs
      .filter((e) => !filter.level || e.level === filter.level)
      .filter(
        (e) =>
          !filter.query ||
          e.message.toLowerCase().includes(filter.query.toLowerCase())
      )
      .slice()
      .reverse()
  }

  async clearLogs(): Promise<void> {
    this.logs = []
  }
```

Also update the **existing** `getVaultInfo()` method (currently hardcodes `vaultPath: '(in-memory)'` — read it first to confirm) to return `this.vaultPath` instead of the literal string, so a `setVaultPath` call is actually reflected the next time anything calls `getVaultInfo()` again, not just in `setVaultPath`'s own return value:

```ts
  async getVaultInfo(): Promise<VaultInfo> {
    const alive = [...this.docs.values()].filter((d) => d.deletedAt === null)
    return { vaultPath: this.vaultPath, documentCount: alive.length }
  }
```

- [ ] **Step 7: Run the test to verify it passes**

Run: `pnpm test memory-backend && pnpm exec tsc --noEmit`
Expected: PASS, clean.

- [ ] **Step 8: Commit**

```bash
git add src/lib/types.ts src/lib/backend/backend.ts src/lib/backend/tauri-backend.ts src/lib/backend/memory-backend.ts src/lib/backend/memory-backend.test.ts
git commit -m "feat: extend Backend with vault-path change and logging IPC

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: `reportError`/`HK-XXXX` funnel + `logger.ts`

**Depends on:** Task 3 (`Backend.appendLog`).

**Files:**

- Create: `src/lib/errors.ts`, `src/lib/errors.test.ts`, `src/lib/logger.ts`, `src/lib/logger.test.ts`
- Modify: `src/lib/store.ts`

**Interfaces:**

- Consumes: `backend.appendLog(entry: LogEntry): Promise<void>` (Task 3).
- Produces: `log.info(scope: string, message: string, data?: unknown): void`, `log.warn(...)`, `log.error(...)` (same signature) in `src/lib/logger.ts`. `reportError(code: HkErrorCode, context?: Record<string, unknown>): void` in `src/lib/errors.ts`, plus the exported `HkErrorCode` union type and `ERROR_DEFINITIONS` map (both consumed by Task 6's retrofit and later section tasks). `settingsDialogOpenAtom`/`settingsDialogSectionAtom` Jotai atoms in `src/lib/store.ts`.

- [ ] **Step 1: Add the Settings-dialog atoms**

In `src/lib/store.ts`, add (this is needed now because `reportError`'s "Open Settings" action sets these atoms directly, without needing React context — the same reason `docMetasAtom`/`refreshDocsAtom` already live here):

```ts
export type SettingsSection = 'general' | 'appearance' | 'ai' | 'logs' | 'about'

export const settingsDialogOpenAtom = atom(false)
export const settingsDialogSectionAtom = atom<SettingsSection>('general')

export const openSettingsAtom = atom(
  null,
  (_get, set, section: SettingsSection = 'general') => {
    set(settingsDialogSectionAtom, section)
    set(settingsDialogOpenAtom, true)
  }
)
```

- [ ] **Step 2: Write the failing test for `logger.ts`**

Create `src/lib/logger.test.ts`:

```ts
import { beforeEach, expect, test, vi } from 'vitest'

vi.mock('#lib/backend/index', () => ({
  backend: { appendLog: vi.fn().mockResolvedValue(undefined) }
}))

import { log } from '#lib/logger'
import { backend } from '#lib/backend/index'

beforeEach(() => {
  vi.mocked(backend.appendLog).mockClear()
})

test('log.info calls backend.appendLog with level "info" and the given scope/message/data', () => {
  log.info('vault', 'reindexed', { count: 3 })
  expect(backend.appendLog).toHaveBeenCalledWith(
    expect.objectContaining({
      level: 'info',
      scope: 'vault',
      message: 'reindexed',
      data: { count: 3 }
    })
  )
})

test('log.warn and log.error use their own levels', () => {
  log.warn('ai', 'slow response')
  log.error('index', 'rebuild failed')
  expect(backend.appendLog).toHaveBeenNthCalledWith(
    1,
    expect.objectContaining({
      level: 'warn',
      scope: 'ai',
      message: 'slow response'
    })
  )
  expect(backend.appendLog).toHaveBeenNthCalledWith(
    2,
    expect.objectContaining({
      level: 'error',
      scope: 'index',
      message: 'rebuild failed'
    })
  )
})

test('every log entry carries an ISO timestamp', () => {
  log.info('test', 'x')
  const call = vi.mocked(backend.appendLog).mock.calls[0][0]
  expect(() => new Date(call.timestamp).toISOString()).not.toThrow()
  expect(new Date(call.timestamp).toISOString()).toBe(call.timestamp)
})
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `pnpm test logger`
Expected: FAIL — `#lib/logger` doesn't exist.

- [ ] **Step 4: Implement `logger.ts`**

Create `src/lib/logger.ts`:

```ts
import { backend } from '#lib/backend/index'
import type { LogLevel } from '#lib/types'

function write(
  level: LogLevel,
  scope: string,
  message: string,
  data?: unknown
) {
  // Fire-and-forget: a logging failure must never block the caller's own
  // control flow, and there's nowhere useful to surface it (it would just
  // recurse back into logging). Swallow deliberately.
  void backend
    .appendLog({
      level,
      scope,
      message,
      data,
      timestamp: new Date().toISOString()
    })
    .catch(() => {})
  if (import.meta.env.DEV) {
    console[level === 'warn' ? 'warn' : level === 'error' ? 'error' : 'log'](
      `[${scope}] ${message}`,
      data ?? ''
    )
  }
}

export const log = {
  info: (scope: string, message: string, data?: unknown) =>
    write('info', scope, message, data),
  warn: (scope: string, message: string, data?: unknown) =>
    write('warn', scope, message, data),
  error: (scope: string, message: string, data?: unknown) =>
    write('error', scope, message, data)
}
```

Verify `import.meta.env.DEV` is the correct Vite convention this codebase already uses elsewhere (grep for `import.meta.env` in `src/` first) rather than assuming — adjust if the project uses a different dev-detection mechanism.

- [ ] **Step 5: Run the test to verify it passes**

Run: `pnpm test logger && pnpm exec tsc --noEmit`
Expected: PASS, clean.

- [ ] **Step 6: Write the failing test for `errors.ts`**

Create `src/lib/errors.test.ts`:

```ts
import { beforeEach, expect, test, vi } from 'vitest'

vi.mock('#lib/backend/index', () => ({
  backend: { appendLog: vi.fn().mockResolvedValue(undefined) }
}))
vi.mock('sonner', () => ({
  toast: { error: vi.fn(), warning: vi.fn(), info: vi.fn() }
}))

import { reportError } from '#lib/errors'
import { backend } from '#lib/backend/index'
import { toast } from 'sonner'

beforeEach(() => {
  vi.mocked(backend.appendLog).mockClear()
  vi.mocked(toast.error).mockClear()
})

test('reportError shows a toast with the mapped message for a known code', () => {
  reportError('HK-1003')
  expect(toast.error).toHaveBeenCalledWith(
    expect.stringContaining('not found'),
    expect.anything()
  )
})

test('reportError logs a structured entry including the code and context', () => {
  reportError('HK-3001', { provider: 'openai' })
  expect(backend.appendLog).toHaveBeenCalledWith(
    expect.objectContaining({
      level: 'error',
      data: expect.objectContaining({ code: 'HK-3001', provider: 'openai' })
    })
  )
})

test('reportError falls back to a generic message for an unmapped code without throwing', () => {
  // @ts-expect-error - deliberately testing the runtime fallback for a code
  // outside the known union, since callers could still construct one
  // dynamically from an IPC error payload.
  expect(() => reportError('HK-9999')).not.toThrow()
  expect(toast.error).toHaveBeenCalled()
})
```

- [ ] **Step 7: Run the test to verify it fails**

Run: `pnpm test errors`
Expected: FAIL — `#lib/errors` doesn't exist.

- [ ] **Step 8: Implement `errors.ts`**

Create `src/lib/errors.ts`:

```ts
import { toast } from 'sonner'

import { log } from '#lib/logger'
import { openSettingsAtom } from '#lib/store'
import { getDefaultStore } from 'jotai'

export type HkErrorCode =
  | 'HK-1001'
  | 'HK-1002'
  | 'HK-1003'
  | 'HK-1004'
  | 'HK-1005'
  | 'HK-1006'
  | 'HK-1007'
  | 'HK-2001'
  | 'HK-3001'
  | 'HK-3002'
  | 'HK-3003'
  | 'HK-3004'
  | 'HK-3005'
  | 'HK-6001'
  | 'HK-6002'
  | 'HK-9001'

type ErrorSeverity = 'info' | 'warning' | 'error'

interface ErrorDefinition {
  message: string
  severity: ErrorSeverity
  /** When present, the toast gets an action button opening Settings to this section. */
  openSettings?: 'general' | 'appearance' | 'ai' | 'logs' | 'about'
}

const ERROR_DEFINITIONS: Record<HkErrorCode, ErrorDefinition> = {
  'HK-1001': { message: 'A file system error occurred.', severity: 'error' },
  'HK-1002': {
    message: 'Saved data could not be read - it may be corrupted.',
    severity: 'error'
  },
  'HK-1003': { message: 'That document was not found.', severity: 'error' },
  'HK-1004': { message: 'The file could not be imported.', severity: 'error' },
  'HK-1005': {
    message: 'Could not switch to the selected vault folder.',
    severity: 'error',
    openSettings: 'general'
  },
  'HK-1006': {
    message:
      "This page's content could not be displayed - the file may be damaged.",
    severity: 'error'
  },
  'HK-1007': { message: 'Could not copy to the clipboard.', severity: 'error' },
  'HK-2001': {
    message: 'Search index error - try rebuilding the index.',
    severity: 'error',
    openSettings: 'general'
  },
  'HK-3001': {
    message: 'Could not access the Keychain for this API key.',
    severity: 'error',
    openSettings: 'ai'
  },
  'HK-3002': {
    message: 'Could not load your AI settings.',
    severity: 'error',
    openSettings: 'ai'
  },
  'HK-3003': {
    message: 'Could not save that API key.',
    severity: 'error',
    openSettings: 'ai'
  },
  'HK-3004': {
    message: 'Could not save your default AI provider/model.',
    severity: 'error',
    openSettings: 'ai'
  },
  'HK-3005': {
    message: 'The Writing Tools request failed.',
    severity: 'error'
  },
  'HK-6001': {
    message: 'Could not load the logs.',
    severity: 'error',
    openSettings: 'logs'
  },
  'HK-6002': {
    message: 'Could not export the logs.',
    severity: 'error',
    openSettings: 'logs'
  },
  'HK-9001': { message: 'Something unexpected went wrong.', severity: 'error' }
}

const FALLBACK: ErrorDefinition = {
  message: 'Something unexpected went wrong.',
  severity: 'error'
}

export function reportError(
  code: HkErrorCode,
  context?: Record<string, unknown>
) {
  const definition = ERROR_DEFINITIONS[code] ?? FALLBACK
  const toastFn =
    definition.severity === 'warning'
      ? toast.warning
      : definition.severity === 'info'
        ? toast.info
        : toast.error
  toastFn(definition.message, {
    description: code,
    action: definition.openSettings
      ? {
          label: 'Open Settings',
          onClick: () =>
            getDefaultStore().set(openSettingsAtom, definition.openSettings)
        }
      : undefined
  })
  log.error('error', definition.message, { code, ...context })
}
```

Verify `jotai`'s `getDefaultStore()` export is real and matches this project's installed version (`grep -n "getDefaultStore" node_modules/jotai/**/*.d.ts` or check the package's own docs) before finalizing — this app doesn't currently call jotai atoms from outside a component, so confirm this is the correct way to write to an atom from plain (non-React) code.

- [ ] **Step 9: Run the test to verify it passes**

Run: `pnpm test errors && pnpm exec tsc --noEmit`
Expected: PASS, clean.

- [ ] **Step 10: Run the full check set**

Run: `pnpm test && pnpm exec tsc --noEmit`
Expected: all green.

- [ ] **Step 11: Commit**

```bash
git add src/lib/store.ts src/lib/logger.ts src/lib/logger.test.ts src/lib/errors.ts src/lib/errors.test.ts
git commit -m "feat: central reportError/HK-XXXX funnel and logger

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: `ErrorBoundary` + `window.onunhandledrejection`

**Depends on:** Task 4 (`reportError`).

**Files:**

- Create: `src/components/error-boundary.tsx`, `src/components/error-boundary.test.tsx`
- Modify: `src/main.tsx`

**Interfaces:**

- Produces: `ErrorBoundary` (React class component, `{ children: ReactNode }`, catches render errors and calls `reportError('HK-9001', { message, componentStack })`, renders a minimal fallback UI instead of a blank crashed page).

Note: `src/components/editor-boundary.tsx`'s `EditorBoundary` **already exists** — a narrower boundary specific to malformed-document rendering failures, wrapping only the editor content, not the whole app. This task's `ErrorBoundary` is a different, broader component (wraps the entire router in `main.tsx`, the last-resort catch-all) — it does not replace `EditorBoundary`, both coexist (React error boundaries nest normally: `EditorBoundary`'s own catch stops a bad document from taking down the rest of the app; this task's `ErrorBoundary` is the outer safety net for everything else). `EditorBoundary`'s own `console.error` call gets retrofitted onto `reportError` in Task 6, not this task.

- [ ] **Step 1: Write the failing test**

Create `src/components/error-boundary.test.tsx`:

```tsx
import { render, screen } from '@testing-library/react'
import { expect, test, vi } from 'vitest'

vi.mock('#lib/errors', () => ({ reportError: vi.fn() }))

import { ErrorBoundary } from '#components/error-boundary'
import { reportError } from '#lib/errors'

function Boom() {
  throw new Error('kaboom')
}

test('renders children normally when nothing throws', () => {
  render(
    <ErrorBoundary>
      <div data-testid="ok">fine</div>
    </ErrorBoundary>
  )
  expect(screen.getByTestId('ok')).toBeInTheDocument()
})

test('catches a render error, shows a fallback, and reports HK-9001', () => {
  const consoleSpy = vi.spyOn(console, 'error').mockImplementation(() => {})
  render(
    <ErrorBoundary>
      <Boom />
    </ErrorBoundary>
  )
  expect(screen.getByTestId('error-boundary-fallback')).toBeInTheDocument()
  expect(reportError).toHaveBeenCalledWith(
    'HK-9001',
    expect.objectContaining({ message: 'kaboom' })
  )
  consoleSpy.mockRestore()
})
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `pnpm test error-boundary`
Expected: FAIL — `#components/error-boundary` doesn't exist.

- [ ] **Step 3: Implement `ErrorBoundary`**

Create `src/components/error-boundary.tsx`:

```tsx
import { Component, type ErrorInfo, type ReactNode } from 'react'

import { reportError } from '#lib/errors'

interface ErrorBoundaryProps {
  children: ReactNode
}

interface ErrorBoundaryState {
  hasError: boolean
}

export class ErrorBoundary extends Component<
  ErrorBoundaryProps,
  ErrorBoundaryState
> {
  state: ErrorBoundaryState = { hasError: false }

  static getDerivedStateFromError(): ErrorBoundaryState {
    return { hasError: true }
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    reportError('HK-9001', {
      message: error.message,
      componentStack: info.componentStack
    })
  }

  render() {
    if (this.state.hasError) {
      return (
        <div
          data-testid="error-boundary-fallback"
          className="flex h-svh flex-col items-center justify-center gap-2 text-center"
        >
          <p className="text-muted-foreground">
            Something went wrong. Try reloading the app.
          </p>
        </div>
      )
    }
    return this.props.children
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `pnpm test error-boundary && pnpm exec tsc --noEmit`
Expected: PASS, clean.

- [ ] **Step 5: Wire `ErrorBoundary` and `window.onunhandledrejection` into `main.tsx`**

Read `src/main.tsx` in full first (it currently wraps `RouterProvider` in `ThemeProvider` inside `React.StrictMode`, and has the `isTauri()`-gated scoped-fetch replacement). Add the import, wrap `RouterProvider`:

```tsx
import { ErrorBoundary } from '#components/error-boundary'
import { reportError } from '#lib/errors'
```

```tsx
window.addEventListener('unhandledrejection', (event) => {
  reportError('HK-9001', {
    message:
      event.reason instanceof Error
        ? event.reason.message
        : String(event.reason)
  })
})
```

placed after the existing `isTauri()` fetch-scoping block, before `const router = ...`. Wrap the render:

```tsx
ReactDOM.createRoot(document.getElementById('root') as HTMLElement).render(
  <React.StrictMode>
    <ErrorBoundary>
      <ThemeProvider>
        <RouterProvider router={router} />
      </ThemeProvider>
    </ErrorBoundary>
  </React.StrictMode>
)
```

- [ ] **Step 6: Live-verify the unhandledrejection path**

With `pnpm dev` running, open the browser devtools console and run `Promise.reject(new Error('test'))` — confirm a toast appears and (check via `backend`'s in-memory state or a quick `console.log` patch, then remove it) that `appendLog` was called. Don't leave any temporary debug code behind.

- [ ] **Step 7: Run the full check set**

Run: `pnpm test && pnpm exec tsc --noEmit`
Expected: all green.

- [ ] **Step 8: Commit**

```bash
git add src/components/error-boundary.tsx src/components/error-boundary.test.tsx src/main.tsx
git commit -m "feat: ErrorBoundary and window.onunhandledrejection feed reportError

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Retrofit Phase 3's ad-hoc error handling onto `reportError`

**Depends on:** Task 4 (`reportError`).

**Files:**

- Modify: `src/components/writing-tools-popover.tsx`, `src/components/writing-tools-popover.test.tsx`, `src/components/ai-settings-dialog.tsx`, `src/components/ai-settings-dialog.test.tsx`, `src/components/page-header.tsx`, `src/components/page-header.test.tsx`, `src/components/editor-boundary.tsx`, `src/components/editor-boundary.test.tsx`, `src/hooks/use-copy-to-clipboard.ts`, `src/hooks/use-copy-to-clipboard.test.ts`

**Interfaces:**

- Consumes: `reportError(code: HkErrorCode, context?: Record<string, unknown>)` (Task 4).

- [ ] **Step 1: Retrofit `writing-tools-popover.tsx`**

Read the file's current `runAction` function in full first (it has two `toast.error('Writing Tools request failed', { description: ... })` call sites — one in the `event.type === 'error'` branch, one in the outer `catch`). Replace both `toast.error(...)` calls with:

```tsx
reportError('HK-3005', { message: event.message })
```

and, in the catch block:

```tsx
reportError('HK-3005', { message: message })
```

(keep the existing `message` variable computation as-is, just change what happens with it). Remove the now-unused `import { toast } from 'sonner'` if nothing else in the file uses `toast` directly, and add `import { reportError } from '#lib/errors'`.

- [ ] **Step 2: Update `writing-tools-popover.test.tsx`**

Read the existing test file's error-path tests first (the ones asserting `writing-tools-error` text content). Change the mock from `vi.mock('sonner', ...)`-adjacent patterns to mocking `#lib/errors` instead:

```tsx
vi.mock('#lib/errors', () => ({ reportError: vi.fn() }))
```

Update the assertions that previously checked `toast.error` was called to instead check `reportError` was called with `'HK-3005'` and a `message` context matching the expected error text. Keep the existing assertions on the inline `writing-tools-error` DOM element unchanged — that behavior didn't change, only how the toast/log side-effect is dispatched.

- [ ] **Step 3: Retrofit `ai-settings-dialog.tsx`**

Read the file's current `useEffect` (settings-load `.catch`), `saveKey`, and `saveDefaults` functions in full first. Replace:

- The settings-load `.catch`'s `toast.error('Failed to load AI settings', { description })` with `reportError('HK-3002', { message: description })`.
- `saveKey`'s failure-branch `toast.error(\`Failed to save ${provider} API key\`, { description })`with`reportError('HK-3003', { provider, message: description })`. Keep the success-branch `toast.success(...)`call as-is —`reportError`is only for failures, success toasts stay plain`sonner` calls (there's no HK-code for "this succeeded").
- `saveDefaults`'s failure-branch `toast.error('Failed to save default AI provider/model', { description })` with `reportError('HK-3004', { message: description })`.

Add `import { reportError } from '#lib/errors'`. Keep `import { toast } from 'sonner'` since `toast.success` is still used.

- [ ] **Step 4: Update `ai-settings-dialog.test.tsx`**

Read the existing failure-path tests first (the ones added when this file's error handling was first built, asserting specific `toast.error` calls with specific messages). Change them to assert `reportError` was called with the matching code (`'HK-3002'`/`'HK-3003'`/`'HK-3004'`) instead of asserting the old free-text `toast.error` message — mock `#lib/errors` the same way as Step 2. Keep the success-path test (`toast.success`) unchanged.

- [ ] **Step 5: Retrofit `page-header.tsx`**

Read the `uploadCover` function in full first (its `catch` block currently does `console.error('hikki: cover upload failed', error)`). Replace with:

```tsx
reportError('HK-1004', {
  message: error instanceof Error ? error.message : String(error)
})
```

Add `import { reportError } from '#lib/errors'`.

- [ ] **Step 6: Update `page-header.test.tsx`**

Read the existing `'failed cover upload is swallowed safely and does not patch'` test first (it currently spies on `console.error` and asserts it was called). Mock `#lib/errors` (same pattern as Step 2) and assert `reportError` was called with `'HK-1004'` instead of asserting on `console.error`. Remove the `console.error` spy/assertion — the failure is no longer silent-to-toast, it's fully funneled.

- [ ] **Step 7: Retrofit `editor-boundary.tsx`**

This is a **separate, pre-existing** component from the `ErrorBoundary` built in Task 5 (a narrower boundary specific to malformed-document rendering failures — see Task 5's note). Read `componentDidCatch(error: unknown) { console.error('hikki: editor failed to render', error) }` in full first. Replace with:

```tsx
reportError('HK-1006', {
  message: error instanceof Error ? error.message : String(error)
})
```

Add `import { reportError } from '#lib/errors'`.

- [ ] **Step 8: Update `editor-boundary.test.tsx`**

Read the existing test first (it spies on `console.error` via `vi.spyOn(console, 'error').mockImplementation(() => {})` to silence React's own noisy error logging during the intentional-throw test). Mock `#lib/errors` (same pattern as Step 2) and add an assertion that `reportError` was called with `'HK-1006'`. The `console.error` spy itself should stay — it's still needed to silence React's own internal error logging during the test, it just no longer needs an assertion on it (only on `reportError` now).

- [ ] **Step 9: Retrofit `use-copy-to-clipboard.ts`**

Read the `copy` function's `catch` block in full first — its own comment says _"No toast system exists yet (tracked separately) to surface this to the user - log it rather than fail with no trace at all"_ — this task is exactly that tracked follow-up. Replace:

```ts
console.error('hikki: failed to copy code block to clipboard', error)
```

with:

```ts
reportError('HK-1007', {
  message: error instanceof Error ? error.message : String(error)
})
```

and delete the now-stale comment above it (the gap it was tracking is closed). Add `import { reportError } from '#lib/errors'`.

- [ ] **Step 10: Update `use-copy-to-clipboard.test.ts`**

Read the existing failure-path test first (it spies on `console.error`). Mock `#lib/errors` (same pattern as Step 2) and assert `reportError` was called with `'HK-1007'` instead of asserting on `console.error`.

- [ ] **Step 11: Run the full check set**

Run: `pnpm test && pnpm exec tsc --noEmit`
Expected: all green.

- [ ] **Step 12: Live-verify with `pnpm dev`**

Trigger each retrofitted path manually (an AI request with no API key configured, a cover-image upload failure by uploading to a doc ID that doesn't exist, a code-block copy in a context where clipboard access fails if you can arrange one) and confirm a toast still appears with a sensible message in each case, and that the toast's copy is now the fixed `ERROR_DEFINITIONS` message rather than the old per-instance dynamic text (this is an intentional, expected change — the dynamic detail like the provider name now lives in the log's `context`, not the toast). The API-key-save and editor-render-failure paths are impractical to trigger live (would need to break Keychain access or hand-corrupt a vault file mid-session) — trust unit test coverage for those two.

- [ ] **Step 13: Commit**

```bash
git add src/components/writing-tools-popover.tsx src/components/writing-tools-popover.test.tsx src/components/ai-settings-dialog.tsx src/components/ai-settings-dialog.test.tsx src/components/page-header.tsx src/components/page-header.test.tsx src/components/editor-boundary.tsx src/components/editor-boundary.test.tsx src/hooks/use-copy-to-clipboard.ts src/hooks/use-copy-to-clipboard.test.ts
git commit -m "refactor: retrofit Phase 3's ad-hoc error handling onto reportError

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: `SettingsDialog` shell + entry point + `⌘,` shortcut

**Depends on:** Task 4 (`settingsDialogOpenAtom`/`settingsDialogSectionAtom`/`openSettingsAtom`).

**Files:**

- Modify (full rewrite): `src/components/settings-dialog.tsx`
- Create: `src/components/settings-dialog.test.tsx`
- Modify: `src/components/title-bar.tsx`

**Interfaces:**

- Consumes: `settingsDialogOpenAtom`, `settingsDialogSectionAtom` (Task 4).
- Produces: `SettingsDialog` component (no props — reads/writes the atoms directly, self-contained like `AiSettingsDialog` was). Later tasks (8-11) each add one section's real content in place of this task's placeholder `<div>`s — this task's job is only the shell (navigation, dialog open/close, section switching), not any section's content.

- [ ] **Step 1: Write the failing test**

Create `src/components/settings-dialog.test.tsx` (this replaces whatever test file, if any, exists for the old scaffold — check first and remove it if it tests the old unused boilerplate):

```tsx
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { getDefaultStore } from 'jotai'
import { test, expect, beforeEach } from 'vitest'

import { SettingsDialog } from '#components/settings-dialog'
import { settingsDialogOpenAtom, settingsDialogSectionAtom } from '#lib/store'

beforeEach(() => {
  getDefaultStore().set(settingsDialogOpenAtom, false)
  getDefaultStore().set(settingsDialogSectionAtom, 'general')
})

test('closed by default, opens when settingsDialogOpenAtom is set', () => {
  render(<SettingsDialog />)
  expect(screen.queryByTestId('settings-dialog')).not.toBeInTheDocument()
  getDefaultStore().set(settingsDialogOpenAtom, true)
  expect(screen.getByTestId('settings-dialog')).toBeInTheDocument()
})

test('shows the General section by default and switches sections on nav click', async () => {
  getDefaultStore().set(settingsDialogOpenAtom, true)
  render(<SettingsDialog />)
  expect(screen.getByTestId('settings-section-general')).toBeInTheDocument()
  await userEvent.click(screen.getByTestId('settings-nav-appearance'))
  expect(screen.getByTestId('settings-section-appearance')).toBeInTheDocument()
  expect(
    screen.queryByTestId('settings-section-general')
  ).not.toBeInTheDocument()
})

test('opens directly to whichever section settingsDialogSectionAtom holds', () => {
  getDefaultStore().set(settingsDialogSectionAtom, 'logs')
  getDefaultStore().set(settingsDialogOpenAtom, true)
  render(<SettingsDialog />)
  expect(screen.getByTestId('settings-section-logs')).toBeInTheDocument()
})
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `pnpm test settings-dialog`
Expected: FAIL — the old scaffold at this path doesn't match this shape.

- [ ] **Step 3: Implement the shell**

Fully replace `src/components/settings-dialog.tsx` (delete every import/section from the old unused scaffold — `Breadcrumb`, the icon imports, etc. — none of it carries over):

```tsx
import { useAtom } from 'jotai'

import { Dialog, DialogContent } from '#components/ui/dialog'
import { cn } from '#lib/utils'
import {
  settingsDialogOpenAtom,
  settingsDialogSectionAtom,
  type SettingsSection
} from '#lib/store'

const SECTIONS: { id: SettingsSection; label: string }[] = [
  { id: 'general', label: 'General' },
  { id: 'appearance', label: 'Appearance' },
  { id: 'ai', label: 'AI' },
  { id: 'logs', label: 'Logs' },
  { id: 'about', label: 'About & Updates' }
]

export function SettingsDialog() {
  const [open, setOpen] = useAtom(settingsDialogOpenAtom)
  const [section, setSection] = useAtom(settingsDialogSectionAtom)

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogContent
        data-testid="settings-dialog"
        className="flex h-125 w-175 max-w-none gap-0 p-0"
      >
        <nav className="bg-muted/40 flex w-40 shrink-0 flex-col gap-1 border-r p-2">
          {SECTIONS.map((s) => (
            <button
              key={s.id}
              type="button"
              data-testid={`settings-nav-${s.id}`}
              onClick={() => setSection(s.id)}
              className={cn(
                'rounded-md px-2.5 py-1.5 text-left text-sm transition-colors',
                section === s.id
                  ? 'bg-accent text-accent-foreground'
                  : 'text-muted-foreground hover:bg-accent/50'
              )}
            >
              {s.label}
            </button>
          ))}
        </nav>
        <div className="min-w-0 flex-1 overflow-y-auto p-6">
          {/* Task 8-11 each replace one of these placeholders with the
              section's real content - this task builds only the shell. */}
          {section === 'general' && (
            <div data-testid="settings-section-general" />
          )}
          {section === 'appearance' && (
            <div data-testid="settings-section-appearance" />
          )}
          {section === 'ai' && <div data-testid="settings-section-ai" />}
          {section === 'logs' && <div data-testid="settings-section-logs" />}
          {section === 'about' && <div data-testid="settings-section-about" />}
        </div>
      </DialogContent>
    </Dialog>
  )
}
```

Check `#components/ui/dialog`'s exact `DialogContent` props first (whether it needs a `showCloseButton` prop or renders one automatically, matching how `AiSettingsDialog`/other dialogs in this app already use it) rather than guessing.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `pnpm test settings-dialog && pnpm exec tsc --noEmit`
Expected: PASS, clean.

- [ ] **Step 5: Wire the title-bar entry point and `⌘,` shortcut**

Read `src/components/title-bar.tsx` in full first (it currently renders `SidebarTrigger`, the `<AiSettingsDialog />` trigger, a spacer, and the theme-toggle button in a flex row). Replace the `<AiSettingsDialog />` line with a gear-icon button and mount `<SettingsDialog />` as a sibling (it manages its own open state via the atom, so it doesn't need to be inside any particular DOM position, but keep it in the header row near the trigger for readability):

```tsx
import { Settings as SettingsIcon } from 'lucide-react'
import { useSetAtom } from 'jotai'

import { SettingsDialog } from '#components/settings-dialog'
import { openSettingsAtom } from '#lib/store'
```

```tsx
const openSettings = useSetAtom(openSettingsAtom)
```

```tsx
      <Button
        variant="ghost"
        size="icon"
        className="size-7"
        data-testid="settings-trigger"
        onClick={() => openSettings()}
      >
        <SettingsIcon className="size-4" />
        <span className="sr-only">Settings</span>
      </Button>
      <SettingsDialog />
```

Remove the now-unused `import { AiSettingsDialog } from '#components/ai-settings-dialog'` line — the component itself isn't deleted yet (Task 10 folds its content in and deletes it), just this file no longer renders it directly.

Add the `⌘,` listener in the same file (matching `ui/sidebar.tsx`'s existing `window.addEventListener('keydown', ...)` pattern):

```tsx
useEffect(() => {
  const handleKeyDown = (event: KeyboardEvent) => {
    if (event.key === ',' && (event.metaKey || event.ctrlKey)) {
      event.preventDefault()
      openSettings()
    }
  }
  window.addEventListener('keydown', handleKeyDown)
  return () => window.removeEventListener('keydown', handleKeyDown)
}, [openSettings])
```

Add `useEffect` to the existing `react` import line.

- [ ] **Step 6: Live-verify**

With `pnpm dev` running, click the new gear icon and confirm the dialog opens to General with all 5 nav items clickable and switching the empty placeholder panes; press `⌘,` (or `Ctrl+,`) and confirm it also opens the dialog. Confirm the sidebar toggle and theme-toggle buttons still work unchanged.

- [ ] **Step 7: Run the full check set**

Run: `pnpm test && pnpm exec tsc --noEmit`
Expected: all green (the still-standalone `AiSettingsDialog` component and its own test file are untouched by this task — they just aren't rendered from `title-bar.tsx` anymore; `ai-settings-dialog.test.tsx` renders the component directly, not via `title-bar.tsx`, so it's unaffected).

- [ ] **Step 8: Commit**

```bash
git add src/components/settings-dialog.tsx src/components/settings-dialog.test.tsx src/components/title-bar.tsx
git commit -m "feat: Settings dialog shell (sidebar nav) + title-bar entry point + ⌘,

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: General & About sections

**Depends on:** Task 2 (`@tauri-apps/plugin-dialog`), Task 3 (`Backend.setVaultPath`, existing `Backend.rebuildIndex`), Task 7 (dialog shell).

**Files:**

- Create: `src/components/settings/general-section.tsx`, `src/components/settings/general-section.test.tsx`, `src/components/settings/about-section.tsx`, `src/components/settings/about-section.test.tsx`
- Modify: `src/components/settings-dialog.tsx`

**Interfaces:**

- Consumes: `backend.getVaultInfo(): Promise<VaultInfo>`, `backend.setVaultPath(path): Promise<VaultInfo>`, `backend.rebuildIndex(): Promise<number>` (existing/Task 3), `@tauri-apps/plugin-dialog`'s `open` (Task 2), `@tauri-apps/api/app`'s `getVersion()`.
- Produces: `GeneralSection`, `AboutSection` components (both no props, self-contained).

- [ ] **Step 1: Write the failing test for `GeneralSection`**

Create `src/components/settings/general-section.test.tsx`:

```tsx
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { test, expect, vi, beforeEach } from 'vitest'

vi.mock('@tauri-apps/plugin-dialog', () => ({ open: vi.fn() }))

import { GeneralSection } from '#components/settings/general-section'
import { backend } from '#lib/backend/index'
import { open as openDialog } from '@tauri-apps/plugin-dialog'

beforeEach(async () => {
  vi.mocked(openDialog).mockReset()
  // `backend` is this app's shared module-level singleton (imported the same
  // way the component itself imports it), not a fresh instance per test -
  // reset its vault path back to the known default so tests don't leak
  // state into each other regardless of declaration order.
  await backend.setVaultPath('(in-memory)')
})

test('shows the current vault path on mount', async () => {
  render(<GeneralSection />)
  await waitFor(() =>
    expect(screen.getByTestId('vault-path')).toHaveTextContent('(in-memory)')
  )
})

test('choosing a folder from the native picker updates the vault path', async () => {
  vi.mocked(openDialog).mockResolvedValue('/tmp/new-vault')
  render(<GeneralSection />)
  await waitFor(() => screen.getByTestId('vault-path'))
  await userEvent.click(screen.getByTestId('change-vault-path'))
  await waitFor(() =>
    expect(screen.getByTestId('vault-path')).toHaveTextContent('/tmp/new-vault')
  )
})

test('cancelling the native picker (null result) leaves the vault path unchanged', async () => {
  vi.mocked(openDialog).mockResolvedValue(null)
  render(<GeneralSection />)
  await waitFor(() => screen.getByTestId('vault-path'))
  await userEvent.click(screen.getByTestId('change-vault-path'))
  await waitFor(() =>
    expect(screen.getByTestId('vault-path')).toHaveTextContent('(in-memory)')
  )
})

test('rebuild index button calls backend.rebuildIndex', async () => {
  const spy = vi.spyOn(backend, 'rebuildIndex')
  render(<GeneralSection />)
  await waitFor(() => screen.getByTestId('vault-path'))
  await userEvent.click(screen.getByTestId('rebuild-index'))
  await waitFor(() => expect(spy).toHaveBeenCalled())
  spy.mockRestore()
})
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `pnpm test general-section`
Expected: FAIL — `#components/settings/general-section` doesn't exist.

- [ ] **Step 3: Implement `GeneralSection`**

Create `src/components/settings/general-section.tsx`. Use the exact `open()` signature/return type confirmed in Task 2 rather than guessing — the draft below assumes `open({ directory: true }): Promise<string | null>`, adjust if Task 2's verification found otherwise:

```tsx
import { open as openDialog } from '@tauri-apps/plugin-dialog'
import { useEffect, useState } from 'react'

import { Button } from '#components/ui/button'
import { reportError } from '#lib/errors'
import { backend } from '#lib/backend/index'

export function GeneralSection() {
  const [vaultPath, setVaultPath] = useState('')
  const [rebuilding, setRebuilding] = useState(false)

  useEffect(() => {
    backend.getVaultInfo().then((info) => setVaultPath(info.vaultPath))
  }, [])

  const changeVaultPath = async () => {
    const selected = await openDialog({ directory: true })
    if (!selected || Array.isArray(selected)) return
    try {
      const info = await backend.setVaultPath(selected)
      setVaultPath(info.vaultPath)
    } catch (err) {
      reportError('HK-1005', {
        message: err instanceof Error ? err.message : String(err)
      })
    }
  }

  const rebuildIndex = async () => {
    setRebuilding(true)
    try {
      await backend.rebuildIndex()
    } catch (err) {
      reportError('HK-2001', {
        message: err instanceof Error ? err.message : String(err)
      })
    } finally {
      setRebuilding(false)
    }
  }

  return (
    <div className="flex flex-col gap-4">
      <div>
        <p className="text-sm font-medium">Vault location</p>
        <p
          data-testid="vault-path"
          className="text-muted-foreground mt-1 truncate text-sm"
        >
          {vaultPath}
        </p>
        <div className="mt-2 flex gap-2">
          <Button
            variant="outline"
            size="sm"
            onClick={changeVaultPath}
            data-testid="change-vault-path"
          >
            Change…
          </Button>
        </div>
      </div>
      <div>
        <p className="text-sm font-medium">Search index</p>
        <Button
          variant="outline"
          size="sm"
          className="mt-2"
          onClick={rebuildIndex}
          disabled={rebuilding}
          data-testid="rebuild-index"
        >
          {rebuilding ? 'Rebuilding…' : 'Rebuild index'}
        </Button>
      </div>
    </div>
  )
}
```

Note: "Reveal in Finder" was in the original spec bullet but has no meaning in `MemoryBackend`/browser dev mode and no existing IPC command to call — check whether `@tauri-apps/plugin-opener`'s already-installed `revealItemInDir` (used elsewhere in this app, confirm via grep) can be called directly here gated on `isTauri()` (add `import { isTauri } from '#lib/backend/index'` alongside `backend` if so — the draft above doesn't import it since this addition is your call); if so add a second button calling it with the current `vaultPath`, otherwise note in your report why it was omitted rather than silently dropping it.

- [ ] **Step 4: Run the test to verify it passes**

Run: `pnpm test general-section && pnpm exec tsc --noEmit`
Expected: PASS, clean.

- [ ] **Step 5: Write the failing test for `AboutSection`**

Create `src/components/settings/about-section.test.tsx`:

```tsx
import { render, screen, waitFor } from '@testing-library/react'
import { test, expect, vi } from 'vitest'

vi.mock('@tauri-apps/api/app', () => ({
  getVersion: vi.fn().mockResolvedValue('0.1.0')
}))

import { AboutSection } from '#components/settings/about-section'

test('shows the app version', async () => {
  render(<AboutSection />)
  await waitFor(() =>
    expect(screen.getByTestId('app-version')).toHaveTextContent('0.1.0')
  )
})
```

- [ ] **Step 6: Run the test to verify it fails**

Run: `pnpm test about-section`
Expected: FAIL — `#components/settings/about-section` doesn't exist.

- [ ] **Step 7: Implement `AboutSection`**

Create `src/components/settings/about-section.tsx`. Confirm `@tauri-apps/api/app`'s `getVersion()` is real and returns `Promise<string>` against the installed package before finalizing (it's already a transitive part of `@tauri-apps/api`, already a dependency — no new package needed) — if it throws or is unavailable outside a real Tauri context (likely, since there's no Tauri IPC bridge in browser/dev mode), gate the call on `isTauri()` and fall back to reading the version a different way in dev mode (e.g. a `pnpm`-injected `import.meta.env` value, or simply show `"dev"` as a placeholder in non-Tauri mode — your call, document whichever you pick):

```tsx
import { getVersion } from '@tauri-apps/api/app'
import { useEffect, useState } from 'react'

import { isTauri } from '#lib/backend/index'

export function AboutSection() {
  const [version, setVersion] = useState('dev')

  useEffect(() => {
    if (!isTauri()) return
    getVersion().then(setVersion)
  }, [])

  return (
    <div className="flex flex-col gap-2">
      <p className="text-sm font-medium">Hikki</p>
      <p data-testid="app-version" className="text-muted-foreground text-sm">
        Version {version}
      </p>
    </div>
  )
}
```

- [ ] **Step 8: Run the test to verify it passes**

Run: `pnpm test about-section && pnpm exec tsc --noEmit`
Expected: PASS, clean.

- [ ] **Step 9: Wire both sections into `SettingsDialog`**

In `src/components/settings-dialog.tsx`, replace the `general`/`about` placeholder `<div>`s with the real components:

```tsx
import { GeneralSection } from '#components/settings/general-section'
import { AboutSection } from '#components/settings/about-section'
```

```tsx
{
  section === 'general' && (
    <div data-testid="settings-section-general">
      <GeneralSection />
    </div>
  )
}
```

```tsx
{
  section === 'about' && (
    <div data-testid="settings-section-about">
      <AboutSection />
    </div>
  )
}
```

(Keep the outer `data-testid` wrapper `<div>`s — `settings-dialog.test.tsx`'s existing section-switching tests query by those.)

- [ ] **Step 10: Run the full check set**

Run: `pnpm test && pnpm exec tsc --noEmit`
Expected: all green.

- [ ] **Step 11: Live-verify**

With `pnpm dev` running, open Settings, confirm General shows the in-memory vault path (dev mode), clicking "Change…" opens... nothing real in browser mode (native dialogs don't exist there) — confirm it doesn't crash, just no-ops or resolves to whatever `MemoryBackend`'s stand-in returns; confirm "Rebuild index" doesn't error. Confirm About shows a version string (likely "dev" per Step 7's fallback). Full native-picker behavior can only be verified in the real Tauri app — note this in your report the same way Task 2's plugin-http live-CORS check was deferred in Phase 3.

- [ ] **Step 12: Commit**

```bash
git add src/components/settings/general-section.tsx src/components/settings/general-section.test.tsx src/components/settings/about-section.tsx src/components/settings/about-section.test.tsx src/components/settings-dialog.tsx
git commit -m "feat: Settings General and About sections

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 9: Appearance section

**Depends on:** Task 7 (dialog shell).

**Files:**

- Create: `src/components/settings/appearance-section.tsx`, `src/components/settings/appearance-section.test.tsx`
- Modify: `src/components/settings-dialog.tsx`, `src/components/title-bar.tsx`

**Interfaces:**

- Consumes: `next-themes`' `useTheme()` (already used by `title-bar.tsx` and `theme-provider.tsx`).
- Produces: `AppearanceSection` component (no props).

- [ ] **Step 1: Write the failing test**

Create `src/components/settings/appearance-section.test.tsx`:

```tsx
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { test, expect } from 'vitest'
import { ThemeProvider } from '#components/theme-provider'

import { AppearanceSection } from '#components/settings/appearance-section'

test('clicking Dark sets the theme to dark', async () => {
  render(
    <ThemeProvider>
      <AppearanceSection />
    </ThemeProvider>
  )
  await userEvent.click(screen.getByTestId('appearance-mode-dark'))
  expect(document.documentElement.className).toContain('dark')
})

test('clicking Light sets the theme to light', async () => {
  render(
    <ThemeProvider>
      <AppearanceSection />
    </ThemeProvider>
  )
  await userEvent.click(screen.getByTestId('appearance-mode-light'))
  expect(document.documentElement.className).not.toContain('dark')
})
```

Check how this codebase's _existing_ theme-related tests (if any test `title-bar.tsx`'s theme toggle) assert on `next-themes` state before finalizing this — match whatever pattern is already established rather than introducing a new one.

- [ ] **Step 2: Run the test to verify it fails**

Run: `pnpm test appearance-section`
Expected: FAIL — `#components/settings/appearance-section` doesn't exist.

- [ ] **Step 3: Implement `AppearanceSection`**

Create `src/components/settings/appearance-section.tsx`:

```tsx
import { useTheme } from 'next-themes'

import { Button } from '#components/ui/button'
import { cn } from '#lib/utils'

const MODES = ['light', 'dark', 'system'] as const

export function AppearanceSection() {
  const { theme, setTheme } = useTheme()

  return (
    <div className="flex flex-col gap-2">
      <p className="text-sm font-medium">Appearance</p>
      <div className="flex gap-2">
        {MODES.map((mode) => (
          <Button
            key={mode}
            variant="outline"
            size="sm"
            data-testid={`appearance-mode-${mode}`}
            className={cn(theme === mode && 'border-ring')}
            onClick={() => setTheme(mode)}
          >
            {mode[0].toUpperCase() + mode.slice(1)}
          </Button>
        ))}
      </div>
    </div>
  )
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `pnpm test appearance-section && pnpm exec tsc --noEmit`
Expected: PASS, clean.

- [ ] **Step 5: Wire into `SettingsDialog`**

In `src/components/settings-dialog.tsx`, replace the `appearance` placeholder:

```tsx
import { AppearanceSection } from '#components/settings/appearance-section'
```

```tsx
{
  section === 'appearance' && (
    <div data-testid="settings-section-appearance">
      <AppearanceSection />
    </div>
  )
}
```

- [ ] **Step 6: Confirm the title-bar quick-toggle stays put**

Per §14c's decision, the existing theme-toggle button in `title-bar.tsx` (`data-testid="theme-toggle"`) is **not** removed by this task — it remains as a fast one-click affordance alongside the fuller Appearance section. Read `title-bar.tsx` to confirm this button and its `setTheme(resolvedTheme === 'dark' ? 'light' : 'dark')` logic are untouched; no changes needed here unless something in Task 7/8's edits accidentally disturbed it (check `git diff` against the pre-Task-7 version if unsure).

- [ ] **Step 7: Run the full check set**

Run: `pnpm test && pnpm exec tsc --noEmit`
Expected: all green.

- [ ] **Step 8: Live-verify**

With `pnpm dev` running, open Settings → Appearance, click each mode button, confirm the whole app's theme changes and the title-bar's own quick-toggle button still works and reflects the same underlying state (clicking it while Settings is open, if visible, should update the Appearance section's highlighted button too, since both read the same `next-themes` state).

- [ ] **Step 9: Commit**

```bash
git add src/components/settings/appearance-section.tsx src/components/settings/appearance-section.test.tsx src/components/settings-dialog.tsx
git commit -m "feat: Settings Appearance section (mode only)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 10: AI section (fold in `AiSettingsDialog`)

**Depends on:** Task 6 (retrofitted `ai-settings-dialog.tsx`), Task 7 (dialog shell).

**Files:**

- Create: `src/components/settings/ai-section.tsx`, `src/components/settings/ai-section.test.tsx`
- Delete: `src/components/ai-settings-dialog.tsx`, `src/components/ai-settings-dialog.test.tsx`
- Modify: `src/components/settings-dialog.tsx`, `e2e-tests/app.spec.ts`

**Interfaces:**

- Produces: `AiSection` component (no props) — same behavior as the old `AiSettingsDialog`, minus the `Dialog`/`DialogTrigger` wrapper (it's now rendered directly inside `SettingsDialog`'s content pane, not its own separate dialog).

- [ ] **Step 1: Move the test file**

Copy `src/components/ai-settings-dialog.test.tsx` to `src/components/settings/ai-section.test.tsx`, updating:

- The import from `#components/ai-settings-dialog` (named export `AiSettingsDialog`) to `#components/settings/ai-section` (named export `AiSection`).
- Every `render(<AiSettingsDialog />)` to `render(<AiSection />)`.
- Remove any test/assertion that specifically exercised the old `Dialog`/`DialogTrigger`/open-close behavior (e.g. a test clicking `ai-settings-trigger` to open it before interacting with the fields) — `AiSection` has no trigger or open state of its own now, since `SettingsDialog`'s own nav handles that; its fields are just always rendered when the AI section is active. Keep every test that exercises the actual save/test-connection/default-model logic, just render `<AiSection />` directly without an opening click first.

- [ ] **Step 2: Run the test to verify it fails**

Run: `pnpm test ai-section`
Expected: FAIL — `#components/settings/ai-section` doesn't exist yet.

- [ ] **Step 3: Implement `AiSection`**

Read `src/components/ai-settings-dialog.tsx` in full (post-Task-6 retrofit) first. Create `src/components/settings/ai-section.tsx` with the same content, minus the `Dialog`/`DialogTrigger`/`DialogContent`/`DialogHeader`/`DialogTitle` wrapper — i.e., take everything currently inside `<DialogContent>...</DialogContent>` and render it as the component's direct return value (a plain `<div className="flex flex-col gap-3">...</div>` wrapping what's already there), keeping every `data-testid`, every `useState`/`useEffect`, `saveKey`/`testConnection`/`saveDefaults` function, and the retrofitted `reportError` calls from Task 6 exactly as they are. Rename the exported function from `AiSettingsDialog` to `AiSection`.

The `useEffect` that currently loads settings gated on `if (!open) return` (since it used to run only while the dialog was open) should instead just run unconditionally on mount, since this component only exists in the tree while its section is the active one — remove the `open`/`!open` check and the dependency on an `open` variable entirely (there's no local `open` state anymore).

- [ ] **Step 4: Run the test to verify it passes**

Run: `pnpm test ai-section && pnpm exec tsc --noEmit`
Expected: PASS, clean.

- [ ] **Step 5: Wire into `SettingsDialog` and delete the old files**

In `src/components/settings-dialog.tsx`, replace the `ai` placeholder:

```tsx
import { AiSection } from '#components/settings/ai-section'
```

```tsx
{
  section === 'ai' && (
    <div data-testid="settings-section-ai">
      <AiSection />
    </div>
  )
}
```

Delete `src/components/ai-settings-dialog.tsx` and `src/components/ai-settings-dialog.test.tsx` (`git rm`).

- [ ] **Step 6: Fix the e2e `configureAiSettings` helper**

Task 7 removed the title bar's `<AiSettingsDialog />` trigger (`data-testid="ai-settings-trigger"`), replacing it with a gear-icon `data-testid="settings-trigger"` that opens the new `SettingsDialog`. `e2e-tests/app.spec.ts`'s `configureAiSettings` helper (used throughout the whole `Writing Tools` describe block) still opens the old, now-nonexistent trigger — this is the point in the plan where that gets fixed, since this task is what gives the AI section a real, reachable home in the new dialog.

In `e2e-tests/app.spec.ts`, find `configureAiSettings`:

```ts
async function configureAiSettings(page: Page) {
  await page.getByTestId('ai-settings-trigger').click()
  await page.getByTestId('ai-settings-default-provider').selectOption('openai')
  await page.getByTestId('ai-settings-key-openai').fill('sk-test-key')
  await page.getByTestId('ai-settings-save-openai').click()
  await page.getByTestId('ai-settings-default-model').selectOption({ index: 1 })
  await page.keyboard.press('Escape')
}
```

Replace only the opening line — the rest of the helper is unaffected since `AiSection` keeps every `data-testid` from the old `AiSettingsDialog` unchanged (per Step 3):

```ts
async function configureAiSettings(page: Page) {
  await page.getByTestId('settings-trigger').click()
  await page.getByTestId('settings-nav-ai').click()
  await page.getByTestId('ai-settings-default-provider').selectOption('openai')
  await page.getByTestId('ai-settings-key-openai').fill('sk-test-key')
  await page.getByTestId('ai-settings-save-openai').click()
  await page.getByTestId('ai-settings-default-model').selectOption({ index: 1 })
  await page.keyboard.press('Escape')
}
```

- [ ] **Step 7: Run the full check set, including e2e**

Run: `pnpm test && pnpm exec tsc --noEmit`
Expected: all green — confirm nothing else in `src/` still imports `#components/ai-settings-dialog` (`grep -rn "ai-settings-dialog" src/` should return nothing).

Then run: `pnpm e2e`
Expected: the whole `Writing Tools` describe block (every test that calls `configureAiSettings`) passes again — this is the first point since Task 7 where `pnpm e2e` has been runnable end-to-end, since the trigger it depends on didn't exist in the tree from Task 7 through Task 9.

- [ ] **Step 8: Live-verify**

With `pnpm dev` running, open Settings → AI, confirm both provider key rows, test-connection buttons, and default-provider/model selects render and behave exactly as `AiSettingsDialog` did before (save a key, run a test connection against the faux provider, pick defaults) — this is a relocation, not a behavior change, so everything should work identically to how it was verified in Phase 3's Task 8.

- [ ] **Step 9: Commit**

```bash
git add src/components/settings/ai-section.tsx src/components/settings/ai-section.test.tsx src/components/settings-dialog.tsx e2e-tests/app.spec.ts
git rm src/components/ai-settings-dialog.tsx src/components/ai-settings-dialog.test.tsx
git commit -m "feat: fold AiSettingsDialog into the Settings AI section

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 11: Logs section

**Depends on:** Task 1/3 (logging backend + `Backend.readLogs`/`clearLogs`), Task 2 (`@tauri-apps/plugin-dialog`'s `save`), Task 7 (dialog shell).

**Files:**

- Create: `src/components/settings/logs-section.tsx`, `src/components/settings/logs-section.test.tsx`
- Modify: `src/components/settings-dialog.tsx`

**Interfaces:**

- Consumes: `backend.readLogs(filter: LogFilter): Promise<LogEntry[]>`, `backend.clearLogs(): Promise<void>` (Task 3), `@tauri-apps/plugin-dialog`'s `save` (Task 2).
- Produces: `LogsSection` component (no props).

- [ ] **Step 1: Write the failing test**

Create `src/components/settings/logs-section.test.tsx`:

```tsx
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { test, expect, vi, beforeEach } from 'vitest'

vi.mock('@tauri-apps/plugin-dialog', () => ({ save: vi.fn() }))

import { LogsSection } from '#components/settings/logs-section'
import { backend } from '#lib/backend/index'
import { save as saveDialog } from '@tauri-apps/plugin-dialog'

beforeEach(async () => {
  await backend.clearLogs()
  vi.mocked(saveDialog).mockReset()
})

test('renders existing log entries newest first', async () => {
  await backend.appendLog({
    level: 'info',
    scope: 'a',
    message: 'first',
    timestamp: new Date(0).toISOString()
  })
  await backend.appendLog({
    level: 'error',
    scope: 'b',
    message: 'second',
    timestamp: new Date(1).toISOString()
  })
  render(<LogsSection />)
  const rows = await screen.findAllByTestId('log-row')
  expect(rows).toHaveLength(2)
  expect(rows[0]).toHaveTextContent('second')
  expect(rows[1]).toHaveTextContent('first')
})

test('level filter narrows the visible rows', async () => {
  await backend.appendLog({
    level: 'info',
    scope: 'a',
    message: 'calm',
    timestamp: new Date().toISOString()
  })
  await backend.appendLog({
    level: 'error',
    scope: 'b',
    message: 'boom',
    timestamp: new Date().toISOString()
  })
  render(<LogsSection />)
  await screen.findAllByTestId('log-row')
  await userEvent.selectOptions(screen.getByTestId('log-level-filter'), 'error')
  await waitFor(async () => {
    const rows = await screen.findAllByTestId('log-row')
    expect(rows).toHaveLength(1)
    expect(rows[0]).toHaveTextContent('boom')
  })
})

test('text search narrows the visible rows', async () => {
  await backend.appendLog({
    level: 'info',
    scope: 'a',
    message: 'vault reindexed',
    timestamp: new Date().toISOString()
  })
  await backend.appendLog({
    level: 'info',
    scope: 'b',
    message: 'ai request sent',
    timestamp: new Date().toISOString()
  })
  render(<LogsSection />)
  await screen.findAllByTestId('log-row')
  await userEvent.type(screen.getByTestId('log-search'), 'vault')
  await waitFor(async () => {
    const rows = await screen.findAllByTestId('log-row')
    expect(rows).toHaveLength(1)
    expect(rows[0]).toHaveTextContent('vault reindexed')
  })
})

test('clear button empties the log list', async () => {
  await backend.appendLog({
    level: 'info',
    scope: 'a',
    message: 'x',
    timestamp: new Date().toISOString()
  })
  render(<LogsSection />)
  await screen.findAllByTestId('log-row')
  await userEvent.click(screen.getByTestId('logs-clear'))
  await waitFor(() =>
    expect(screen.queryAllByTestId('log-row')).toHaveLength(0)
  )
})

test('export writes the currently-filtered rows via the native save dialog', async () => {
  vi.mocked(saveDialog).mockResolvedValue('/tmp/hikki-logs.jsonl')
  await backend.appendLog({
    level: 'info',
    scope: 'a',
    message: 'x',
    timestamp: new Date().toISOString()
  })
  render(<LogsSection />)
  await screen.findAllByTestId('log-row')
  await userEvent.click(screen.getByTestId('logs-export'))
  await waitFor(() => expect(saveDialog).toHaveBeenCalled())
})
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `pnpm test logs-section`
Expected: FAIL — `#components/settings/logs-section` doesn't exist.

- [ ] **Step 3: Implement `LogsSection`**

Create `src/components/settings/logs-section.tsx`. Confirm `save()`'s exact signature from Task 2's verification (the draft below assumes it takes `{ defaultPath?: string }`-like options and returns `Promise<string | null>`) and adjust if different; for actually writing file contents to the chosen path, check whether `@tauri-apps/plugin-dialog` itself writes the file or whether this needs `@tauri-apps/plugin-fs`'s `writeTextFile` (a separate, not-yet-installed plugin) — verify which is true rather than assuming `save()` does the writing itself, since dialog plugins in Tauri 2 typically only return the chosen _path_, with a separate fs-write call needed to actually put content there:

```tsx
import { save as saveDialog } from '@tauri-apps/plugin-dialog'
import { useEffect, useState } from 'react'

import { reportError } from '#lib/errors'
import { backend, isTauri } from '#lib/backend/index'
import type { LogEntry, LogLevel } from '#lib/types'

export function LogsSection() {
  const [entries, setEntries] = useState<LogEntry[]>([])
  const [level, setLevel] = useState<LogLevel | ''>('')
  const [query, setQuery] = useState('')

  const refresh = async (nextLevel: LogLevel | '', nextQuery: string) => {
    try {
      const logs = await backend.readLogs({
        level: nextLevel || undefined,
        query: nextQuery || undefined
      })
      setEntries(logs)
    } catch (err) {
      reportError('HK-6001', {
        message: err instanceof Error ? err.message : String(err)
      })
    }
  }

  useEffect(() => {
    refresh(level, query)
    // Deliberately re-runs only on level/query change, not on every render.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [level, query])

  const clear = async () => {
    await backend.clearLogs()
    setEntries([])
  }

  const exportLogs = async () => {
    if (!isTauri()) return
    try {
      const path = await saveDialog({ defaultPath: 'hikki-logs.jsonl' })
      if (!path) return
      // Confirmed which real API writes the file contents to `path` during
      // Task 2/this task's own verification step - fill in the actual write
      // call here (likely `@tauri-apps/plugin-fs`'s `writeTextFile`, a new
      // dependency if so) rather than assuming `save()` alone persists data.
    } catch (err) {
      reportError('HK-6002', {
        message: err instanceof Error ? err.message : String(err)
      })
    }
  }

  return (
    <div className="flex h-full flex-col gap-3">
      <div className="flex gap-2">
        <select
          data-testid="log-level-filter"
          value={level}
          onChange={(e) => setLevel(e.target.value as LogLevel | '')}
          className="h-8 rounded-lg border border-input bg-transparent px-2.5 text-sm"
        >
          <option value="">All levels</option>
          <option value="info">Info</option>
          <option value="warn">Warn</option>
          <option value="error">Error</option>
        </select>
        <input
          data-testid="log-search"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search…"
          className="h-8 flex-1 rounded-lg border border-input bg-transparent px-2.5 text-sm"
        />
        <button
          type="button"
          data-testid="logs-export"
          onClick={exportLogs}
          className="h-8 rounded-lg border border-input px-2.5 text-sm"
        >
          Export…
        </button>
        <button
          type="button"
          data-testid="logs-clear"
          onClick={clear}
          className="h-8 rounded-lg border border-input px-2.5 text-sm"
        >
          Clear
        </button>
      </div>
      <div className="min-h-0 flex-1 overflow-y-auto">
        {entries.map((entry, i) => (
          <div
            key={i}
            data-testid="log-row"
            className="flex gap-2 border-b py-1 text-xs"
          >
            <span className="text-muted-foreground">{entry.timestamp}</span>
            <span className="font-medium">{entry.level}</span>
            <span className="text-muted-foreground">{entry.scope}</span>
            <span>{entry.message}</span>
          </div>
        ))}
      </div>
    </div>
  )
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `pnpm test logs-section && pnpm exec tsc --noEmit`
Expected: PASS, clean.

- [ ] **Step 5: Wire into `SettingsDialog`**

In `src/components/settings-dialog.tsx`, replace the `logs` placeholder:

```tsx
import { LogsSection } from '#components/settings/logs-section'
```

```tsx
{
  section === 'logs' && (
    <div data-testid="settings-section-logs">
      <LogsSection />
    </div>
  )
}
```

- [ ] **Step 6: Run the full check set**

Run: `pnpm test && pnpm exec tsc --noEmit`
Expected: all green.

- [ ] **Step 7: Live-verify**

With `pnpm dev` running, do a few things that call `log.*()` or `reportError()` (e.g. trigger the unhandledrejection test from Task 5's live-verify again, or an AI-error path from Task 6), open Settings → Logs, confirm the entries appear, filter by level, search by text, and confirm Clear empties the list. Export can't be meaningfully live-verified in browser/dev mode (no real native dialog) — note this the same way Task 8's native-picker check was deferred.

- [ ] **Step 8: Commit**

```bash
git add src/components/settings/logs-section.tsx src/components/settings/logs-section.test.tsx src/components/settings-dialog.tsx
git commit -m "feat: Settings Logs section

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 12: e2e coverage for the full Settings flow

**Depends on:** Tasks 7-11 (the whole dialog + all 4 real sections).

**Files:**

- Modify: `e2e-tests/app.spec.ts`

- [ ] **Step 1: Add the e2e tests**

Read the existing file's conventions first (helper functions, `test.describe` grouping style — e.g. the `Writing Tools` describe block from Phase 3). Add a new block:

```ts
test.describe('Settings dialog', () => {
  test('opens via the title-bar gear icon and navigates between sections', async ({
    page
  }) => {
    await page.goto('/')
    await page.getByTestId('settings-trigger').click()
    await expect(page.getByTestId('settings-section-general')).toBeVisible()
    await page.getByTestId('settings-nav-appearance').click()
    await expect(page.getByTestId('settings-section-appearance')).toBeVisible()
  })

  test('opens via the ⌘, keyboard shortcut', async ({ page }) => {
    await page.goto('/')
    await page.keyboard.press('Meta+,')
    await expect(page.getByTestId('settings-dialog')).toBeVisible()
  })

  test('Appearance mode buttons change the app theme', async ({ page }) => {
    await page.goto('/')
    await page.getByTestId('settings-trigger').click()
    await page.getByTestId('settings-nav-appearance').click()
    await page.getByTestId('appearance-mode-dark').click()
    await expect(page.locator('html')).toHaveClass(/dark/)
    await page.getByTestId('appearance-mode-light').click()
    await expect(page.locator('html')).not.toHaveClass(/dark/)
  })

  test('Logs section shows entries, filters, and clears', async ({ page }) => {
    await page.goto('/')
    // Trigger at least one real logged event first - the missing-defaults
    // Writing Tools error path already exercises reportError/logging.
    await page.getByTestId('new-doc').click()
    const editable = page
      .getByTestId('editor')
      .locator('[contenteditable="true"]')
      .first()
    await editable.click()
    await page.keyboard.type('Some text.')
    await page.keyboard.press('Home')
    await page.keyboard.down('Shift')
    await page.keyboard.press('End')
    await page.keyboard.up('Shift')
    await page.getByTestId('writing-tools-button').click()
    await page.getByTestId('writing-tools-proofread').click()
    await expect(page.getByTestId('writing-tools-error')).toBeVisible()

    await page.getByTestId('settings-trigger').click()
    await page.getByTestId('settings-nav-logs').click()
    await expect(page.getByTestId('log-row').first()).toBeVisible()
    await page.getByTestId('logs-clear').click()
    await expect(page.getByTestId('log-row')).toHaveCount(0)
  })
})
```

- [ ] **Step 2: Run the new tests**

Run: `pnpm exec playwright test -g "Settings dialog"`
Expected: all pass. If the log-row assertion in the last test fails because the missing-defaults Writing Tools error path doesn't actually call `reportError`/logging (double check Task 6's retrofit covers this exact path — it should, `HK-3005` covers stream errors, but confirm the "no default provider configured" early-exit in `writing-tools-popover.tsx`'s `runAction` also goes through `reportError` or a different code, not a silent local-state-only error — if it's still local-only, either add a `reportError` call there too or pick a different action in this test that definitely logs something, like the unhandled-rejection trick from Task 5).

- [ ] **Step 3: Run the full e2e suite**

Run: `pnpm e2e`
Expected: all pass, including every pre-existing test.

- [ ] **Step 4: Commit**

```bash
git add e2e-tests/app.spec.ts
git commit -m "test: e2e coverage for the Settings dialog flow

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 13: Documentation sync (run LAST)

**Files:**

- Modify: `CLAUDE.md`, `README.md`

- [ ] **Step 1: Update `CLAUDE.md`**

Add a new bullet under Architecture (matching the existing bullet-per-subsystem style) covering: the `SettingsDialog` shell (sidebar-nav-in-Dialog, replacing the unused scaffold and Phase 3's `AiSettingsDialog`), its 5 sections (General/Appearance-mode-only/AI/Logs/About-static), the `reportError`/`HK-XXXX` funnel in `errors.ts` (with the new 6xxx group noted), `logger.ts`, the Rust `logging.rs` module (JSONL + rotation), and the `⌘,` shortcut. Verify every path/command claim against the actual shipped code before writing it, same discipline as every prior docs-sync task in this project (Phase 3's Task 13).

- [ ] **Step 2: Update `README.md`**

Mention Settings (vault location, appearance mode, AI keys, logs) as a shipped feature, and the `⌘,` shortcut.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md README.md
git commit -m "docs: sync docs with Settings/errors/logging (Phase 4)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Self-review notes

- **Spec coverage:** §8's 5 Settings sections → Tasks 7-11 (Appearance/About deliberately reduced per §14c). §8's `reportError`/HK-XXXX/toast funnel → Task 4. §8's `ErrorBoundary`/`onunhandledrejection` → Task 5. §8's `logger.ts`/Rust `append_log`/rotation/`read_logs` → Tasks 1, 3, 4. §14c's retrofit decision → Task 6, which turned out to cover 5 files, not the 3 named in brainstorming — a fresh grep during plan-writing (self-review, not brainstorming) turned up two more pre-existing `console.error` call sites the brainstorming discussion never surfaced: `editor-boundary.tsx`'s own, separate `EditorBoundary` (a narrower, pre-existing boundary for malformed-document rendering, distinct from Task 5's new app-wide one) and `use-copy-to-clipboard.ts`'s clipboard-copy failure path, whose own code comment literally says "no toast system exists yet (tracked separately)" — this retrofit task is exactly that tracked follow-up. §14c's shell/entry-point/shortcut decisions → Task 7. §14c's dropped voice toggle → simply absent from Task 10 (nothing to build). §4's already-named `append_log`/`read_logs`/`clear_logs` → Task 1 uses those exact names.
- **Placeholder scan:** no TBD/TODO. Two "confirm against installed source" notes (Task 2 Step 4, Task 11 Step 3) are the same class of honest, tracked verification point every prior phase's plan has used (e.g. Phase 3's `keyring`/`http:default` uncertainties) — not placeholders, since each has a concrete starting draft to verify or correct.
- **Type consistency:** `LogEntry`/`LogFilter`/`LogLevel` (Task 3, `types.ts`) are the single definitions reused identically by `logger.ts`, `errors.ts`'s log call, `logs-section.tsx`, and both Rust (`logging.rs`, camelCase via serde) and TS backends — no renamed variants across tasks. `HkErrorCode`/`reportError` (Task 4) are consumed identically by Tasks 5, 6, 8, 11. `settingsDialogOpenAtom`/`settingsDialogSectionAtom`/`openSettingsAtom`/`SettingsSection` (Task 4, `store.ts`) are the single source of truth reused by Tasks 4 (errors.ts's action), 7 (shell + title-bar), and nothing redefines them.
- **Task ordering:** Task 1 and Task 2 are independent of each other, both must land before Task 3 (which needs Task 1's commands) — Task 2 doesn't block Task 3, only Tasks 8/11 need Task 2. Task 4 depends on Task 3. Tasks 5 and 6 both depend on Task 4 but not each other. Task 7 depends on Task 4's atoms. Tasks 8-11 each depend on Task 7 (the shell) plus their own specific earlier dependency (8: Tasks 2+3; 9: none beyond 7; 10: Task 6's retrofit; 11: Tasks 1/2/3). Task 12 depends on all of 7-11. Task 13 runs last.
- **Known open verification points, flagged honestly:** the exact `@tauri-apps/plugin-dialog` `open`/`save` signatures and return shapes (Task 2, consumed by Tasks 8/11); whether `dialog:default` needs its own origin-style scope the way `http:default` surprisingly did in Phase 3 (Task 2); whether writing an exported log file needs a second plugin (`@tauri-apps/plugin-fs`) beyond `plugin-dialog`'s own `save()` (Task 11); whether `jotai`'s `getDefaultStore()` is the right way to write an atom from non-component code in this project's installed jotai version (Task 4); whether "Reveal in Finder" has a real existing command to call (Task 8); the project's actual `import.meta.env.DEV`-equivalent dev-check convention (Task 4). Each has an explicit "verify against installed/real API" instruction rather than being silently assumed.
