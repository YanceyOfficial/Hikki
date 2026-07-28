# AI Writing Tools (Phase 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an Apple-Intelligence-style "Writing Tools" popover to the editor — Proofread, Rewrite, tone chips, transforms, and Compose, backed by a real streaming AI client (OpenAI + Anthropic via `@earendil-works/pi-ai`), with a minimal Keychain-backed settings surface pulled forward from Phase 4.

**Architecture:** A thin `src/lib/ai/` layer wraps `@earendil-works/pi-ai`'s `Models` collection (real providers in the compiled app, `fauxProvider()` in dev/Playwright, mirroring the existing `TauriBackend`/`MemoryBackend` split). API keys live in the OS Keychain (new Rust `ai.rs` module, `keyring` crate) and are fetched by IPC immediately before each request — never persisted in JS state. `@tauri-apps/plugin-http`'s fetch replaces the global `window.fetch` once at startup so pi-ai's internal SDK calls bypass webview CORS. The popover is a new BlockNote formatting-toolbar entry; streamed text renders into a preview card; applying a result goes through BlockNote's standard `editor.replaceBlocks`/`insertBlocks`.

**Tech Stack:** `@earendil-works/pi-ai` (provider abstraction + streaming + faux test provider), `@tauri-apps/plugin-http` + `tauri-plugin-http` (Rust), `keyring` (Rust Keychain), `sonner` (toasts), existing BlockNote/shadcn/Jotai stack.

## Global Constraints

- API keys are Keychain-only (`keyring` crate) — never in the plain-JSON settings file, never in JS state/localStorage, never logged. Fetched fresh via IPC immediately before each AI request.
- AI-generated content is applied exclusively via BlockNote's `editor.replaceBlocks`/`editor.insertBlocks` — never raw `Doc.blocks` JSON mutation (spec §14b; keeps the door open for a future Yjs migration, itself out of scope here per spec §16).
- This phase pulls forward only what AI needs from Phase 4: Keychain commands, one small standalone API-key/default-model dialog (not the full 5-section Settings shell from spec §8), and plain `sonner` toasts for AI errors (not the full `HK-XXXX`-driven toast+logger pipeline from spec §8 — though the existing lightweight `AppError` Rust enum, already used by every command, does get one new variant for Keychain failures, per its own established `HK-XXXX` numbering).
- Two providers only for v1: OpenAI and Anthropic, via `@earendil-works/pi-ai`'s per-provider subpath factories (`@earendil-works/pi-ai/providers/openai`, `/anthropic`) — not `providers/all` (avoids bundling 20+ unused provider SDKs).
- Model IDs are never hardcoded — the model-selector dropdown and the default-model setting both read from pi-ai's own live catalog (`models.getModels(providerId)`), so the app never goes stale as providers ship new models. (This also sidesteps needing to pin an exact "current flagship" ID at plan-writing time.)
- `data-testid` on every interactive element, following this codebase's existing convention.
- IPC payloads camelCase; Rust uses `serde(rename_all = "camelCase")`.
- Rust commands follow the existing `*_impl` testable-core + `#[tauri::command]` thin-wrapper pattern (`commands.rs`).
- jsdom cannot render BlockNote — UI-level behavior (the popover, streaming, apply-to-document) is Playwright e2e; pure logic (prompt construction, client wrapper) is Vitest, using `@earendil-works/pi-ai`'s own `fauxProvider()` rather than hand-rolled mocks (this codebase's established "always use the real thing, never reinvent" rule).
- `src/components/settings-dialog.tsx` and `nav-main.tsx` are unused shadcn-template boilerplate from the original scaffold commit — do not import, extend, or reference them for anything in this plan.

---

### Task 1: Rust Keychain module + AppSettings extension

**Files:**

- Create: `src-tauri/src/ai.rs`
- Modify: `src-tauri/src/vault.rs` (extend `AppSettings`), `src-tauri/src/commands.rs` (register new commands, fix the `set_vault_path_impl` struct-literal), `src-tauri/src/error.rs` (new error variant), `src-tauri/src/lib.rs` (register the `ai` module + new commands in the invoke handler), `src-tauri/Cargo.toml` (add `keyring`)

**Interfaces:**

- Produces: `ai::get_api_key_impl(provider: &str) -> Result<Option<String>>`, `ai::set_api_key_impl(provider: &str, key: &str) -> Result<()>`, `ai::delete_api_key_impl(provider: &str) -> Result<()>`, each wrapped as `#[tauri::command]` `get_api_key`/`set_api_key`/`delete_api_key` (camelCase `provider`/`key` params). `AppSettings` gains `default_ai_provider: Option<String>` and `default_ai_model: Option<String>`. `AppError` gains a `Keychain(#[from] keyring::Error)` variant, code `"HK-3001"` (spec §8's "3xxx AI" grouping).

- [ ] **Step 1: Add the `keyring` dependency**

In `src-tauri/Cargo.toml`, add under `[dependencies]`:

```toml
keyring = "3"
```

Run `cargo build --manifest-path src-tauri/Cargo.toml` once to confirm it resolves and compiles on this machine (macOS Keychain backend) before writing any code against it — the exact patch version isn't pinned here, let cargo pick the latest `3.x` and note in your report which version it resolved to.

- [ ] **Step 2: Write the failing Rust tests**

In `src-tauri/src/ai.rs`:

```rust
use keyring::Entry;

use crate::error::{AppError, Result};

const SERVICE: &str = "com.hikki.app.ai";

pub fn get_api_key_impl(provider: &str) -> Result<Option<String>> {
    let entry = Entry::new(SERVICE, provider)?;
    match entry.get_password() {
        Ok(key) => Ok(Some(key)),
        Err(keyring::Error::NoEntry) => Ok(None),
        Err(e) => Err(e.into()),
    }
}

pub fn set_api_key_impl(provider: &str, key: &str) -> Result<()> {
    let entry = Entry::new(SERVICE, provider)?;
    entry.set_password(key)?;
    Ok(())
}

pub fn delete_api_key_impl(provider: &str) -> Result<()> {
    let entry = Entry::new(SERVICE, provider)?;
    match entry.delete_credential() {
        Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
        Err(e) => Err(e.into()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Keychain tests use a unique provider-id-per-test (not a fixed constant)
    // so parallel `cargo test` runs never collide on the same real Keychain
    // entry, and each test cleans up its own entry when done.
    fn unique_provider(tag: &str) -> String {
        format!("test-{tag}-{}", std::process::id())
    }

    #[test]
    fn get_missing_key_returns_none() {
        let provider = unique_provider("missing");
        assert_eq!(get_api_key_impl(&provider).unwrap(), None);
    }

    #[test]
    fn set_then_get_round_trips() {
        let provider = unique_provider("roundtrip");
        set_api_key_impl(&provider, "sk-test-123").unwrap();
        assert_eq!(get_api_key_impl(&provider).unwrap(), Some("sk-test-123".to_string()));
        delete_api_key_impl(&provider).unwrap();
    }

    #[test]
    fn delete_is_idempotent() {
        let provider = unique_provider("delete-idempotent");
        set_api_key_impl(&provider, "sk-test-456").unwrap();
        delete_api_key_impl(&provider).unwrap();
        delete_api_key_impl(&provider).unwrap(); // second delete must not error
        assert_eq!(get_api_key_impl(&provider).unwrap(), None);
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cargo test --manifest-path src-tauri/Cargo.toml ai::`
Expected: FAIL — `error.rs` doesn't have a `From<keyring::Error>` conversion yet (compile error), or the module isn't registered in `lib.rs` yet. Confirm the actual failure reason before moving on (should be a compile error referencing `AppError`/`keyring::Error`, not a runtime assertion failure).

- [ ] **Step 4: Add the `Keychain` error variant**

In `src-tauri/src/error.rs`, add to the `AppError` enum:

```rust
    #[error("keychain error: {0}")]
    Keychain(#[from] keyring::Error),
```

And to `AppError::code`:

```rust
            AppError::Keychain(_) => "HK-3001",
```

- [ ] **Step 5: Register the module and run tests again**

In `src-tauri/src/lib.rs`, add `mod ai;` near the other `mod` declarations. Run: `cargo test --manifest-path src-tauri/Cargo.toml ai::`
Expected: PASS (3 tests).

- [ ] **Step 6: Extend `AppSettings` and fix the now-incomplete struct literal**

In `src-tauri/src/vault.rs`, change the struct:

```rust
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct AppSettings {
    pub vault_path: PathBuf,
    #[serde(default)]
    pub default_ai_provider: Option<String>,
    #[serde(default)]
    pub default_ai_model: Option<String>,
}
```

`#[serde(default)]` on both new fields is required, not optional — without it, every pre-existing `settings.json` on disk from before this change (missing these keys) would fail to deserialize on load, exactly the same class of backward-compatibility break already fixed once for `Document.threads` in the previous phase. Update the two existing struct-literal construction sites this change breaks — `load_settings`'s fallback:

```rust
        .unwrap_or_else(|| AppSettings {
            vault_path: default_vault_path(),
            default_ai_provider: None,
            default_ai_model: None,
        })
```

and, in `commands.rs`'s `set_vault_path_impl`, preserve the _existing_ AI settings rather than resetting them when only the vault path changes:

```rust
    {
        let mut settings = lock(&state.settings);
        let candidate = AppSettings { vault_path: new_root, ..settings.clone() };
        vault::save_settings(&state.app_data_dir, &candidate)?;
        *settings = candidate;
    }
```

Run `cargo build --manifest-path src-tauri/Cargo.toml` and let the compiler find any other struct-literal construction site you missed (grep for `AppSettings {` across `src-tauri/src/*.rs` first, then let `cargo check`'s own errors confirm you got them all — don't guess which ones need updating).

- [ ] **Step 7: Update the two existing `vault.rs` tests for the new fields**

`load_settings_defaults_when_missing` and `settings_round_trip` (in `vault.rs`'s own `#[cfg(test)]` module) construct `AppSettings` literals directly — update both to include the two new fields (`None` for both is fine, these tests aren't about AI settings specifically).

- [ ] **Step 8: Add the IPC command wrappers**

In `src-tauri/src/commands.rs`:

```rust
#[tauri::command]
pub fn get_api_key(provider: String) -> Result<Option<String>> {
    crate::ai::get_api_key_impl(&provider)
}

#[tauri::command]
pub fn set_api_key(provider: String, key: String) -> Result<()> {
    crate::ai::set_api_key_impl(&provider, &key)
}

#[tauri::command]
pub fn delete_api_key(provider: String) -> Result<()> {
    crate::ai::delete_api_key_impl(&provider)
}

pub fn save_ai_settings_impl(
    state: &AppState,
    default_ai_provider: Option<String>,
    default_ai_model: Option<String>,
) -> Result<AppSettings> {
    let mut settings = lock(&state.settings);
    let candidate = AppSettings { default_ai_provider, default_ai_model, ..settings.clone() };
    vault::save_settings(&state.app_data_dir, &candidate)?;
    *settings = candidate.clone();
    Ok(candidate)
}

#[tauri::command]
pub fn save_ai_settings(
    state: State<AppState>,
    default_ai_provider: Option<String>,
    default_ai_model: Option<String>,
) -> Result<AppSettings> {
    save_ai_settings_impl(&state, default_ai_provider, default_ai_model)
}

#[tauri::command]
pub fn get_ai_settings(state: State<AppState>) -> Result<AppSettings> {
    Ok(lock(&state.settings).clone())
}
```

Find wherever `lib.rs` registers the existing commands in `tauri::generate_handler![...]` and add `get_api_key, set_api_key, delete_api_key, save_ai_settings, get_ai_settings` to that list — read the exact current macro invocation first rather than guessing its formatting.

- [ ] **Step 9: Write a test for `save_ai_settings_impl`**

In `commands.rs`'s existing `#[cfg(test)]` module (it already has a `state()` helper building a real `AppState` in a tempdir — reuse it):

```rust
    #[test]
    fn save_ai_settings_impl_persists_and_preserves_vault_path() {
        let (_vault_dir, _data_dir, state) = state();
        let before_vault_path = lock(&state.settings).vault_path.clone();

        let updated = save_ai_settings_impl(
            &state,
            Some("anthropic".to_string()),
            Some("claude-test-model".to_string()),
        )
        .unwrap();

        assert_eq!(updated.default_ai_provider, Some("anthropic".to_string()));
        assert_eq!(updated.default_ai_model, Some("claude-test-model".to_string()));
        assert_eq!(updated.vault_path, before_vault_path);

        // Reloading from disk must see the same values.
        let reloaded = vault::load_settings(&state.app_data_dir);
        assert_eq!(reloaded.default_ai_provider, Some("anthropic".to_string()));
    }
```

- [ ] **Step 10: Run the full Rust suite**

Run: `cargo test --manifest-path src-tauri/Cargo.toml`
Expected: all pass (existing tests + the new `ai::` tests + the new `save_ai_settings_impl` test), no warnings about unused fields.

- [ ] **Step 11: Commit**

```bash
git add src-tauri
git commit -m "feat(rust): Keychain-backed AI API key storage + AppSettings extension

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: `@tauri-apps/plugin-http` wiring (Rust + JS + capability + global fetch patch)

**Depends on:** none (independent of Task 1).

**Files:**

- Modify: `src-tauri/Cargo.toml`, `src-tauri/src/lib.rs`, `src-tauri/capabilities/default.json`, `package.json`, `src/main.tsx`

**Interfaces:**

- Produces: at app startup (inside the real Tauri app only), `window.fetch` is replaced with `@tauri-apps/plugin-http`'s `fetch`, so any library calling the ambient global `fetch` (including `@earendil-works/pi-ai`'s internal provider SDKs, added in Task 4) transparently routes through Tauri's native HTTP client, bypassing webview CORS restrictions. In plain-browser dev/Playwright mode (`isTauri()` false), the global `fetch` is left untouched.

- [ ] **Step 1: Add the Rust plugin dependency and register it**

In `src-tauri/Cargo.toml`, add under `[dependencies]`:

```toml
tauri-plugin-http = "2"
```

In `src-tauri/src/lib.rs`, find the existing `.plugin(tauri_plugin_opener::init())` call in the `tauri::Builder` chain and add a sibling line directly after it:

```rust
        .plugin(tauri_plugin_http::init())
```

Run `cargo build --manifest-path src-tauri/Cargo.toml` to confirm it compiles.

- [ ] **Step 2: Add the HTTP permission to the app's capability**

Read `src-tauri/capabilities/default.json` first (it currently lists `"permissions": ["core:default", "opener:default"]`). Add `"http:default"` to that array. After building once (Step 1 already did this), check `src-tauri/gen/schemas/` for an `http`-related permission schema file that was generated — if the plugin's actual permission identifier differs from `"http:default"` (e.g. it requires a scoped `http:allow-fetch` with an explicit URL allow-list for `api.openai.com`/`api.anthropic.com`), use the real identifier/scope found there instead of guessing. Document whichever you actually needed in your report.

- [ ] **Step 3: Add the JS dependency**

```bash
pnpm add @tauri-apps/plugin-http
```

- [ ] **Step 4: Replace the global fetch at bootstrap**

In `src/main.tsx`, before the `ReactDOM.createRoot(...).render(...)` call, add:

```tsx
import { fetch as tauriFetch } from '@tauri-apps/plugin-http'

import { isTauri } from '#lib/backend/index'

if (isTauri()) {
  window.fetch = tauriFetch as unknown as typeof window.fetch
}
```

Place the import alongside the existing imports at the top of the file, and this block after the imports but before `const router = ...`.

- [ ] **Step 5: Verify live in the real Tauri app**

This specific change (a native window's actual HTTP behavior) cannot be meaningfully verified by an automated test — jsdom/Playwright's dev-server mode never executes the `isTauri()` branch at all. Run `pnpm tauri dev`, and once Task 4/6 land later in this plan and there's a real AI request to trigger, confirm live that a request to `api.anthropic.com` or `api.openai.com` actually succeeds (no CORS error in the webview's dev console) — note in your report that you deferred this specific live check to whichever later task first makes a real network call, since there's nothing to observably test yet at this point in the plan. Do still run `pnpm dev` (browser mode) and confirm the app loads with no console errors (confirming the `isTauri()` guard correctly no-ops in plain-browser mode).

- [ ] **Step 6: Run the full frontend check set**

Run: `pnpm test && pnpm exec tsc --noEmit`
Expected: all green (this task adds no new frontend logic to unit-test yet, just the bootstrap wiring).

- [ ] **Step 7: Commit**

```bash
git add src-tauri package.json pnpm-lock.yaml src/main.tsx
git commit -m "feat: wire up tauri-plugin-http and replace global fetch in the Tauri app

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Extend the `Backend` abstraction with AI key/settings IPC

**Depends on:** Task 1 (the Rust commands this task's `TauriBackend` implementation calls).

**Files:**

- Modify: `src/lib/backend/backend.ts`, `src/lib/backend/tauri-backend.ts`, `src/lib/backend/memory-backend.ts`
- Test: `src/lib/backend/memory-backend.test.ts` (check if this file already exists — if not, check whichever existing test file covers `MemoryBackend`'s other methods and follow its pattern)

**Interfaces:**

- Produces: `Backend` gains `getApiKey(provider: string): Promise<string | null>`, `setApiKey(provider: string, key: string): Promise<void>`, `deleteApiKey(provider: string): Promise<void>`, `getAiSettings(): Promise<AiSettings>`, `saveAiSettings(settings: AiSettings): Promise<AiSettings>`, where `AiSettings = { defaultAiProvider: string | null; defaultAiModel: string | null }` (new type, add it to `src/lib/types.ts` alongside the existing `Doc`/`DocumentMeta` types).

This is the **only** place in the frontend allowed to reach these IPC calls — per this codebase's existing rule ("Never call `invoke` outside `src/lib/backend/`"), nothing in `src/lib/ai/` (Task 4 onward) may call `@tauri-apps/api/core`'s `invoke` directly; it must go through `backend`.

- [ ] **Step 1: Add the type and interface methods**

In `src/lib/types.ts`, add:

```ts
export interface AiSettings {
  defaultAiProvider: string | null
  defaultAiModel: string | null
}
```

In `src/lib/backend/backend.ts`, add to the `Backend` interface:

```ts
  getApiKey(provider: string): Promise<string | null>
  setApiKey(provider: string, key: string): Promise<void>
  deleteApiKey(provider: string): Promise<void>
  getAiSettings(): Promise<AiSettings>
  saveAiSettings(settings: AiSettings): Promise<AiSettings>
```

(Add `AiSettings` to the existing `import type { ... } from '#lib/types'` line at the top of the file.)

- [ ] **Step 2: Implement in `TauriBackend`**

In `src/lib/backend/tauri-backend.ts`, add:

```ts
  getApiKey(provider: string) {
    return invoke<string | null>('get_api_key', { provider })
  }
  setApiKey(provider: string, key: string) {
    return invoke<void>('set_api_key', { provider, key })
  }
  deleteApiKey(provider: string) {
    return invoke<void>('delete_api_key', { provider })
  }
  getAiSettings() {
    return invoke<AiSettings>('get_ai_settings')
  }
  saveAiSettings(settings: AiSettings) {
    return invoke<AiSettings>('save_ai_settings', {
      defaultAiProvider: settings.defaultAiProvider,
      defaultAiModel: settings.defaultAiModel
    })
  }
```

(Add `AiSettings` to the existing type import at the top of the file.)

- [ ] **Step 3: Write the failing test for `MemoryBackend`**

Check whether a test file for `MemoryBackend` already exists (`ls src/lib/backend/*.test.ts`) — if one covers similar methods, add to it; otherwise create `src/lib/backend/memory-backend.test.ts` following the existing test style used elsewhere in this codebase (plain Vitest, no React Testing Library needed here). Test:

```ts
import { beforeEach, expect, test } from 'vitest'

import { MemoryBackend } from '#lib/backend/memory-backend'

let backend: MemoryBackend

beforeEach(() => {
  backend = new MemoryBackend()
})

test('api key round-trips through set/get/delete', async () => {
  expect(await backend.getApiKey('openai')).toBeNull()
  await backend.setApiKey('openai', 'sk-test-123')
  expect(await backend.getApiKey('openai')).toBe('sk-test-123')
  await backend.deleteApiKey('openai')
  expect(await backend.getApiKey('openai')).toBeNull()
})

test('ai settings persist in memory across calls', async () => {
  const initial = await backend.getAiSettings()
  expect(initial).toEqual({ defaultAiProvider: null, defaultAiModel: null })

  const saved = await backend.saveAiSettings({
    defaultAiProvider: 'anthropic',
    defaultAiModel: 'claude-test'
  })
  expect(saved).toEqual({
    defaultAiProvider: 'anthropic',
    defaultAiModel: 'claude-test'
  })
  expect(await backend.getAiSettings()).toEqual(saved)
})
```

- [ ] **Step 4: Run the test to verify it fails**

Run: `pnpm test memory-backend`
Expected: FAIL — `MemoryBackend` doesn't implement the new `Backend` members yet (TypeScript compile error surfaced through Vitest, or a runtime "is not a function").

- [ ] **Step 5: Implement in `MemoryBackend`**

Read `src/lib/backend/memory-backend.ts` in full first to match its existing style (likely a class with in-memory `Map`/plain fields backing each piece of state). Add:

```ts
  #apiKeys = new Map<string, string>()
  #aiSettings: AiSettings = { defaultAiProvider: null, defaultAiModel: null }

  async getApiKey(provider: string) {
    return this.#apiKeys.get(provider) ?? null
  }
  async setApiKey(provider: string, key: string) {
    this.#apiKeys.set(provider, key)
  }
  async deleteApiKey(provider: string) {
    this.#apiKeys.delete(provider)
  }
  async getAiSettings() {
    return this.#aiSettings
  }
  async saveAiSettings(settings: AiSettings) {
    this.#aiSettings = settings
    return this.#aiSettings
  }
```

Adjust the exact private-field syntax if this file uses a different convention than `#private` fields (check how it currently stores other in-memory state, e.g. documents, and match that pattern instead if it differs).

- [ ] **Step 6: Run tests to verify they pass**

Run: `pnpm test memory-backend && pnpm exec tsc --noEmit`
Expected: PASS, clean.

- [ ] **Step 7: Commit**

```bash
git add src/lib
git commit -m "feat: extend Backend with Keychain-backed AI key/settings IPC

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: `pi-ai` Models collection + dev/test faux-provider split

**Depends on:** Task 3 (`backend.getApiKey` used here).

**Files:**

- Create: `src/lib/ai/models.ts`, `src/lib/ai/models.test.ts`
- Modify: `package.json`

**Interfaces:**

- Consumes: `backend.getApiKey(provider)` from Task 3.
- Produces: `getAiModels(): Models` — a **module-level lazy singleton** (mirrors `backend/index.ts`'s own `export const backend: Backend = ...` singleton pattern), so every caller across the app (Task 6's client, Task 8's settings dialog, Task 11's popover) shares the exact same `Models` collection and, in dev/test mode, the exact same faux-provider instance within one session — not a fresh, independent faux provider per call site. `AI_PROVIDER_IDS = ['openai', 'anthropic'] as const`, `type AiProviderId = (typeof AI_PROVIDER_IDS)[number]`. Test-only exports: `__resetAiModelsForTesting()` (clears the cached singleton so the next `getAiModels()` call builds a fresh collection — call this in every test file's `beforeEach` that touches AI models, so one test's scripted faux response can never leak into another) and `__getFauxProviderForTesting()` (returns the current cached faux-provider handle so tests can call its `.setResponses(...)` — throws if called in a context where `getAiModels()` hasn't registered a faux provider, e.g. if `isTauri()` were somehow true in a test). Later tasks (5, 6, 8, 11) import `getAiModels`/`AiProviderId` from this file — do not duplicate the provider-id list elsewhere.

- [ ] **Step 1: Install dependencies**

```bash
pnpm add @earendil-works/pi-ai
```

Read the actual installed package's exported members (check `node_modules/@earendil-works/pi-ai/package.json`'s `exports` map, and skim its type declarations) to confirm the exact import paths (`@earendil-works/pi-ai/providers/openai`, `@earendil-works/pi-ai/providers/anthropic`, and the core `createModels`/`fauxProvider` exports from the package root) match what's described below — adjust if the installed version's API surface differs from what's documented here.

- [ ] **Step 2: Write the failing test**

Create `src/lib/ai/models.test.ts`:

```ts
import { beforeEach, expect, test } from 'vitest'

import {
  getAiModels,
  __getFauxProviderForTesting,
  __resetAiModelsForTesting
} from '#lib/ai/models'

beforeEach(() => {
  __resetAiModelsForTesting()
})

test('dev/test mode registers a faux provider with at least one model', () => {
  const models = getAiModels()
  const providers = models.getProviders()
  expect(providers.length).toBeGreaterThan(0)

  const allModels = models.getModels()
  expect(allModels.length).toBeGreaterThan(0)
})

test('repeated calls within a session return the same collection instance', () => {
  expect(getAiModels()).toBe(getAiModels())
})

test('the faux provider handle is reachable for scripting responses', () => {
  getAiModels() // ensure the singleton (and its faux provider) is initialized
  const faux = __getFauxProviderForTesting()
  expect(typeof faux.setResponses).toBe('function')
})
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `pnpm test models.test`
Expected: FAIL — module doesn't exist yet.

- [ ] **Step 4: Implement `getAiModels`**

Create `src/lib/ai/models.ts`:

```ts
import {
  createModels,
  fauxProvider,
  type FauxProvider,
  type Models
} from '@earendil-works/pi-ai'
import { anthropicProvider } from '@earendil-works/pi-ai/providers/anthropic'
import { openaiProvider } from '@earendil-works/pi-ai/providers/openai'

import { isTauri } from '#lib/backend/index'

export const AI_PROVIDER_IDS = ['openai', 'anthropic'] as const
export type AiProviderId = (typeof AI_PROVIDER_IDS)[number]

// Module-level lazy singleton - mirrors `backend/index.ts`'s own singleton
// pattern - so every call site (the AI client, the settings dialog, the
// popover) shares one `Models` collection, and in dev/test mode, one faux
// provider instance, rather than each independently creating its own
// isolated (and in the faux case, unscriptable-from-outside) collection.
let cachedModels: Models | undefined
let cachedFaux: FauxProvider | undefined

export function getAiModels(): Models {
  if (cachedModels) return cachedModels

  const models = createModels()

  if (isTauri()) {
    models.setProvider(openaiProvider())
    models.setProvider(anthropicProvider())
  } else {
    // Dev server (pnpm dev) and Playwright e2e both run in plain-browser
    // mode, never inside the real Tauri app - real provider API calls would
    // need real API keys and would hit real, billed endpoints from CI/local
    // dev. The faux provider gives real streaming semantics (text_delta,
    // done, error - the same event shapes the UI code handles) with
    // deterministic, scripted, free responses instead.
    cachedFaux = fauxProvider()
    models.setProvider(cachedFaux.provider)
  }

  cachedModels = models
  return models
}

/** Test-only: clears the cached singleton so the next getAiModels() call builds a fresh collection (and, in non-Tauri mode, a fresh faux provider) - call in beforeEach so scripted responses never leak between tests. */
export function __resetAiModelsForTesting() {
  cachedModels = undefined
  cachedFaux = undefined
}

/** Test-only: the current cached faux-provider handle, for scripting responses via `.setResponses(...)`. Call `getAiModels()` at least once first (directly or indirectly) so the singleton - and its faux provider - actually exists. Throws if the cached instance is running in real-provider (Tauri) mode. */
export function __getFauxProviderForTesting(): FauxProvider {
  if (!cachedFaux) {
    throw new Error(
      '__getFauxProviderForTesting() called with no cached faux provider - call getAiModels() first, and confirm this is not running in Tauri mode'
    )
  }
  return cachedFaux
}
```

Confirm `FauxProvider` (or whatever the real installed type is actually called — `fauxProvider()`'s return type) is genuinely exported from `@earendil-works/pi-ai`'s package root; adjust the import/type name if the installed version calls it something else.

- [ ] **Step 5: Run tests to verify they pass**

Run: `pnpm test models.test && pnpm exec tsc --noEmit`
Expected: PASS, clean.

- [ ] **Step 6: Commit**

```bash
git add src/lib/ai package.json pnpm-lock.yaml
git commit -m "feat: pi-ai Models collection with dev/test faux-provider split

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Prompt templates for each Writing Tools action

**Depends on:** none (pure functions, no pi-ai/BlockNote dependency).

**Files:**

- Create: `src/lib/ai/prompts.ts`, `src/lib/ai/prompts.test.ts`

**Interfaces:**

- Produces: `type WritingToolAction = { kind: 'proofread' | 'rewrite' | 'tone'; tone?: 'friendly' | 'professional' | 'concise' } | { kind: 'transform'; transform: 'summary' | 'keyPoints' | 'list' | 'table' } | { kind: 'compose'; instruction: string } | { kind: 'custom'; instruction: string }` and `buildContext(action: WritingToolAction, selectedText: string): Context` (returns a pi-ai `Context` object — `{ systemPrompt, messages }` — ready to pass to `models.stream()`/`models.complete()`). Task 6 imports both from this file.

- [ ] **Step 1: Write the failing tests**

Create `src/lib/ai/prompts.test.ts`:

```ts
import { expect, test } from 'vitest'

import { buildContext } from '#lib/ai/prompts'

test('proofread builds a context asking to correct the given text', () => {
  const context = buildContext({ kind: 'proofread' }, 'Its a nice day.')
  expect(context.messages).toHaveLength(1)
  expect(context.messages[0].role).toBe('user')
  const content = context.messages[0].content
  expect(typeof content === 'string' ? content : '').toContain(
    'Its a nice day.'
  )
  expect(context.systemPrompt?.toLowerCase()).toContain('proofread')
})

test('tone chip includes the requested tone in the system prompt', () => {
  const context = buildContext(
    { kind: 'tone', tone: 'friendly' },
    'Please respond promptly.'
  )
  expect(context.systemPrompt?.toLowerCase()).toContain('friendly')
})

test('transform includes the requested transform kind', () => {
  const context = buildContext(
    { kind: 'transform', transform: 'keyPoints' },
    'Long paragraph here.'
  )
  expect(context.systemPrompt?.toLowerCase()).toContain('key points')
})

test('compose uses the free-form instruction, not selected text, as the prompt', () => {
  const context = buildContext(
    { kind: 'compose', instruction: 'Write a haiku about oceans' },
    ''
  )
  const content = context.messages[0].content
  expect(typeof content === 'string' ? content : '').toContain(
    'haiku about oceans'
  )
})

test('custom uses the free-form instruction alongside the selected text', () => {
  const context = buildContext(
    { kind: 'custom', instruction: 'Make this sound more excited' },
    'The meeting is at 3pm.'
  )
  const content = context.messages[0].content
  const text = typeof content === 'string' ? content : ''
  expect(text).toContain('more excited')
  expect(text).toContain('The meeting is at 3pm.')
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pnpm test prompts.test`
Expected: FAIL — module doesn't exist.

- [ ] **Step 3: Implement**

Create `src/lib/ai/prompts.ts`. Read `@earendil-works/pi-ai`'s `Context`/`Message` type declarations first (installed in Task 4) to confirm the exact shape expected for `messages[].content` (the tests above assume it can be a plain string, matching the Quick Start example in pi-ai's own README — confirm this against the actually-installed version's types before finalizing) and `timestamp` field if required. Implementation:

```ts
import type { Context } from '@earendil-works/pi-ai'

export type WritingToolAction =
  | { kind: 'proofread' }
  | { kind: 'rewrite' }
  | { kind: 'tone'; tone: 'friendly' | 'professional' | 'concise' }
  | { kind: 'transform'; transform: 'summary' | 'keyPoints' | 'list' | 'table' }
  | { kind: 'compose'; instruction: string }
  | { kind: 'custom'; instruction: string }

const TRANSFORM_LABEL: Record<
  Extract<WritingToolAction, { kind: 'transform' }>['transform'],
  string
> = {
  summary: 'a short summary',
  keyPoints: 'a bulleted list of key points',
  list: 'a plain bulleted list',
  table: 'a markdown table'
}

function systemPromptFor(action: WritingToolAction): string {
  switch (action.kind) {
    case 'proofread':
      return 'You are a careful proofreader. Fix grammar, spelling, and punctuation errors in the given text. Preserve the original meaning and tone. Reply with only the corrected text, no explanation.'
    case 'rewrite':
      return 'You are a skilled editor. Rewrite the given text to improve clarity and flow while preserving its original meaning. Reply with only the rewritten text, no explanation.'
    case 'tone':
      return `You are a skilled editor. Rewrite the given text in a more ${action.tone} tone, preserving its meaning. Reply with only the rewritten text, no explanation.`
    case 'transform':
      return `You are a skilled editor. Transform the given text into ${TRANSFORM_LABEL[action.transform]}. Reply with only the transformed content, no explanation.`
    case 'compose':
      return 'You are a helpful writing assistant. Write new content based on the instruction given. Reply with only the composed content, no explanation.'
    case 'custom':
      return 'You are a skilled editor. Apply the requested change to the given text, preserving its meaning unless the instruction says otherwise. Reply with only the edited text, no explanation.'
  }
}

function userMessageFor(
  action: WritingToolAction,
  selectedText: string
): string {
  if (action.kind === 'compose') {
    return action.instruction
  }
  if (action.kind === 'custom') {
    return `${action.instruction}\n\n---\n\n${selectedText}`
  }
  return selectedText
}

export function buildContext(
  action: WritingToolAction,
  selectedText: string
): Context {
  return {
    systemPrompt: systemPromptFor(action),
    messages: [
      {
        role: 'user',
        content: userMessageFor(action, selectedText),
        timestamp: Date.now()
      }
    ]
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pnpm test prompts.test && pnpm exec tsc --noEmit`
Expected: PASS, clean. If `Context`'s real installed type requires `content` to be an array of content blocks rather than a plain string, adjust `userMessageFor`'s return type and the message shape accordingly (wrap in `[{ type: 'text', text: ... }]`) and update the tests' `content` assertions to match — state in your report which shape the installed version actually required.

- [ ] **Step 5: Commit**

```bash
git add src/lib/ai
git commit -m "feat: prompt templates for each Writing Tools action

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Streaming AI client wrapper

**Depends on:** Task 3 (`backend.getApiKey`/`getAiSettings`), Task 4 (`getAiModels`, `AiProviderId`), Task 5 (`buildContext`, `WritingToolAction`).

**Files:**

- Create: `src/lib/ai/client.ts`, `src/lib/ai/client.test.ts`

**Interfaces:**

- Produces: `type WritingToolStreamEvent = { type: 'delta'; text: string } | { type: 'done' } | { type: 'error'; message: string }`, `async function* streamWritingTool(action: WritingToolAction, selectedText: string, options: { provider: AiProviderId; modelId: string }): AsyncGenerator<WritingToolStreamEvent>`. Task 10/11 (the popover UI) consumes this generator directly.

- [ ] **Step 1: Write the failing tests**

Create `src/lib/ai/client.test.ts`. `models.ts` (Task 4) already exposes `__resetAiModelsForTesting()`/`__getFauxProviderForTesting()` for exactly this purpose — script the response through the faux handle, then call `streamWritingTool` normally (it reaches the same cached `Models` singleton internally):

```ts
import { fauxAssistantMessage, fauxText } from '@earendil-works/pi-ai'
import { beforeEach, expect, test, vi } from 'vitest'

vi.mock('#lib/backend/index', () => ({
  backend: { getApiKey: vi.fn().mockResolvedValue('sk-test-key') },
  isTauri: () => false
}))

import {
  getAiModels,
  __getFauxProviderForTesting,
  __resetAiModelsForTesting
} from '#lib/ai/models'
import { streamWritingTool } from '#lib/ai/client'

beforeEach(() => {
  __resetAiModelsForTesting()
})

async function collect(
  action: Parameters<typeof streamWritingTool>[0],
  text: string
) {
  const events = []
  const modelId = getAiModels().getModels()[0].id
  for await (const event of streamWritingTool(action, text, {
    provider: 'openai',
    modelId
  })) {
    events.push(event)
  }
  return events
}

test('streams text deltas then a done event', async () => {
  getAiModels() // initialize the singleton (and its faux provider) first
  __getFauxProviderForTesting().setResponses([
    fauxAssistantMessage([fauxText('Corrected text.')])
  ])

  const events = await collect({ kind: 'proofread' }, 'some text')
  expect(events.some((e) => e.type === 'delta')).toBe(true)
  expect(events.at(-1)).toEqual({ type: 'done' })
  expect(
    events
      .filter((e) => e.type === 'delta')
      .map((e) => (e as { type: 'delta'; text: string }).text)
      .join('')
  ).toBe('Corrected text.')
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pnpm test client.test`
Expected: FAIL — `client.ts` doesn't exist yet.

- [ ] **Step 3: Implement**

Create `src/lib/ai/client.ts`. Read `@earendil-works/pi-ai`'s actual streamed-event union type (the Quick Start example in its README enumerates `start`/`text_start`/`text_delta`/`text_end`/`thinking_*`/`toolcall_*`/`done`/`error` — confirm this against the installed version's type declarations) before finalizing the mapping below:

```ts
import { getAiModels } from '#lib/ai/models'
import { buildContext, type WritingToolAction } from '#lib/ai/prompts'
import { backend } from '#lib/backend/index'
import type { AiProviderId } from '#lib/ai/models'

export type WritingToolStreamEvent =
  | { type: 'delta'; text: string }
  | { type: 'done' }
  | { type: 'error'; message: string }

export async function* streamWritingTool(
  action: WritingToolAction,
  selectedText: string,
  options: { provider: AiProviderId; modelId: string }
): AsyncGenerator<WritingToolStreamEvent> {
  const models = getAiModels()
  const model = models.getModel(options.provider, options.modelId)
  if (!model) {
    yield {
      type: 'error',
      message: `Model not found: ${options.provider}/${options.modelId}`
    }
    return
  }

  const apiKey = await backend.getApiKey(options.provider)
  if (!apiKey) {
    yield {
      type: 'error',
      message: `No API key configured for ${options.provider}`
    }
    return
  }

  const context = buildContext(action, selectedText)

  try {
    const stream = models.stream(model, context, { apiKey })
    for await (const event of stream) {
      if (event.type === 'text_delta') {
        yield { type: 'delta', text: event.delta }
      } else if (event.type === 'error') {
        yield { type: 'error', message: event.error.errorMessage }
        return
      } else if (event.type === 'done') {
        yield { type: 'done' }
        return
      }
    }
  } catch (err) {
    yield {
      type: 'error',
      message: err instanceof Error ? err.message : String(err)
    }
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pnpm test client.test && pnpm exec tsc --noEmit`
Expected: PASS, clean.

- [ ] **Step 5: Add an error-path test**

Add to `client.test.ts`: a test that mocks `backend.getApiKey` to resolve `null` (no key configured) and asserts `streamWritingTool` yields exactly one `{ type: 'error', ... }` event mentioning the missing key, with no `delta`/`done` events before it.

- [ ] **Step 6: Run all client tests**

Run: `pnpm test client.test`
Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add src/lib/ai
git commit -m "feat: streaming AI client wrapper over pi-ai

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: Sonner toaster wiring

**Depends on:** none.

**Files:**

- Modify: `src/components/app-shell.tsx`, `package.json`

**Interfaces:**

- Produces: a single `<Toaster />` mounted in `AppShell`, and `toast` (re-exported from `sonner`) available for Task 11 to call on AI request failures.

- [ ] **Step 1: Install shadcn's sonner component**

```bash
pnpm dlx shadcn@latest add sonner
```

This should add `sonner` to `package.json` and generate `src/components/ui/sonner.tsx` (a themed wrapper matching this app's existing shadcn component conventions) — confirm both happened; if the generated wrapper needs this app's `next-themes` integration wired in (check the generated file for a `useTheme` import expecting a specific hook shape), verify it matches `#components/theme-provider`'s actual exports.

- [ ] **Step 2: Mount it in `AppShell`**

In `src/components/app-shell.tsx`, import the generated `Toaster` component and render it once, as a sibling of the existing `SidebarProvider` content (not nested inside the scrollable `page-content` div):

```tsx
import { Toaster } from '#components/ui/sonner'
```

Add `<Toaster />` as the last child of the outermost returned element.

- [ ] **Step 3: Write a smoke test**

Check whether `app-shell.tsx` already has a test file (`src/components/app-shell.test.tsx`) — if so, add a case confirming `<Toaster />`'s container renders (sonner typically renders a `<section>`/`<ol>` landmark you can query by role or a stable class — check the generated component for what's queryable); if no test file exists for `app-shell.tsx` today, don't create one just for this — a visual/manual check is enough for a single `<Toaster/>` mount, consistent with this codebase not unit-testing pure layout-shell components elsewhere.

- [ ] **Step 4: Run the check set**

Run: `pnpm test && pnpm exec tsc --noEmit`
Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add src/components package.json pnpm-lock.yaml
git commit -m "feat: add sonner toaster to AppShell

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: Minimal AI settings dialog

**Depends on:** Task 3 (backend AI methods), Task 4 (`getAiModels`/`AI_PROVIDER_IDS`), Task 7 (toasts for save-error feedback).

**Files:**

- Create: `src/components/ai-settings-dialog.tsx`, `src/components/ai-settings-dialog.test.tsx`
- Modify: `src/components/title-bar.tsx` (entry point — see Step 5)

**Interfaces:**

- Produces: `AiSettingsDialog` component (self-contained: owns its own `Dialog`/`open` state, no props needed) rendering per-provider API key inputs (masked, save individually), a default-provider/default-model selector sourced from `getAiModels()`'s live catalog, and a "Test connection" button per provider that runs one cheap `models.complete()` call.

This is deliberately **not** the 5-section Settings shell from spec §8 — a single small dialog, matching the "minimal Phase-4 pull-forward" scope from spec §14b. Do not build navigation/section infrastructure here; that's Phase 4's job.

- [ ] **Step 1: Write the failing test**

Create `src/components/ai-settings-dialog.test.tsx` (React Testing Library, following this codebase's existing component-test conventions — check a similar existing test file, e.g. `page-header.test.tsx`, for the exact render/query helpers already in use):

```tsx
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { test, expect } from 'vitest'

import { AiSettingsDialog } from '#components/ai-settings-dialog'
import { backend } from '#lib/backend/index'

test('saving an API key persists it through the backend', async () => {
  render(<AiSettingsDialog />)
  await userEvent.click(screen.getByTestId('ai-settings-trigger'))

  const openaiKeyInput = await screen.findByTestId('ai-settings-key-openai')
  await userEvent.type(openaiKeyInput, 'sk-test-key')
  await userEvent.click(screen.getByTestId('ai-settings-save-openai'))

  await waitFor(async () => {
    expect(await backend.getApiKey('openai')).toBe('sk-test-key')
  })
})

test('changing the default model persists through the backend', async () => {
  render(<AiSettingsDialog />)
  await userEvent.click(screen.getByTestId('ai-settings-trigger'))

  const modelSelect = await screen.findByTestId('ai-settings-default-model')
  await userEvent.selectOptions(
    modelSelect,
    modelSelect.querySelectorAll('option')[1] as HTMLOptionElement
  )

  await waitFor(async () => {
    const settings = await backend.getAiSettings()
    expect(settings.defaultAiModel).not.toBeNull()
  })
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pnpm test ai-settings-dialog`
Expected: FAIL — component doesn't exist.

- [ ] **Step 3: Implement**

Create `src/components/ai-settings-dialog.tsx`. Use this app's existing `Dialog`/`Button`/`Input`/`Select`-equivalent shadcn primitives (check `src/components/ui/` for whatever select/combobox component this codebase already has installed — `combobox.tsx` exists but was previously flagged as unused scaffolding in an earlier phase; verify live whether it's now suitable to use here or whether a plain native `<select>` matching this app's existing low-key form patterns is more appropriate, your call). Structure:

```tsx
import { useEffect, useState } from 'react'

import { Button } from '#components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogTrigger
} from '#components/ui/dialog'
import { Input } from '#components/ui/input'
import { getAiModels, AI_PROVIDER_IDS, type AiProviderId } from '#lib/ai/models'
import { backend } from '#lib/backend/index'

export function AiSettingsDialog() {
  const [open, setOpen] = useState(false)
  const [keys, setKeys] = useState<Record<AiProviderId, string>>({
    openai: '',
    anthropic: ''
  })
  const [testState, setTestState] = useState<
    Record<AiProviderId, 'idle' | 'testing' | 'ok' | 'error'>
  >({ openai: 'idle', anthropic: 'idle' })
  const [defaultProvider, setDefaultProvider] = useState<string>('')
  const [defaultModel, setDefaultModel] = useState<string>('')

  useEffect(() => {
    if (!open) return
    backend.getAiSettings().then((settings) => {
      setDefaultProvider(settings.defaultAiProvider ?? '')
      setDefaultModel(settings.defaultAiModel ?? '')
    })
  }, [open])

  const saveKey = async (provider: AiProviderId) => {
    await backend.setApiKey(provider, keys[provider])
  }

  const testConnection = async (provider: AiProviderId) => {
    setTestState((s) => ({ ...s, [provider]: 'testing' }))
    try {
      const models = getAiModels()
      const model = models.getModels(provider)[0]
      const apiKey = await backend.getApiKey(provider)
      if (!model || !apiKey) throw new Error('no model or key')
      await models.complete(
        model,
        {
          messages: [{ role: 'user', content: 'ping', timestamp: Date.now() }]
        },
        { apiKey }
      )
      setTestState((s) => ({ ...s, [provider]: 'ok' }))
    } catch {
      setTestState((s) => ({ ...s, [provider]: 'error' }))
    }
  }

  const allModels = getAiModels()
  const modelOptions = [defaultProvider || AI_PROVIDER_IDS[0]].flatMap((p) =>
    allModels.getModels(p as AiProviderId)
  )

  const saveDefaults = async (provider: string, model: string) => {
    setDefaultProvider(provider)
    setDefaultModel(model)
    await backend.saveAiSettings({
      defaultAiProvider: provider || null,
      defaultAiModel: model || null
    })
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger
        render={
          <Button variant="ghost" size="sm" data-testid="ai-settings-trigger" />
        }
      >
        AI Settings
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>AI Writing Tools</DialogTitle>
        </DialogHeader>
        {AI_PROVIDER_IDS.map((provider) => (
          <div key={provider} className="flex items-center gap-2">
            <Input
              type="password"
              placeholder={`${provider} API key`}
              value={keys[provider]}
              onChange={(e) =>
                setKeys((k) => ({ ...k, [provider]: e.target.value }))
              }
              data-testid={`ai-settings-key-${provider}`}
            />
            <Button
              size="sm"
              onClick={() => saveKey(provider)}
              data-testid={`ai-settings-save-${provider}`}
            >
              Save
            </Button>
            <Button
              size="sm"
              variant="secondary"
              onClick={() => testConnection(provider)}
              data-testid={`ai-settings-test-${provider}`}
            >
              {testState[provider] === 'testing'
                ? 'Testing…'
                : 'Test connection'}
            </Button>
          </div>
        ))}
        <select
          value={defaultProvider}
          onChange={(e) => saveDefaults(e.target.value, '')}
          data-testid="ai-settings-default-provider"
        >
          <option value="">Choose a provider…</option>
          {AI_PROVIDER_IDS.map((p) => (
            <option key={p} value={p}>
              {p}
            </option>
          ))}
        </select>
        <select
          value={defaultModel}
          onChange={(e) => saveDefaults(defaultProvider, e.target.value)}
          data-testid="ai-settings-default-model"
        >
          <option value="">Choose a model…</option>
          {modelOptions.map((m) => (
            <option key={m.id} value={m.id}>
              {m.name ?? m.id}
            </option>
          ))}
        </select>
      </DialogContent>
    </Dialog>
  )
}
```

Treat this as a starting structure, not a pixel-final design — verify live (`pnpm dev`) that it renders sensibly and adjust spacing/labels as needed; the important parts are the `data-testid`s (matched by Step 1's tests) and the actual save/load wiring through `backend`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `pnpm test ai-settings-dialog && pnpm exec tsc --noEmit`
Expected: PASS, clean.

- [ ] **Step 5: Wire a temporary entry point**

In `src/components/title-bar.tsx`, add `<AiSettingsDialog />` as a sibling of the existing `theme-toggle` button (read the file first — it currently renders `SidebarTrigger` + a spacer + the theme toggle button in a flex row; add the new dialog trigger button in that same row). This is explicitly a provisional placement — spec §8's real Settings dialog (Phase 4) will supersede this with a proper navigation entry; note this in a one-line comment so a future reader isn't confused about why it's here.

- [ ] **Step 6: Live-verify**

With `pnpm dev` running, open the dialog, confirm both provider rows render, and (without a real API key, since this is dev/faux mode) confirm the "Test connection" button reaches the faux provider and reports success (the faux provider's `complete()` always succeeds with scripted/default content, so this exercises the full plumbing without needing a real key — though `backend.getApiKey` in `MemoryBackend` will return `null` unless you've saved one first via the dialog itself in the same session; confirm the flow works when you do).

- [ ] **Step 7: Run the full check set**

Run: `pnpm test && pnpm exec tsc --noEmit`
Expected: all green.

- [ ] **Step 8: Commit**

```bash
git add src/components
git commit -m "feat: minimal AI settings dialog (API keys + default model)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 9: Writing Tools formatting-toolbar entry point

**Depends on:** none from Tasks 4-8 directly (this task only adds the _entry point_; the popover body is Task 10).

**Files:**

- Create: `src/components/writing-tools-button.tsx`
- Modify: `src/components/editor.tsx`

**Interfaces:**

- Produces: a `WritingToolsButton` component usable inside a custom `FormattingToolbar`, and wires `formattingToolbar={false}` + a manually-rendered `FormattingToolbarController` into `editor.tsx`, mirroring the existing `sideMenu={false}` + `<SideMenuController sideMenu={EditorSideMenu} />` pattern already in that file. Clicking the button (or `⌘J`) sets a piece of state `editor.tsx` passes down to Task 10's popover component (a `writingToolsOpen` boolean is enough at this stage — Task 10 fills in the actual popover body).

- [ ] **Step 1: Confirm the real customization mechanism**

Read `node_modules/@blocknote/react/src/editor/BlockNoteDefaultUI.tsx` and `node_modules/@blocknote/react/src/components/FormattingToolbar/{FormattingToolbar,FormattingToolbarController}.tsx` to confirm: `BlockNoteView`'s `formattingToolbar` prop is boolean-only (`false` disables the default entirely); a custom toolbar requires manually rendering `<FormattingToolbarController formattingToolbar={CustomToolbar} />` as a child of `<BlockNoteView>`, where `CustomToolbar` is a component rendering `<FormattingToolbar>{getFormattingToolbarItems()}<WritingToolsButton /></FormattingToolbar>` (`getFormattingToolbarItems` and `FormattingToolbar` are both real exports of `@blocknote/react` — confirm the exact import paths against the installed version before writing the code below).

- [ ] **Step 2: Implement `WritingToolsButton`**

Create `src/components/writing-tools-button.tsx`. This button needs to work exactly like BlockNote's own default toolbar buttons (rendered via `Components.Generic.Toolbar.Button` from the shared components context, since it must render inside `FormattingToolbar`'s existing item list — same pattern already used for the toolbar buttons this codebase has customized before):

```tsx
import { useComponentsContext } from '@blocknote/react'
import { SparklesIcon } from 'lucide-react'

export function WritingToolsButton({ onClick }: { onClick: () => void }) {
  const Components = useComponentsContext()!
  return (
    <Components.FormattingToolbar.Button
      mainTooltip="Writing Tools (⌘J)"
      onClick={onClick}
      data-testid="writing-tools-button"
    >
      <SparklesIcon className="size-4" />
    </Components.FormattingToolbar.Button>
  )
}
```

Verify `Components.FormattingToolbar.Button` is the correct sub-namespace (not `Components.Generic.Toolbar.Button`) by checking how BlockNote's own `BasicTextStyleButton`/`CreateLinkButton` (in `FormattingToolbar/DefaultButtons/`) render their buttons — match whichever one they actually use.

- [ ] **Step 3: Wire it into `editor.tsx`**

Read the current file in full first (it already has `sideMenu={false}` + a manually-rendered `<SideMenuController sideMenu={EditorSideMenu} />`, and `<CommentThreadsSidebar />` as a sibling — follow the exact same structural pattern). Add:

```tsx
const [writingToolsOpen, setWritingToolsOpen] = useState(false)
```

near the component's other state, and in the `<BlockNoteView>` props, add `formattingToolbar={false}`. As a child of `<BlockNoteView>` (alongside the existing `<SideMenuController>`/`<CommentThreadsSidebar>`):

```tsx
<FormattingToolbarController
  formattingToolbar={() => (
    <FormattingToolbar>
      {getFormattingToolbarItems()}
      <WritingToolsButton
        key="writingToolsButton"
        onClick={() => setWritingToolsOpen(true)}
      />
    </FormattingToolbar>
  )}
/>
```

(Task 10 will replace the bare `writingToolsOpen` boolean with the actual popover; for this task, a temporary visible marker is enough to prove the wiring works — e.g. render `{writingToolsOpen && <div data-testid="writing-tools-placeholder">Writing Tools</div>}` somewhere in the component, to be deleted in Task 10 once the real popover exists.)

- [ ] **Step 4: Add the `⌘J` keyboard shortcut**

Check whether this codebase has an existing global-shortcut pattern (search for `useEffect.*keydown` or similar across `src/components/editor.tsx`/`src/pages/document-page.tsx`) — if not, add a scoped `keydown` listener on the editor's own container (not `window`, to avoid firing when focus is elsewhere) that checks for `event.metaKey && event.key === 'j'`, calls `event.preventDefault()`, and calls the same handler the button uses. Only do this if text is currently selected (matching the formatting toolbar's own visibility condition) — check `editor.getSelection()`'s real API (BlockNote/ProseMirror) to gate this correctly rather than guessing.

- [ ] **Step 5: Live-verify**

With `pnpm dev` running, select text, confirm a sparkle-icon button appears in the formatting toolbar alongside Bold/Italic/etc., and clicking it (or pressing `⌘J` with text selected) shows the temporary placeholder. Confirm the rest of the toolbar (Bold, Italic, existing "Add comment", "Create link") still works unchanged — this task adds a button to the existing list, it must not remove or reorder anything.

- [ ] **Step 6: Run the full check set**

Run: `pnpm test && pnpm exec tsc --noEmit && pnpm e2e`
Expected: all green — the existing e2e tests exercise the formatting toolbar already (comment creation, code blocks) and must still pass unchanged.

- [ ] **Step 7: Commit**

```bash
git add src/components
git commit -m "feat: add Writing Tools entry point to the formatting toolbar

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 10: Writing Tools popover UI (static shell, no streaming yet)

**Depends on:** Task 9 (the `writingToolsOpen` state + entry point this replaces the placeholder with).

**Files:**

- Create: `src/components/writing-tools-popover.tsx`, `src/components/writing-tools-popover.test.tsx`
- Modify: `src/components/editor.tsx` (replace Task 9's placeholder with the real popover)

**Interfaces:**

- Consumes: `WritingToolAction` type from Task 5's `prompts.ts` (for typing the action-selection callbacks — this task does not call `buildContext`/`streamWritingTool` yet, that's Task 11).
- Produces: `WritingToolsPopover` component with props `{ open: boolean; onOpenChange: (open: boolean) => void; onActionSelected: (action: WritingToolAction) => void }`. Task 11 wires `onActionSelected` to the actual streaming call.

- [ ] **Step 1: Write the failing test**

Create `src/components/writing-tools-popover.test.tsx`:

```tsx
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { test, expect, vi } from 'vitest'

import { WritingToolsPopover } from '#components/writing-tools-popover'

test('clicking Proofread calls onActionSelected with the proofread action', async () => {
  const onActionSelected = vi.fn()
  render(
    <WritingToolsPopover
      open={true}
      onOpenChange={() => {}}
      onActionSelected={onActionSelected}
    />
  )
  await userEvent.click(screen.getByTestId('writing-tools-proofread'))
  expect(onActionSelected).toHaveBeenCalledWith({ kind: 'proofread' })
})

test('clicking a tone chip calls onActionSelected with the right tone', async () => {
  const onActionSelected = vi.fn()
  render(
    <WritingToolsPopover
      open={true}
      onOpenChange={() => {}}
      onActionSelected={onActionSelected}
    />
  )
  await userEvent.click(screen.getByTestId('writing-tools-tone-friendly'))
  expect(onActionSelected).toHaveBeenCalledWith({
    kind: 'tone',
    tone: 'friendly'
  })
})

test('submitting the describe-your-change input calls onActionSelected with a custom action', async () => {
  const onActionSelected = vi.fn()
  render(
    <WritingToolsPopover
      open={true}
      onOpenChange={() => {}}
      onActionSelected={onActionSelected}
    />
  )
  await userEvent.type(
    screen.getByTestId('writing-tools-describe-input'),
    'make it shorter{Enter}'
  )
  expect(onActionSelected).toHaveBeenCalledWith({
    kind: 'custom',
    instruction: 'make it shorter'
  })
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pnpm test writing-tools-popover`
Expected: FAIL — component doesn't exist.

- [ ] **Step 3: Implement**

Create `src/components/writing-tools-popover.tsx`, matching `IMG_6065.jpeg`'s layout (describe-your-change input at top, Proofread/Rewrite row, tone chips row, transform cards row, Compose row at bottom) using this app's own `Popover`/`Button` primitives — not BlockNote's, since this popover is triggered from a plain button click, not anchored via BlockNote's own floating-toolbar positioning (it can render as a normal app-level `Popover` anchored near the toolbar button):

```tsx
import { useState } from 'react'

import { Button } from '#components/ui/button'
import { Popover, PopoverContent } from '#components/ui/popover'
import { Input } from '#components/ui/input'
import type { WritingToolAction } from '#lib/ai/prompts'

interface WritingToolsPopoverProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  onActionSelected: (action: WritingToolAction) => void
}

const TONES = ['friendly', 'professional', 'concise'] as const
const TRANSFORMS = ['summary', 'keyPoints', 'list', 'table'] as const
const TRANSFORM_LABELS: Record<(typeof TRANSFORMS)[number], string> = {
  summary: 'Summary',
  keyPoints: 'Key Points',
  list: 'List',
  table: 'Table'
}

export function WritingToolsPopover({
  open,
  onOpenChange,
  onActionSelected
}: WritingToolsPopoverProps) {
  const [describeValue, setDescribeValue] = useState('')

  return (
    <Popover open={open} onOpenChange={onOpenChange}>
      <PopoverContent data-testid="writing-tools-popover" className="w-96">
        <Input
          placeholder="Describe your change"
          value={describeValue}
          onChange={(e) => setDescribeValue(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter' && describeValue.trim()) {
              onActionSelected({
                kind: 'custom',
                instruction: describeValue.trim()
              })
            }
          }}
          data-testid="writing-tools-describe-input"
        />
        <div className="flex gap-2">
          <Button
            onClick={() => onActionSelected({ kind: 'proofread' })}
            data-testid="writing-tools-proofread"
          >
            Proofread
          </Button>
          <Button
            onClick={() => onActionSelected({ kind: 'rewrite' })}
            data-testid="writing-tools-rewrite"
          >
            Rewrite
          </Button>
        </div>
        <div className="flex gap-2">
          {TONES.map((tone) => (
            <Button
              key={tone}
              variant="secondary"
              onClick={() => onActionSelected({ kind: 'tone', tone })}
              data-testid={`writing-tools-tone-${tone}`}
            >
              {tone[0].toUpperCase() + tone.slice(1)}
            </Button>
          ))}
        </div>
        <div className="grid grid-cols-4 gap-2">
          {TRANSFORMS.map((transform) => (
            <Button
              key={transform}
              variant="secondary"
              onClick={() => onActionSelected({ kind: 'transform', transform })}
              data-testid={`writing-tools-transform-${transform}`}
            >
              {TRANSFORM_LABELS[transform]}
            </Button>
          ))}
        </div>
        <Button
          className="w-full"
          variant="secondary"
          onClick={() =>
            onActionSelected({
              kind: 'compose',
              instruction: describeValue.trim()
            })
          }
          data-testid="writing-tools-compose"
        >
          Compose
        </Button>
      </PopoverContent>
    </Popover>
  )
}
```

This is a starting structure to satisfy Step 1's tests and match `IMG_6065.jpeg`'s general shape — visual polish (matching this app's soft design language, spacing, icons per action) is expected to need live tuning; treat exact styling as your judgment call, verified live in Step 6, not a pixel-spec.

- [ ] **Step 4: Run tests to verify they pass**

Run: `pnpm test writing-tools-popover && pnpm exec tsc --noEmit`
Expected: PASS, clean.

- [ ] **Step 5: Wire it into `editor.tsx`, replacing Task 9's placeholder**

Replace the `{writingToolsOpen && <div data-testid="writing-tools-placeholder">...}` from Task 9 with:

```tsx
<WritingToolsPopover
  open={writingToolsOpen}
  onOpenChange={setWritingToolsOpen}
  onActionSelected={(action) => {
    // Task 11 wires this to the actual streaming call; for now just close
    // the popover so the flow is at least visibly complete end-to-end.
    console.log('Writing tool action selected', action)
    setWritingToolsOpen(false)
  }}
/>
```

- [ ] **Step 6: Live-verify**

With `pnpm dev` running, select text, click the Writing Tools button, confirm the popover renders matching `IMG_6065.jpeg`'s general shape (adjust spacing/layout as needed), and confirm each action (Proofread, a tone chip, a transform, Compose, and typing+Enter in the describe input) logs the right action shape to the console and closes the popover. Check both light and dark theme.

- [ ] **Step 7: Run the full check set**

Run: `pnpm test && pnpm exec tsc --noEmit && pnpm e2e`
Expected: all green.

- [ ] **Step 8: Commit**

```bash
git add src/components
git commit -m "feat: Writing Tools popover UI (static shell)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 11: Streaming preview + apply flow (Replace / Insert below / Discard)

**Depends on:** Task 6 (`streamWritingTool`), Task 10 (the popover this extends with a preview state).

**Files:**

- Modify: `src/components/writing-tools-popover.tsx`, `src/components/writing-tools-popover.test.tsx`, `src/components/editor.tsx`

**Interfaces:**

- Produces: `WritingToolsPopover` gains an internal state machine (`idle` → `streaming` → `previewing` → back to `idle`), calling `streamWritingTool` (Task 6) once an action is selected, rendering deltas into a preview area, and three new callbacks the popover invokes on resolution: `onReplace: (text: string) => void`, `onInsertBelow: (text: string) => void`, `onDiscard: () => void` — wired in `editor.tsx` to `editor.replaceBlocks`/`editor.insertBlocks`.

- [ ] **Step 1: Write the failing tests**

Add to `src/components/writing-tools-popover.test.tsx` (mocking `streamWritingTool` so the test controls exactly what streams, rather than depending on Task 4's faux provider indirectly):

```tsx
vi.mock('#lib/ai/client', () => ({
  streamWritingTool: vi.fn()
}))

import { streamWritingTool } from '#lib/ai/client'

async function* fakeStream(chunks: string[]) {
  for (const chunk of chunks) {
    yield { type: 'delta', text: chunk } as const
  }
  yield { type: 'done' } as const
}

test('streams deltas into a preview and shows Replace/Insert/Discard once done', async () => {
  vi.mocked(streamWritingTool).mockReturnValue(fakeStream(['Hello', ' world']))
  const onReplace = vi.fn()
  render(
    <WritingToolsPopover
      open={true}
      onOpenChange={() => {}}
      selectedText="hi there"
      onReplace={onReplace}
      onInsertBelow={vi.fn()}
    />
  )
  await userEvent.click(screen.getByTestId('writing-tools-proofread'))

  await waitFor(() => {
    expect(screen.getByTestId('writing-tools-preview')).toHaveTextContent(
      'Hello world'
    )
  })
  expect(screen.getByTestId('writing-tools-replace')).toBeInTheDocument()

  await userEvent.click(screen.getByTestId('writing-tools-replace'))
  expect(onReplace).toHaveBeenCalledWith('Hello world')
})

test('shows an error state when the stream yields an error event', async () => {
  async function* errorStream() {
    yield {
      type: 'error',
      text: '',
      message: 'No API key configured for openai'
    } as const
  }
  vi.mocked(streamWritingTool).mockReturnValue(errorStream())
  render(
    <WritingToolsPopover
      open={true}
      onOpenChange={() => {}}
      selectedText="hi there"
      onReplace={vi.fn()}
      onInsertBelow={vi.fn()}
    />
  )
  await userEvent.click(screen.getByTestId('writing-tools-proofread'))

  await waitFor(() => {
    expect(screen.getByTestId('writing-tools-error')).toHaveTextContent(
      'No API key configured'
    )
  })
})
```

(Note: the fake error event above includes a stray `text: ''` field that doesn't belong to the real `WritingToolStreamEvent` error variant — remove it; it was left in by mistake while sketching this test. The real shape is just `{ type: 'error', message: string }`.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `pnpm test writing-tools-popover`
Expected: FAIL — `onReplace`/`onInsertBelow`/`selectedText` props don't exist yet, no preview/error rendering.

- [ ] **Step 3: Implement the state machine**

Extend `WritingToolsPopover`: replace the `onActionSelected` prop with `selectedText: string`, `onReplace: (text: string) => void`, `onInsertBelow: (text: string) => void` (dropping the old prop entirely — Task 10's `console.log` placeholder is being replaced, not kept alongside this). Internal state:

```tsx
const [phase, setPhase] = useState<
  'idle' | 'streaming' | 'previewing' | 'error'
>('idle')
const [previewText, setPreviewText] = useState('')
const [errorMessage, setErrorMessage] = useState('')

const runAction = async (action: WritingToolAction) => {
  setPhase('streaming')
  setPreviewText('')
  // Provider/model resolution: Task 8's saved defaults, via backend.getAiSettings() -
  // read them once when starting a stream rather than holding them in component
  // state that could go stale if the user changes defaults in another window.
  const settings = await backend.getAiSettings()
  if (!settings.defaultAiProvider || !settings.defaultAiModel) {
    setPhase('error')
    setErrorMessage(
      'No default AI provider/model configured. Open AI Settings first.'
    )
    return
  }
  try {
    for await (const event of streamWritingTool(action, selectedText, {
      provider: settings.defaultAiProvider as AiProviderId,
      modelId: settings.defaultAiModel
    })) {
      if (event.type === 'delta') {
        setPreviewText((prev) => prev + event.text)
      } else if (event.type === 'error') {
        setPhase('error')
        setErrorMessage(event.message)
        return
      } else if (event.type === 'done') {
        setPhase('previewing')
      }
    }
  } catch (err) {
    setPhase('error')
    setErrorMessage(err instanceof Error ? err.message : String(err))
  }
}
```

Render, in addition to the existing action buttons (disable them while `phase === 'streaming'`): when `phase === 'streaming' || phase === 'previewing'`, a `data-testid="writing-tools-preview"` element showing `previewText`; when `phase === 'previewing'`, three buttons `data-testid="writing-tools-replace"` / `"writing-tools-insert-below"` / `"writing-tools-discard"` calling `onReplace(previewText)` / `onInsertBelow(previewText)` / resetting `phase` to `'idle'` respectively; when `phase === 'error'`, a `data-testid="writing-tools-error"` element showing `errorMessage`, plus a way to dismiss back to `'idle'`.

Wire each existing action button's `onClick` (Proofread, Rewrite, tone chips, transforms, Compose, the describe-input's Enter handler) to call `runAction({...})` instead of the old `onActionSelected({...})`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `pnpm test writing-tools-popover && pnpm exec tsc --noEmit`
Expected: PASS, clean.

- [ ] **Step 5: Wire Replace/Insert into `editor.tsx` via BlockNote's real APIs**

In `editor.tsx`, replace the Task 10 `console.log` wiring with real handlers. You'll need the currently-selected block range at the moment the popover was opened (capture it when `setWritingToolsOpen(true)` fires, via `editor.getSelection()`/`editor.getTextCursorPosition()` — check BlockNote's actual selection API to get the right block reference(s) to pass to `replaceBlocks`, rather than guessing):

```tsx
<WritingToolsPopover
  open={writingToolsOpen}
  onOpenChange={setWritingToolsOpen}
  selectedText={/* the currently selected plain text, read from editor at open-time */}
  onReplace={(text) => {
    // Replace the blocks that were selected when the popover opened with a
    // single new paragraph containing the AI's output - via BlockNote's own
    // block-replacement API, never raw Doc.blocks mutation (spec §14b).
    editor.replaceBlocks(capturedSelectedBlocks, [
      { type: 'paragraph', content: text }
    ])
    setWritingToolsOpen(false)
  }}
  onInsertBelow={(text) => {
    editor.insertBlocks(
      [{ type: 'paragraph', content: text }],
      capturedSelectedBlocks[capturedSelectedBlocks.length - 1],
      'after'
    )
    setWritingToolsOpen(false)
  }}
/>
```

Confirm the exact `replaceBlocks`/`insertBlocks` signatures (argument order, the `'after'`/`'before'` placement literal) against `@blocknote/core`'s actual installed type declarations before finalizing — don't guess.

- [ ] **Step 6: Live-verify end to end**

With `pnpm dev` running (faux provider active): select text, open Writing Tools, click Proofread, confirm the preview area fills in with the faux provider's scripted/default streamed output, click Replace, confirm the selected text is replaced in the actual document. Repeat for Insert below (confirm a new block appears after, original text untouched) and Discard (confirm nothing changes). Confirm the missing-default-settings error path (clear AI settings first) shows a clear error state. Check both light and dark theme.

- [ ] **Step 7: Run the full check set**

Run: `pnpm test && pnpm exec tsc --noEmit && pnpm e2e`
Expected: all green.

- [ ] **Step 8: Commit**

```bash
git add src/components
git commit -m "feat: stream AI results into a preview with Replace/Insert/Discard

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 12: Toast on AI errors + e2e coverage for the full Writing Tools flow

**Depends on:** Task 7 (toaster), Task 11 (the full flow this tests).

**Files:**

- Modify: `src/components/writing-tools-popover.tsx` (toast on error, in addition to the inline error state), `e2e-tests/app.spec.ts`

- [ ] **Step 1: Add a toast alongside the inline error state**

In `writing-tools-popover.tsx`'s error handling (both the `event.type === 'error'` branch and the `catch` block from Task 11), also call:

```tsx
import { toast } from 'sonner'
// ...
toast.error('Writing Tools request failed', { description: event.message })
```

The inline `writing-tools-error` element from Task 11 stays too — the toast is a secondary, transient notice; the inline state is what a user actually reads to understand what happened, per spec's "missing key → toast with action" intent applied narrowly here (no `HK-XXXX` action-routing system yet, just a plain toast).

- [ ] **Step 2: Add e2e coverage**

In `e2e-tests/app.spec.ts`, add a new `test.describe('Writing Tools', ...)` block. Since the e2e/dev build runs the faux provider (Task 4), no real API key or network call is involved — but `streamWritingTool` (Task 6) still requires `backend.getAiSettings()` to return a configured default provider/model before it'll proceed (Task 11's `runAction` guard), so the test must configure AI Settings (Task 8's dialog) first:

```ts
test.describe('Writing Tools', () => {
  test('proofreading selected text streams a result and replaces it', async ({
    page
  }) => {
    await page.goto('/')
    await page.getByTestId('new-doc').click()

    // Configure a default provider/model first (Task 8's dialog), since
    // Task 11's runAction refuses to start a stream without one.
    await page.getByTestId('ai-settings-trigger').click()
    await page
      .getByTestId('ai-settings-default-provider')
      .selectOption('openai')
    const modelSelect = page.getByTestId('ai-settings-default-model')
    await modelSelect.selectOption({ index: 1 })
    await page.keyboard.press('Escape')

    const editable = page
      .getByTestId('editor')
      .locator('[contenteditable="true"]')
      .first()
    await editable.click()
    await page.keyboard.type('This sentance has a typo.')
    await page.keyboard.press('Home')
    await page.keyboard.down('Shift')
    await page.keyboard.press('End')
    await page.keyboard.up('Shift')

    await page.getByTestId('writing-tools-button').click()
    await page.getByTestId('writing-tools-proofread').click()

    await expect(page.getByTestId('writing-tools-preview')).toBeVisible()
    await expect(page.getByTestId('writing-tools-replace')).toBeVisible({
      timeout: 10000
    })

    await page.getByTestId('writing-tools-replace').click()
    // The faux provider's default/scripted response text - confirm what it
    // actually is once Task 4 is implemented (pi-ai's fauxProvider() has a
    // documented default behavior when no responses are explicitly queued
    // via setResponses() - read that behavior rather than assuming empty
    // output) and assert the editor's content changed to contain it, rather
    // than asserting the exact original typo text is gone (which is also a
    // valid, probably-simpler assertion - your call).
    await expect(editable).not.toContainText('This sentance has a typo.')
  })

  test('discarding a result leaves the original text untouched', async ({
    page
  }) => {
    await page.goto('/')
    await page.getByTestId('new-doc').click()
    await page.getByTestId('ai-settings-trigger').click()
    await page
      .getByTestId('ai-settings-default-provider')
      .selectOption('openai')
    await page
      .getByTestId('ai-settings-default-model')
      .selectOption({ index: 1 })
    await page.keyboard.press('Escape')

    const editable = page
      .getByTestId('editor')
      .locator('[contenteditable="true"]')
      .first()
    await editable.click()
    await page.keyboard.type('Keep this exact text.')
    await page.keyboard.press('Home')
    await page.keyboard.down('Shift')
    await page.keyboard.press('End')
    await page.keyboard.up('Shift')

    await page.getByTestId('writing-tools-button').click()
    await page.getByTestId('writing-tools-rewrite').click()
    await expect(page.getByTestId('writing-tools-discard')).toBeVisible({
      timeout: 10000
    })
    await page.getByTestId('writing-tools-discard').click()

    await expect(editable).toContainText('Keep this exact text.')
  })
})
```

- [ ] **Step 3: Run the new e2e tests**

Run: `pnpm e2e`
Expected: all pass, including these two new tests and every pre-existing one. If the faux provider's default (no-`setResponses()`-called) behavior turns out to be an error rather than some default text (check this directly rather than assuming), adjust the first test's assertions accordingly — state in your report which behavior you actually found.

- [ ] **Step 4: Run the full check set**

Run: `pnpm test && pnpm exec tsc --noEmit && pnpm e2e && cargo test --manifest-path src-tauri/Cargo.toml`
Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add src/components e2e-tests
git commit -m "feat: toast on AI errors + e2e coverage for the Writing Tools flow

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 13: Documentation sync (run LAST)

**Files:**

- Modify: `CLAUDE.md`, `README.md`

- [ ] **Step 1: Update `CLAUDE.md`**

Add a bullet under Architecture covering: the AI layer (`src/lib/ai/`: `models.ts`'s real-vs-faux provider split via `isTauri()`, `prompts.ts`'s per-action prompt templates, `client.ts`'s `streamWritingTool` generator), Keychain-backed API keys (`src-tauri/src/ai.rs`, `get_api_key`/`set_api_key`/`delete_api_key`, never in the plain settings file), the global `window.fetch` replacement in `main.tsx` for CORS bypass, the Writing Tools formatting-toolbar entry point and its popover's Replace/Insert-below/Discard flow via `editor.replaceBlocks`/`insertBlocks`, and the minimal `AiSettingsDialog` (explicitly noting the full Settings dialog is still Phase 4). Verify every path/command claim against the actual shipped code before writing it — same discipline as every prior docs-sync task in this project.

- [ ] **Step 2: Update `README.md`**

Mention Writing Tools (Proofread/Rewrite/tone/transforms/Compose, OpenAI + Anthropic) as a shipped editor feature, and note that configuring an API key is required (via the AI Settings entry in the title bar) before it can be used.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md README.md
git commit -m "docs: sync docs with AI Writing Tools (Phase 3)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Self-review notes

- **Spec coverage:** §6's interaction design (Proofread/Rewrite, tone chips, transforms, Compose, streaming preview, Replace/Insert/Discard, model selector) → Tasks 9-11. §6's provider/streaming backend → Tasks 4/6 (superseded per §14b to use the real `pi-ai` package). §6's "Keys fetched from Keychain via IPC per request" → Tasks 1/3/6. §14b's `window.fetch` replacement → Task 2. §14b's minimal Phase-4 pull-forward (Keychain, small dialog, plain toasts) → Tasks 1/3/8/7/12. §14b's `fauxProvider()` testing approach → Tasks 4/6/12. §14b's `editor.replaceBlocks`/`insertBlocks`-only write constraint → Task 11.
- **Placeholder scan:** no TBD/TODO left un-filled; every "verify against the installed version" instruction is paired with a concrete fallback/best-guess implementation to start from, not a bare instruction to "figure it out."
- **Type consistency:** `WritingToolAction` (Task 5) is consumed identically by Task 6's `streamWritingTool`, Task 10's popover, and Task 11's `runAction` — no renamed variants across tasks. `AiProviderId`/`AI_PROVIDER_IDS` (Task 4) is the single source of truth for provider identifiers, reused by Tasks 6/8/11 rather than re-declared. `AiSettings` (Task 3) is the single shape for default-provider/model persistence, reused by Task 8/11.
- **Task ordering:** Task 1 (Rust Keychain) and Task 2 (plugin-http) are independent of each other but both must land before Task 3 (backend IPC) can be meaningfully tested end-to-end against the real Tauri app — though Task 3's `MemoryBackend` half doesn't actually need either to be done first, so parallelizing 1/2 with 3 is possible if using true parallel dispatch; this plan lists them sequentially for simplicity. Tasks 4→5→6 are a strict chain (models → prompts → client, each consumed by the next). Task 7 (toaster) is independent, needed by Task 8 (test-connection feedback — though Task 8 as drafted doesn't actually toast on test failure, just sets local state; Task 12 is where toasts on real AI errors get added) and Task 12. Task 8 depends on 3+4. Task 9 depends on nothing from 1-8 (pure UI wiring) but Task 10 depends on 9, Task 11 depends on 6+10, Task 12 depends on 7+11.
- **Known open verification points, flagged honestly rather than guessed as settled fact:** the exact `keyring` crate patch version and whether `"http:default"` or a scoped permission identifier is what `tauri-plugin-http` actually requires (Task 2); whether pi-ai's `Context.messages[].content` is a plain string or a content-block array in the actually-installed version (Task 5); the faux provider's default (unscripted) response behavior (Task 12); BlockNote's exact `replaceBlocks`/`insertBlocks` signatures and selection-capture API (Task 11); whether `Components.FormattingToolbar.Button` or `Components.Generic.Toolbar.Button` is the right shared-component namespace for the new toolbar button (Task 9). Each of these has an explicit "verify against the installed/real API" instruction rather than being silently assumed.
