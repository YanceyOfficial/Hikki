# Hikki Phase 2 — Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A working BlockNote editor with block autosave, image/file attachments served through a vault-scoped custom protocol, a Notion-style page header (icon + cover), plus the Phase-2 hardening carried over from the Phase-1 final review (atomic writes, corrupt-doc resilience, index-backed sidebar metas, CSP, prod testid stripping).

**Architecture:** BlockNote (`@blocknote/react` + `@blocknote/shadcn`, already installed at 0.51.4) renders inside the existing DocumentPage and pipes `editor.document` through the existing debounced save. Assets are imported by a Rust command into `documents/<uuid>/assets/` and served to the webview by a `hikki-asset://` custom protocol with traversal checks; the CSP is tightened accordingly. Sidebar metas switch from full-vault fs scans to the SQLite `documents` table.

**Tech Stack:** BlockNote 0.51.4, Tauri 2 custom URI scheme protocol, rusqlite, babel-plugin-react-remove-properties.

**Spec:** `docs/superpowers/specs/2026-07-18-hikki-design.md` §3 (version history), §4–§5, §14 (design language); carry-over: `docs/superpowers/plans/2026-07-19-phase-1-carryover.md` (Phase 2 section). Deferred out of this phase: custom AI slash-menu items (Phase 3), templates/gradient covers/emoji-picker library/history UI (Phase 6), file watcher (later), embeds beyond BlockNote defaults, database views & template import (§15 backlog).

**Execution order:** Tasks 1–9, then 11 (history snapshots), 12 (design polish), and 10 (docs) last.

## Global Constraints

- Package manager: **pnpm**; Rust deps via `cargo add` from `src-tauri/`.
- **shadcn/ui first** — use `src/components/ui/*`; install missing primitives via `pnpm dlx shadcn@latest add <name>`. NOTE: this repo's ui primitives are **@base-ui/react**-based: triggers take a `render={<Component/>}` prop, NOT Radix `asChild` (see `src/components/nav-user.tsx` for the convention).
- Import aliases (package.json `imports`): `#components/*`, `#lib/*`, `#lib/backend/*`, `#hooks/*`, `#pages/*`.
- Every interactive element gets `data-testid`.
- TDD: failing test first, watch it fail, implement, watch it pass, commit.
- Commit messages: conventional commits ending with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- Husky runs oxlint/oxfmt on commit; never `--no-verify`.
- IPC payloads camelCase (serde `rename_all = "camelCase"`); timestamps RFC-3339 UTC.
- Components never call `invoke` — only the `backend` singleton from `#lib/backend/index`.
- `save_document` preserves on-disk `deleted_at` (trash-resurrect guard) — nothing in this phase may weaken that.
- Suites at start: vitest 30, cargo 22, playwright 4 — all green; keep them green.

---

### Task 1: Atomic writes + corrupt-document resilience (Rust)

**Files:**

- Create: `src-tauri/src/fsx.rs`
- Modify: `src-tauri/src/document.rs` (use atomic write; skip unreadable docs), `src-tauri/src/vault.rs` (`save_settings` atomic), `src-tauri/src/index.rs` (`reconcile` skips docs that fail to load), `src-tauri/src/lib.rs` (add `mod fsx;`)

**Interfaces:**

- Produces: `fsx::write_atomic(path: &Path, bytes: &[u8]) -> std::io::Result<()>` (write to `<path>.tmp` sibling, then rename over `path`). `document::list_documents` and `Index::reconcile` skip-and-log unreadable documents instead of erroring.

- [ ] **Step 1: Write failing tests**

Create `src-tauri/src/fsx.rs`:

```rust
use std::fs;
use std::io;
use std::path::{Path, PathBuf};

/// Write via temp file + rename so a crash mid-write can never truncate the
/// only copy of a document.
pub fn write_atomic(path: &Path, bytes: &[u8]) -> io::Result<()> {
    let tmp = tmp_path(path);
    fs::write(&tmp, bytes)?;
    fs::rename(&tmp, path)
}

fn tmp_path(path: &Path) -> PathBuf {
    let mut name = path.file_name().map(|n| n.to_os_string()).unwrap_or_default();
    name.push(".tmp");
    path.with_file_name(name)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn writes_content_and_leaves_no_tmp_file() {
        let dir = tempfile::tempdir().unwrap();
        let target = dir.path().join("doc.json");
        write_atomic(&target, b"{\"a\":1}").unwrap();
        assert_eq!(fs::read(&target).unwrap(), b"{\"a\":1}");
        assert!(!tmp_path(&target).exists());
    }

    #[test]
    fn overwrites_existing_file() {
        let dir = tempfile::tempdir().unwrap();
        let target = dir.path().join("doc.json");
        write_atomic(&target, b"v1").unwrap();
        write_atomic(&target, b"v2").unwrap();
        assert_eq!(fs::read(&target).unwrap(), b"v2");
    }
}
```

Add to `src-tauri/src/document.rs` tests:

```rust
#[test]
fn list_documents_skips_unreadable_docs() {
    let v = vault();
    create_document(v.path(), None, "Good").unwrap();
    let bad_dir = v.path().join("documents").join(uuid::Uuid::new_v4().to_string());
    fs::create_dir_all(&bad_dir).unwrap();
    fs::write(bad_dir.join("document.json"), "{ truncated garba").unwrap();
    let metas = list_documents(v.path()).unwrap();
    assert_eq!(metas.len(), 1);
    assert_eq!(metas[0].title, "Good");
}
```

Add to `src-tauri/src/index.rs` tests:

```rust
#[test]
fn reconcile_skips_unreadable_docs() {
    let dir = tempfile::tempdir().unwrap();
    crate::vault::ensure_vault(dir.path()).unwrap();
    document::create_document(dir.path(), None, "Good").unwrap();
    let bad_dir = dir.path().join("documents").join(uuid::Uuid::new_v4().to_string());
    std::fs::create_dir_all(&bad_dir).unwrap();
    std::fs::write(bad_dir.join("document.json"), "not json").unwrap();
    let mut idx = Index::open_in_memory().unwrap();
    let count = idx.reconcile(dir.path()).unwrap();
    assert_eq!(count, 1);
    assert_eq!(idx.search("good").unwrap().len(), 1);
}
```

Add `mod fsx;` to `src-tauri/src/lib.rs`.

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `cargo test --manifest-path src-tauri/Cargo.toml`
Expected: `list_documents_skips_unreadable_docs` FAILS (list_documents currently propagates the parse error). `reconcile_skips_unreadable_docs` FAILS. fsx tests pass already (implementation included above — it is trivial and its tests pin behavior).

- [ ] **Step 3: Implement resilience + switch writes to atomic**

In `src-tauri/src/document.rs`:

- `write_doc`: replace `fs::write(doc_file(...), json)?` with `crate::fsx::write_atomic(&doc_file(vault, &doc.id), json.as_bytes())?`.
- `list_documents`: replace the two fallible per-entry operations (`fs::read_to_string`, `serde_json::from_str`) with a skip-and-log match:

```rust
let doc: Document = match fs::read_to_string(&file).map_err(crate::error::AppError::from).and_then(|s| Ok(serde_json::from_str::<Document>(&s)?)) {
    Ok(doc) => doc,
    Err(err) => {
        eprintln!("hikki: skipping unreadable document {}: {err}", file.display());
        continue;
    }
};
```

In `src-tauri/src/vault.rs`: `save_settings` writes via `crate::fsx::write_atomic(&app_data_dir.join("settings.json"), json.as_bytes())` (keep the `create_dir_all` first).

In `src-tauri/src/index.rs` `reconcile`: wrap the per-meta `load_document` in a match — on `Err`, `eprintln!("hikki: skipping unindexable document {}: {err}", meta.id)` and `continue`; count only successfully indexed docs (adjust the return to that count).

- [ ] **Step 4: Run tests to verify they pass**

Run: `cargo test --manifest-path src-tauri/Cargo.toml`
Expected: all pass (22 prior + 4 new = 26).

- [ ] **Step 5: Commit**

```bash
git add src-tauri
git commit -m "feat(rust): atomic document writes and corrupt-doc resilience

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Index-backed sidebar metas (Rust)

**Files:**

- Modify: `src-tauri/src/index.rs` (add `list_metas`), `src-tauri/src/commands.rs` (`list_documents_impl` reads from index)

**Interfaces:**

- Consumes: `documents` table columns `(id, parent_id, title, icon, word_count, created_at, updated_at, deleted_at)`.
- Produces: `Index::list_metas(&self) -> Result<Vec<DocumentMeta>>` ordered by `created_at`. `list_documents` command semantics unchanged from the frontend's view (includes soft-deleted docs, sorted by createdAt) — but now O(1 query) instead of parsing every document's blocks on every sidebar refresh.

- [ ] **Step 1: Write failing tests**

In `src-tauri/src/index.rs` tests:

```rust
#[test]
fn list_metas_returns_rows_sorted_by_created_at() {
    let idx = Index::open_in_memory().unwrap();
    let mut b = doc_with("B", sample_blocks());
    b.created_at = "2026-01-02T00:00:00Z".into();
    let mut a = doc_with("A", sample_blocks());
    a.created_at = "2026-01-01T00:00:00Z".into();
    idx.upsert(&b).unwrap();
    idx.upsert(&a).unwrap();
    let metas = idx.list_metas().unwrap();
    assert_eq!(metas.iter().map(|m| m.title.as_str()).collect::<Vec<_>>(), vec!["A", "B"]);
}

#[test]
fn list_metas_includes_soft_deleted() {
    let idx = Index::open_in_memory().unwrap();
    let mut doc = doc_with("Trashed", sample_blocks());
    doc.deleted_at = Some("2026-01-02T00:00:00Z".into());
    idx.upsert(&doc).unwrap();
    let metas = idx.list_metas().unwrap();
    assert_eq!(metas.len(), 1);
    assert!(metas[0].deleted_at.is_some());
}
```

In `src-tauri/src/commands.rs` tests:

```rust
#[test]
fn list_documents_serves_from_index() {
    let (_v, _d, state) = state();
    let doc = create_document_impl(&state, None, "Indexed".into()).unwrap();
    // Remove from the index only — fs still has the doc. If list reads the
    // index (as required), the doc must disappear from the listing.
    state.index.lock().unwrap().remove(&doc.id).unwrap();
    assert!(list_documents_impl(&state).unwrap().is_empty());
}
```

(If `Index::remove` is `#[cfg(test)]`-unused-warned, this test also legitimizes it.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `cargo test --manifest-path src-tauri/Cargo.toml list_metas` and `cargo test --manifest-path src-tauri/Cargo.toml list_documents_serves`
Expected: compile error (`list_metas` undefined); the commands test fails (current impl reads fs).

- [ ] **Step 3: Implement**

`src-tauri/src/index.rs`:

```rust
pub fn list_metas(&self) -> Result<Vec<crate::document::DocumentMeta>> {
    let mut stmt = self.conn.prepare(
        "SELECT id, parent_id, title, icon, created_at, updated_at, deleted_at
         FROM documents ORDER BY created_at",
    )?;
    let metas = stmt
        .query_map([], |row| {
            Ok(crate::document::DocumentMeta {
                id: row.get(0)?,
                parent_id: row.get(1)?,
                title: row.get(2)?,
                icon: row.get(3)?,
                created_at: row.get(4)?,
                updated_at: row.get(5)?,
                deleted_at: row.get(6)?,
            })
        })?
        .collect::<std::result::Result<Vec<_>, _>>()?;
    Ok(metas)
}
```

`src-tauri/src/commands.rs` `list_documents_impl` becomes:

```rust
pub fn list_documents_impl(state: &AppState) -> Result<Vec<DocumentMeta>> {
    lock(&state.index).list_metas()
}
```

(Remove the now-unused `document::list_documents` import from commands.rs if it was only used there — `get_vault_info_impl` may still use it; if so, switch `get_vault_info_impl`'s count to `list_metas()` too so both read the index consistently.)

- [ ] **Step 4: Run the full Rust suite**

Run: `cargo test --manifest-path src-tauri/Cargo.toml`
Expected: all pass (26 + 3 = 29). Watch for existing commands tests that relied on fs-reads — `delete_removes_from_search` asserts the deleted doc is still listed; that still holds because `delete_document_impl` re-upserts affected docs into the index with `deleted_at` set.

- [ ] **Step 5: Commit**

```bash
git add src-tauri
git commit -m "perf(rust): serve sidebar metas from the SQLite index

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Asset import (Rust)

**Files:**

- Create: `src-tauri/src/asset.rs`
- Modify: `src-tauri/src/document.rs` (make `validate_id` `pub(crate)`), `src-tauri/src/commands.rs` (add command), `src-tauri/src/lib.rs` (add `mod asset;`, register command)

**Interfaces:**

- Consumes: `document::validate_id`, `fsx::write_atomic`.
- Produces:
  - `asset::import_asset(vault: &Path, doc_id: &str, file_name: &str, bytes: &[u8]) -> Result<String>` — stores bytes as `documents/<doc_id>/assets/<uuid>.<sanitized-ext>`, returns the stored **file name** (not a URL; the frontend builds URLs).
  - Command `import_asset(doc_id: String, file_name: String, bytes: Vec<u8>) -> Result<String>` (JS args: `{ docId, fileName, bytes }`).

- [ ] **Step 1: Write failing tests**

Create `src-tauri/src/asset.rs`:

```rust
use std::fs;
use std::path::Path;

use crate::document::validate_id;
use crate::error::Result;

#[cfg(test)]
mod tests {
    use super::*;

    fn vault() -> tempfile::TempDir {
        let dir = tempfile::tempdir().unwrap();
        crate::vault::ensure_vault(dir.path()).unwrap();
        dir
    }

    #[test]
    fn stores_bytes_under_doc_assets_with_uuid_name() {
        let v = vault();
        let doc = crate::document::create_document(v.path(), None, "D").unwrap();
        let stored = import_asset(v.path(), &doc.id, "photo.PNG", b"imgbytes").unwrap();
        assert!(stored.ends_with(".png"), "extension lowercased: {stored}");
        let on_disk = v.path().join("documents").join(&doc.id).join("assets").join(&stored);
        assert_eq!(fs::read(on_disk).unwrap(), b"imgbytes");
        let stem = stored.trim_end_matches(".png");
        assert!(uuid::Uuid::parse_str(stem).is_ok(), "uuid stem: {stored}");
    }

    #[test]
    fn sanitizes_hostile_extension_and_falls_back_to_bin() {
        let v = vault();
        let doc = crate::document::create_document(v.path(), None, "D").unwrap();
        let stored = import_asset(v.path(), &doc.id, "../../evil.p/ng", b"x").unwrap();
        assert!(stored.ends_with(".ng") || stored.ends_with(".bin"), "got {stored}");
        let no_ext = import_asset(v.path(), &doc.id, "noext", b"x").unwrap();
        assert!(no_ext.ends_with(".bin"), "got {no_ext}");
    }

    #[test]
    fn rejects_malformed_doc_id() {
        let v = vault();
        match import_asset(v.path(), "../escape", "a.png", b"x") {
            Err(crate::error::AppError::NotFound(_)) => {}
            other => panic!("expected NotFound, got {other:?}"),
        }
    }
}
```

Add to `src-tauri/src/commands.rs` tests:

```rust
#[test]
fn import_asset_stores_and_returns_file_name() {
    let (_v, _d, state) = state();
    let doc = create_document_impl(&state, None, "D".into()).unwrap();
    let stored = import_asset_impl(&state, doc.id.clone(), "a.png".into(), vec![1, 2, 3]).unwrap();
    let vault_path = std::path::PathBuf::from(get_vault_info_impl(&state).unwrap().vault_path);
    assert!(vault_path.join("documents").join(&doc.id).join("assets").join(&stored).is_file());
}
```

Add `mod asset;` to lib.rs. In `document.rs`, change `fn validate_id` to `pub(crate) fn validate_id`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cargo test --manifest-path src-tauri/Cargo.toml asset`
Expected: compile error — `import_asset` not defined.

- [ ] **Step 3: Implement**

`src-tauri/src/asset.rs` (above tests):

```rust
/// Copy raw bytes into the document's assets dir under a fresh UUID name.
/// The original file name contributes only a sanitized extension, so hostile
/// names can never influence the stored path.
pub fn import_asset(vault: &Path, doc_id: &str, file_name: &str, bytes: &[u8]) -> Result<String> {
    validate_id(doc_id)?;
    let ext: String = Path::new(file_name)
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("")
        .chars()
        .filter(|c| c.is_ascii_alphanumeric())
        .take(10)
        .collect::<String>()
        .to_ascii_lowercase();
    let ext = if ext.is_empty() { "bin".to_string() } else { ext };
    let stored = format!("{}.{ext}", uuid::Uuid::new_v4());
    let dir = vault.join("documents").join(doc_id).join("assets");
    fs::create_dir_all(&dir)?;
    crate::fsx::write_atomic(&dir.join(&stored), bytes)?;
    Ok(stored)
}
```

`src-tauri/src/commands.rs`:

```rust
pub fn import_asset_impl(state: &AppState, doc_id: String, file_name: String, bytes: Vec<u8>) -> Result<String> {
    let vault_path = lock(&state.settings).vault_path.clone();
    crate::asset::import_asset(&vault_path, &doc_id, &file_name, &bytes)
}

#[tauri::command]
pub fn import_asset(state: State<AppState>, doc_id: String, file_name: String, bytes: Vec<u8>) -> Result<String> {
    import_asset_impl(&state, doc_id, file_name, bytes)
}
```

Register `commands::import_asset` in lib.rs `generate_handler!`.

- [ ] **Step 4: Run the full Rust suite**

Run: `cargo test --manifest-path src-tauri/Cargo.toml`
Expected: all pass (29 + 4 = 33).

- [ ] **Step 5: Commit**

```bash
git add src-tauri
git commit -m "feat(rust): asset import into vault-scoped per-document storage

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: `hikki-asset://` protocol + CSP (Rust + config)

**Files:**

- Modify: `src-tauri/src/asset.rs` (add `resolve_asset_path` + `mime_for`), `src-tauri/src/lib.rs` (register protocol), `src-tauri/tauri.conf.json` (CSP)

**Interfaces:**

- Consumes: `AppState.settings` for the current vault path.
- Produces:
  - `asset::resolve_asset_path(vault: &Path, url_path: &str) -> Result<std::path::PathBuf>` — accepts `"/<docId>/<fileName>"`, validates docId is a UUID and fileName is a single safe component, returns the absolute asset path (must exist).
  - `asset::mime_for(path: &Path) -> &'static str`.
  - Webview can fetch `hikki-asset://localhost/<docId>/<fileName>` (macOS/Linux) / `http://hikki-asset.localhost/<docId>/<fileName>` (Windows).

- [ ] **Step 1: Write failing tests (in `src-tauri/src/asset.rs` tests module)**

```rust
#[test]
fn resolves_existing_asset_path() {
    let v = vault();
    let doc = crate::document::create_document(v.path(), None, "D").unwrap();
    let stored = import_asset(v.path(), &doc.id, "a.png", b"x").unwrap();
    let resolved = resolve_asset_path(v.path(), &format!("/{}/{}", doc.id, stored)).unwrap();
    assert!(resolved.ends_with(format!("documents/{}/assets/{}", doc.id, stored)));
    assert!(resolved.is_file());
}

#[test]
fn rejects_traversal_and_malformed_requests() {
    let v = vault();
    for bad in [
        "/../../etc/passwd",
        "/not-a-uuid/a.png",
        "/9f8b7c6d-0000-0000-0000-000000000000/../document.json",
        "/9f8b7c6d-0000-0000-0000-000000000000/a/b.png",
        "/9f8b7c6d-0000-0000-0000-000000000000/..",
        "/onlyonesegment",
    ] {
        assert!(resolve_asset_path(v.path(), bad).is_err(), "should reject {bad}");
    }
}

#[test]
fn mime_for_common_types() {
    assert_eq!(mime_for(Path::new("a.png")), "image/png");
    assert_eq!(mime_for(Path::new("a.JPG")), "image/jpeg");
    assert_eq!(mime_for(Path::new("a.pdf")), "application/pdf");
    assert_eq!(mime_for(Path::new("a.weird")), "application/octet-stream");
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cargo test --manifest-path src-tauri/Cargo.toml asset`
Expected: compile error — `resolve_asset_path`, `mime_for` not defined.

- [ ] **Step 3: Implement resolver + protocol registration**

In `src-tauri/src/asset.rs`:

```rust
use crate::error::AppError;
use std::path::PathBuf;

/// Resolve "/<docId>/<fileName>" to an on-disk asset path. docId must be a
/// UUID and fileName one plain component — anything else is rejected, so a
/// crafted URL can never read outside the vault's asset dirs.
pub fn resolve_asset_path(vault: &Path, url_path: &str) -> Result<PathBuf> {
    let mut parts = url_path.trim_start_matches('/').splitn(2, '/');
    let doc_id = parts.next().unwrap_or_default();
    let file_name = parts.next().unwrap_or_default();
    validate_id(doc_id)?;
    let safe = !file_name.is_empty()
        && !file_name.contains('/')
        && !file_name.contains('\\')
        && file_name != "."
        && file_name != ".."
        && file_name.chars().all(|c| c.is_ascii_alphanumeric() || c == '.' || c == '-' || c == '_');
    if !safe {
        return Err(AppError::NotFound(url_path.to_string()));
    }
    let path = vault.join("documents").join(doc_id).join("assets").join(file_name);
    if !path.is_file() {
        return Err(AppError::NotFound(url_path.to_string()));
    }
    Ok(path)
}

pub fn mime_for(path: &Path) -> &'static str {
    match path.extension().and_then(|e| e.to_str()).map(|e| e.to_ascii_lowercase()).as_deref() {
        Some("png") => "image/png",
        Some("jpg") | Some("jpeg") => "image/jpeg",
        Some("gif") => "image/gif",
        Some("webp") => "image/webp",
        Some("svg") => "image/svg+xml",
        Some("pdf") => "application/pdf",
        Some("mp4") => "video/mp4",
        Some("webm") => "video/webm",
        Some("mp3") => "audio/mpeg",
        Some("wav") => "audio/wav",
        _ => "application/octet-stream",
    }
}
```

In `src-tauri/src/lib.rs`, before `.setup(...)` add:

```rust
.register_uri_scheme_protocol("hikki-asset", |ctx, request| {
    let app = ctx.app_handle();
    let state = app.state::<commands::AppState>();
    let vault_path = state.settings.lock().unwrap_or_else(std::sync::PoisonError::into_inner).vault_path.clone();
    match asset::resolve_asset_path(&vault_path, request.uri().path()) {
        Ok(path) => {
            let mime = asset::mime_for(&path);
            match std::fs::read(&path) {
                Ok(body) => tauri::http::Response::builder()
                    .header("Content-Type", mime)
                    .body(body)
                    .unwrap(),
                Err(_) => tauri::http::Response::builder().status(404).body(Vec::new()).unwrap(),
            }
        }
        Err(_) => tauri::http::Response::builder().status(404).body(Vec::new()).unwrap(),
    }
})
```

(Requires `mod asset;` already declared; `use tauri::Manager;` is already imported.)

In `src-tauri/tauri.conf.json`, replace `"security": { "csp": null }` with:

```json
"security": {
  "csp": {
    "default-src": "'self'",
    "script-src": "'self'",
    "style-src": "'self' 'unsafe-inline'",
    "img-src": "'self' hikki-asset: data: blob:",
    "media-src": "'self' hikki-asset: data: blob:",
    "font-src": "'self' data:",
    "connect-src": "'self' ipc: http://ipc.localhost"
  },
  "devCsp": {
    "default-src": "'self'",
    "script-src": "'self' 'unsafe-inline' http://localhost:1420",
    "style-src": "'self' 'unsafe-inline' http://localhost:1420",
    "img-src": "'self' hikki-asset: data: blob: http://localhost:1420",
    "media-src": "'self' hikki-asset: data: blob: http://localhost:1420",
    "font-src": "'self' data: http://localhost:1420",
    "connect-src": "'self' ipc: http://ipc.localhost ws://localhost:1420 http://localhost:1420"
  }
}
```

- [ ] **Step 4: Run tests + compile check**

Run: `cargo test --manifest-path src-tauri/Cargo.toml && cargo check --manifest-path src-tauri/Cargo.toml`
Expected: all pass (33 + 3 = 36); check clean. (The protocol handler itself is covered via `resolve_asset_path` tests; visual verification happens in the user's manual smoke test at phase end.)

- [ ] **Step 5: Commit**

```bash
git add src-tauri
git commit -m "feat(rust): vault-scoped hikki-asset protocol and tightened CSP

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Backend.importAsset + assetUrl (TS)

**Files:**

- Create: `src/lib/asset-url.ts`, `src/lib/asset-url.test.ts`
- Modify: `src/lib/backend/backend.ts`, `src/lib/backend/tauri-backend.ts`, `src/lib/backend/memory-backend.ts`, `src/lib/backend/tauri-backend.test.ts`, `src/lib/backend/memory-backend.test.ts`

**Interfaces:**

- Produces (consumed by Tasks 6–7):

```ts
// backend.ts additions
export interface ImportedAsset {
  fileName: string
  url: string
}
interface Backend {
  // ...existing methods unchanged...
  importAsset(docId: string, file: File): Promise<ImportedAsset>
  assetUrl(docId: string, fileName: string): string
}

// asset-url.ts
export function protocolAssetUrl(docId: string, fileName: string): string
// -> `http://hikki-asset.localhost/<docId>/<fileName>` on Windows UA, else `hikki-asset://localhost/<docId>/<fileName>`
```

- `TauriBackend.importAsset`: reads the file's bytes, `invoke('import_asset', { docId, fileName: file.name, bytes: Array.from(new Uint8Array(await file.arrayBuffer())) })` → stored name → `{ fileName: stored, url: protocolAssetUrl(docId, stored) }`. `assetUrl` = `protocolAssetUrl`.
- `MemoryBackend.importAsset`: stores an object URL (`URL.createObjectURL(file)` when available, else `memory-asset:<docId>/<name>` fallback for jsdom) in a private map keyed `docId/fileName`; returns `{ fileName: file.name, url }`. `assetUrl(docId, fileName)` returns the stored url or the fallback string.

- [ ] **Step 1: Write failing tests**

`src/lib/asset-url.test.ts`:

```ts
import { protocolAssetUrl } from '#lib/asset-url'

test('builds custom-scheme URL on non-Windows', () => {
  expect(protocolAssetUrl('doc-1', 'img.png')).toBe(
    'hikki-asset://localhost/doc-1/img.png'
  )
})

test('encodes unusual characters', () => {
  expect(protocolAssetUrl('doc-1', 'a b.png')).toBe(
    'hikki-asset://localhost/doc-1/a%20b.png'
  )
})
```

Append to `src/lib/backend/tauri-backend.test.ts`:

```ts
test('importAsset sends bytes and maps the stored name to a URL', async () => {
  const calls: Array<[string, unknown]> = []
  mockIPC((cmd, args) => {
    calls.push([cmd, args])
    return 'stored-uuid.png'
  })
  const file = new File([new Uint8Array([1, 2, 3])], 'photo.png')
  const result = await new TauriBackend().importAsset('doc-1', file)
  expect(calls).toEqual([
    [
      'import_asset',
      { docId: 'doc-1', fileName: 'photo.png', bytes: [1, 2, 3] }
    ]
  ])
  expect(result).toEqual({
    fileName: 'stored-uuid.png',
    url: 'hikki-asset://localhost/doc-1/stored-uuid.png'
  })
})
```

Append to `src/lib/backend/memory-backend.test.ts`:

```ts
test('importAsset returns a url and assetUrl resolves it later', async () => {
  const b = new MemoryBackend()
  const doc = await b.createDocument(null, 'D')
  const file = new File([new Uint8Array([9])], 'pic.png')
  const imported = await b.importAsset(doc.id, file)
  expect(imported.fileName).toBe('pic.png')
  expect(imported.url).toBeTruthy()
  expect(b.assetUrl(doc.id, 'pic.png')).toBe(imported.url)
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pnpm test`
Expected: FAIL — `#lib/asset-url` missing; `importAsset` not a function on either backend.

- [ ] **Step 3: Implement**

`src/lib/asset-url.ts`:

```ts
export function protocolAssetUrl(docId: string, fileName: string): string {
  const path = `${encodeURIComponent(docId)}/${encodeURIComponent(fileName)}`
  return navigator.userAgent.includes('Windows')
    ? `http://hikki-asset.localhost/${path}`
    : `hikki-asset://localhost/${path}`
}
```

`src/lib/backend/backend.ts`: add the `ImportedAsset` interface and the two methods to `Backend` (exact shapes from the Interfaces block).

`src/lib/backend/tauri-backend.ts`:

```ts
async importAsset(docId: string, file: File): Promise<ImportedAsset> {
  const bytes = Array.from(new Uint8Array(await file.arrayBuffer()))
  const stored = await invoke<string>('import_asset', { docId, fileName: file.name, bytes })
  return { fileName: stored, url: protocolAssetUrl(docId, stored) }
}
assetUrl(docId: string, fileName: string): string {
  return protocolAssetUrl(docId, fileName)
}
```

`src/lib/backend/memory-backend.ts`:

```ts
private assets = new Map<string, string>()

async importAsset(docId: string, file: File): Promise<ImportedAsset> {
  const url =
    typeof URL.createObjectURL === 'function' ? URL.createObjectURL(file) : `memory-asset:${docId}/${file.name}`
  this.assets.set(`${docId}/${file.name}`, url)
  return { fileName: file.name, url }
}

assetUrl(docId: string, fileName: string): string {
  return this.assets.get(`${docId}/${fileName}`) ?? `memory-asset:${docId}/${fileName}`
}
```

- [ ] **Step 4: Run tests + typecheck**

Run: `pnpm test && pnpm exec tsc --noEmit`
Expected: all pass (30 + 4 = 34), tsc clean.

- [ ] **Step 5: Commit**

```bash
git add src
git commit -m "feat: importAsset backend method with platform-aware asset URLs

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: BlockNote editor with block autosave

**Files:**

- Create: `src/components/editor.tsx`
- Modify: `src/pages/document-page.tsx` (mount editor, patch-style update), `src/pages/document-page.test.tsx` (mock the editor; new blocks-save test)

**Interfaces:**

- Consumes: `backend.importAsset`, `Doc`, existing `debounce` save in DocumentPage.
- Produces: `Editor` component `{ docId: string; initialBlocks: unknown[]; onBlocksChange(blocks: unknown[]): void }`; DocumentPage's `update(patch: Partial<Doc>)` (functional setState + debounced save) which Task 7's header also uses.

- [ ] **Step 1: Write failing tests**

In `src/pages/document-page.test.tsx`: BlockNote cannot render under jsdom (ProseMirror needs real layout APIs), so mock the editor module at the top of the file:

```tsx
vi.mock('#components/editor', () => ({
  Editor: ({
    docId,
    initialBlocks,
    onBlocksChange
  }: {
    docId: string
    initialBlocks: unknown[]
    onBlocksChange: (blocks: unknown[]) => void
  }) => (
    <button
      data-testid="mock-editor"
      data-doc-id={docId}
      data-block-count={initialBlocks.length}
      onClick={() => onBlocksChange([{ type: 'paragraph', content: 'edited' }])}
    >
      mock editor
    </button>
  )
}))
```

Add tests:

```tsx
test('renders the editor with the loaded blocks', async () => {
  const doc = await backend.createDocument(null, 'Has editor')
  await backend.saveDocument({ ...doc, blocks: [{ type: 'paragraph' }] })
  renderPage(doc.id)
  const editor = await screen.findByTestId('mock-editor')
  expect(editor).toHaveAttribute('data-doc-id', doc.id)
  expect(editor).toHaveAttribute('data-block-count', '1')
})

test('block changes are autosaved', async () => {
  const doc = await backend.createDocument(null, 'Blocks')
  renderPage(doc.id)
  await userEvent.click(await screen.findByTestId('mock-editor'))
  await waitFor(
    async () =>
      expect((await backend.loadDocument(doc.id)).blocks).toEqual([
        { type: 'paragraph', content: 'edited' }
      ]),
    { timeout: 3000 }
  )
})
```

Also update the old `editor-placeholder` expectations: the placeholder is gone — remove any assertion referencing `editor-placeholder`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `pnpm test`
Expected: FAIL — `#components/editor` doesn't exist yet.

- [ ] **Step 3: Implement**

`src/components/editor.tsx`:

```tsx
import '@blocknote/core/fonts/inter.css'
import '@blocknote/shadcn/style.css'

import type { Block } from '@blocknote/core'
import { useCreateBlockNote } from '@blocknote/react'
import { BlockNoteView } from '@blocknote/shadcn'

import { backend } from '#lib/backend/index'

interface EditorProps {
  docId: string
  initialBlocks: unknown[]
  onBlocksChange: (blocks: unknown[]) => void
}

export function Editor({ docId, initialBlocks, onBlocksChange }: EditorProps) {
  const editor = useCreateBlockNote(
    {
      initialContent:
        initialBlocks.length > 0 ? (initialBlocks as Block[]) : undefined,
      uploadFile: async (file: File) =>
        (await backend.importAsset(docId, file)).url
    },
    [docId]
  )
  return (
    <div data-testid="editor" className="mt-4 -mx-[3.375rem]">
      <BlockNoteView
        editor={editor}
        onChange={() => onBlocksChange(editor.document)}
      />
    </div>
  )
}
```

(If the negative margin fights the page's `max-w-3xl` padding visually, drop it — check in the browser during Step 4's e2e-less sanity run; BlockNote adds its own horizontal padding.)

`src/pages/document-page.tsx`: replace the `update` function and placeholder:

```tsx
const update = (patch: Partial<Doc>) => {
  setDoc((prev) => {
    if (!prev) return prev
    const next = { ...prev, ...patch }
    save(next)
    return next
  })
}
```

- Title input `onChange` becomes `update({ title: e.target.value })`.
- Replace the `editor-placeholder` `<p>` with:

```tsx
<Editor
  key={doc.id}
  docId={doc.id}
  initialBlocks={doc.blocks}
  onBlocksChange={(blocks) => update({ blocks })}
/>
```

- Import `{ Editor } from '#components/editor'`.

- [ ] **Step 4: Run tests + typecheck + browser sanity**

Run: `pnpm test && pnpm exec tsc --noEmit`
Expected: all pass, tsc clean. Then start `pnpm dev` briefly and load `http://localhost:1420` in a headless check (`curl -s localhost:1420 | head -1`) to confirm the dev server boots with the new CSS imports (full visual verification comes from Task 9's e2e).

- [ ] **Step 5: Commit**

```bash
git add src
git commit -m "feat: BlockNote editor with debounced block autosave and asset upload

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: Page header — icon picker + cover

**Files:**

- Create: `src/components/page-header.tsx`, `src/components/page-header.test.tsx`
- Modify: `src/pages/document-page.tsx` (render PageHeader above the editor, move the title input into it)

**Interfaces:**

- Consumes: `update(patch: Partial<Doc>)` from Task 6, `backend.importAsset`/`backend.assetUrl`.
- Produces: `PageHeader` component `{ doc: Doc; onPatch(patch: Partial<Doc>): void }` — renders cover (if `doc.cover`), icon button, title input (testid `doc-title` preserved — e2e depends on it).

- [ ] **Step 1: Write failing tests**

`src/components/page-header.test.tsx`:

```tsx
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'

import { PageHeader } from '#components/page-header'
import type { Doc } from '#lib/types'

const doc = (over: Partial<Doc> = {}): Doc => ({
  schemaVersion: 1,
  id: 'd1',
  parentId: null,
  title: 'Title',
  icon: null,
  cover: null,
  blocks: [],
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  deletedAt: null,
  ...over
})

test('title edits patch the doc', async () => {
  const onPatch = vi.fn()
  render(<PageHeader doc={doc()} onPatch={onPatch} />)
  await userEvent.type(screen.getByTestId('doc-title'), '!')
  expect(onPatch).toHaveBeenCalledWith({ title: 'Title!' })
})

test('picking an emoji patches the icon and remove clears it', async () => {
  const onPatch = vi.fn()
  render(<PageHeader doc={doc({ icon: '📝' })} onPatch={onPatch} />)
  await userEvent.click(screen.getByTestId('doc-icon-button'))
  await userEvent.click(await screen.findByTestId('doc-icon-option-🚀'))
  expect(onPatch).toHaveBeenCalledWith({ icon: '🚀' })
  await userEvent.click(screen.getByTestId('doc-icon-button'))
  await userEvent.click(await screen.findByTestId('doc-icon-remove'))
  expect(onPatch).toHaveBeenCalledWith({ icon: null })
})

test('cover renders from assetUrl and can be removed', async () => {
  const onPatch = vi.fn()
  render(<PageHeader doc={doc({ cover: 'c.png' })} onPatch={onPatch} />)
  const img = screen.getByTestId('doc-cover-image')
  expect(img).toHaveAttribute('src', expect.stringContaining('c.png'))
  await userEvent.click(screen.getByTestId('doc-cover-remove'))
  expect(onPatch).toHaveBeenCalledWith({ cover: null })
})

test('no cover -> add-cover control shown instead of image', () => {
  render(<PageHeader doc={doc()} onPatch={vi.fn()} />)
  expect(screen.queryByTestId('doc-cover-image')).not.toBeInTheDocument()
  expect(screen.getByTestId('doc-cover-add')).toBeInTheDocument()
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pnpm test`
Expected: FAIL — `#components/page-header` missing.

- [ ] **Step 3: Implement**

`src/components/page-header.tsx`:

```tsx
import { ImagePlus, SmilePlus, X } from 'lucide-react'
import { useRef } from 'react'

import { Button } from '#components/ui/button'
import { Popover, PopoverContent, PopoverTrigger } from '#components/ui/popover'
import { backend } from '#lib/backend/index'
import type { Doc } from '#lib/types'

const EMOJI = [
  '📝',
  '📚',
  '💡',
  '🚀',
  '🎯',
  '📌',
  '🗂️',
  '🧠',
  '☕',
  '🌱',
  '🔥',
  '⭐',
  '💼',
  '🏠',
  '🎨',
  '🎵',
  '🧪',
  '💰',
  '❤️',
  '🗓️',
  '✅',
  '✈️',
  '🍜',
  '🏋️',
  '🐛',
  '🔒',
  '🌍',
  '📷',
  '🎁',
  '⚡'
]

interface PageHeaderProps {
  doc: Doc
  onPatch: (patch: Partial<Doc>) => void
}

export function PageHeader({ doc, onPatch }: PageHeaderProps) {
  const coverInput = useRef<HTMLInputElement>(null)

  const uploadCover = async (file: File | undefined) => {
    if (!file) return
    const imported = await backend.importAsset(doc.id, file)
    onPatch({ cover: imported.fileName })
  }

  return (
    <header data-testid="page-header">
      {doc.cover ? (
        <div className="group relative -mx-8 -mt-10 mb-6 h-48">
          <img
            data-testid="doc-cover-image"
            src={backend.assetUrl(doc.id, doc.cover)}
            alt=""
            className="h-full w-full object-cover"
          />
          <Button
            variant="secondary"
            size="sm"
            className="absolute right-3 bottom-3 opacity-0 transition-opacity group-hover:opacity-100"
            onClick={() => onPatch({ cover: null })}
            data-testid="doc-cover-remove"
          >
            <X /> Remove cover
          </Button>
        </div>
      ) : null}
      <div className="flex items-center gap-2">
        <Popover>
          <PopoverTrigger
            render={
              <Button
                variant="ghost"
                size="icon"
                className="size-10 text-2xl"
                data-testid="doc-icon-button"
              />
            }
          >
            {doc.icon ?? <SmilePlus className="text-muted-foreground size-5" />}
          </PopoverTrigger>
          <PopoverContent className="w-64" align="start">
            <div className="grid grid-cols-6 gap-1">
              {EMOJI.map((emoji) => (
                <Button
                  key={emoji}
                  variant="ghost"
                  size="icon"
                  className="size-9 text-lg"
                  onClick={() => onPatch({ icon: emoji })}
                  data-testid={`doc-icon-option-${emoji}`}
                >
                  {emoji}
                </Button>
              ))}
            </div>
            {doc.icon ? (
              <Button
                variant="ghost"
                size="sm"
                className="mt-2 w-full"
                onClick={() => onPatch({ icon: null })}
                data-testid="doc-icon-remove"
              >
                Remove icon
              </Button>
            ) : null}
          </PopoverContent>
        </Popover>
        {!doc.cover && (
          <Button
            variant="ghost"
            size="sm"
            className="text-muted-foreground"
            onClick={() => coverInput.current?.click()}
            data-testid="doc-cover-add"
          >
            <ImagePlus /> Add cover
          </Button>
        )}
        <input
          ref={coverInput}
          type="file"
          accept="image/*"
          className="hidden"
          onChange={(e) => uploadCover(e.target.files?.[0])}
          data-testid="doc-cover-input"
        />
      </div>
      <input
        data-testid="doc-title"
        className="mt-2 w-full bg-transparent text-4xl font-bold outline-none"
        placeholder="Untitled"
        value={doc.title}
        onChange={(e) => onPatch({ title: e.target.value })}
      />
    </header>
  )
}
```

(Check `PopoverTrigger` in `src/components/ui/popover.tsx` for the `render` prop convention before using — mirror whatever `nav-user.tsx` does for triggers. If `Button` doesn't forward `data-testid`, it does via prop spread — verify once.)

`src/pages/document-page.tsx`: replace the bare title `<input>` with `<PageHeader doc={doc} onPatch={update} />` (keep `update` from Task 6). Existing title tests keep passing because `doc-title` moved but kept its testid and behavior.

- [ ] **Step 4: Run tests + typecheck**

Run: `pnpm test && pnpm exec tsc --noEmit`
Expected: all pass, tsc clean.

- [ ] **Step 5: Commit**

```bash
git add src
git commit -m "feat: page header with emoji icon picker and image cover

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: Strip data-testid from production builds

**Files:**

- Modify: `vite.config.ts`, `package.json` (devDep)

**Interfaces:**

- Produces: production bundles (`pnpm build`) contain none of our `data-testid` attributes; dev/test keep them.

- [ ] **Step 1: Install the babel plugin**

```bash
pnpm add -D babel-plugin-react-remove-properties
```

- [ ] **Step 2: Wire it into the React plugin for production only**

`vite.config.ts` — change the config factory to receive `mode` and configure babel:

```ts
export default defineConfig(({ mode }) => ({
  plugins: [
    react({
      babel: {
        plugins:
          mode === 'production'
            ? [['react-remove-properties', { properties: ['data-testid'] }]]
            : []
      }
    }),
    tailwindcss()
  ]
  // ...keep the existing clearScreen/server options unchanged...
}))
```

(The current file uses `defineConfig(async () => ({...}))` — drop the `async`, take `{ mode }`.)

- [ ] **Step 3: Verify test/dev builds keep testids and prod strips them**

Run: `pnpm test` — all pass (testids present under vitest).
Run: `pnpm build && grep -o 'doc-title\|new-doc\|doc-tree' dist/assets/*.js | sort -u`
Expected: build succeeds; grep prints **nothing** (exit code 1). If `tsc` in the build script fails on unrelated files, fix them — the build must be green.

- [ ] **Step 4: Commit**

```bash
git add vite.config.ts package.json pnpm-lock.yaml
git commit -m "build: strip data-testid attributes from production bundles

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 9: E2E — editor typing, slash menu, icon, persistence

**Files:**

- Modify: `e2e-tests/app.spec.ts` (append tests)

**Interfaces:**

- Consumes: testids `editor`, `doc-title`, `doc-icon-button`, `doc-icon-option-🚀`, `nav-dashboard`, `doc-tree`; BlockNote renders a `[contenteditable="true"]` region inside `[data-testid="editor"]`.

- [ ] **Step 1: Append the e2e tests**

```ts
test('type in the editor and content survives navigation', async ({ page }) => {
  await page.goto('/')
  await page.getByTestId('new-doc').click()
  await page.getByTestId('doc-title').fill('Editor doc')
  const editable = page
    .getByTestId('editor')
    .locator('[contenteditable="true"]')
    .first()
  await editable.click()
  await page.keyboard.type('Hello from BlockNote')
  await page.getByTestId('nav-dashboard').click()
  await page.getByTestId('doc-tree').getByText('Editor doc').click()
  await expect(page.getByTestId('editor')).toContainText('Hello from BlockNote')
})

test('slash menu opens in the editor', async ({ page }) => {
  await page.goto('/')
  await page.getByTestId('new-doc').click()
  const editable = page
    .getByTestId('editor')
    .locator('[contenteditable="true"]')
    .first()
  await editable.click()
  await page.keyboard.type('/')
  await expect(
    page.locator('.bn-suggestion-menu, [class*="suggestionMenu"]').first()
  ).toBeVisible()
})

test('set a page icon from the picker', async ({ page }) => {
  await page.goto('/')
  await page.getByTestId('new-doc').click()
  await page.getByTestId('doc-icon-button').click()
  await page.getByTestId('doc-icon-option-🚀').click()
  await expect(page.getByTestId('doc-icon-button')).toContainText('🚀')
})
```

- [ ] **Step 2: Run the suite**

Run: `pnpm e2e`
Expected: 7 passing (4 existing + 3 new). If the slash-menu selector doesn't match BlockNote 0.51's DOM, inspect the rendered classes via `page.locator('[data-testid="editor"]')` debugging and adjust the selector to the actual menu container class — do not weaken the other assertions.

- [ ] **Step 3: Run everything**

Run: `pnpm test && cargo test --manifest-path src-tauri/Cargo.toml && pnpm exec tsc --noEmit`
Expected: all green.

- [ ] **Step 4: Commit**

```bash
git add e2e-tests
git commit -m "test: e2e coverage for editor typing, slash menu, and page icon

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 11: Version-history snapshots (Rust)

**Files:**

- Create: `src-tauri/src/history.rs`
- Modify: `src-tauri/src/document.rs` (hook in `save_document`), `src-tauri/src/lib.rs` (add `mod history;`)

**Interfaces:**

- Consumes: `Document` (serde), `fsx::write_atomic`, `document::validate_id`.
- Produces (Phase 6's history UI builds on these):
  - `history::maybe_snapshot(vault: &Path, current: &Document) -> Result<Option<String>>` — writes `documents/<id>/history/<UTC-stamp>.json` containing `current` when the newest snapshot is older than `SNAPSHOT_MIN_INTERVAL_SECS` (600) or none exists; prunes to `MAX_SNAPSHOTS` (50); returns the written file name or `None`.
  - `history::list_snapshots(vault: &Path, doc_id: &str) -> Result<Vec<String>>` — snapshot file names, newest first.
  - Snapshot file-name format: `%Y%m%dT%H%M%S%3fZ` UTC (filesystem-safe, lexicographically time-ordered).

- [ ] **Step 1: Write failing tests**

Create `src-tauri/src/history.rs` starting with:

```rust
use std::fs;
use std::path::{Path, PathBuf};

use crate::document::{validate_id, Document};
use crate::error::Result;

pub const SNAPSHOT_MIN_INTERVAL_SECS: i64 = 600;
pub const MAX_SNAPSHOTS: usize = 50;

#[cfg(test)]
mod tests {
    use super::*;

    fn vault() -> tempfile::TempDir {
        let dir = tempfile::tempdir().unwrap();
        crate::vault::ensure_vault(dir.path()).unwrap();
        dir
    }

    #[test]
    fn first_save_writes_a_snapshot() {
        let v = vault();
        let doc = crate::document::create_document(v.path(), None, "A").unwrap();
        let written = maybe_snapshot_with(v.path(), &doc, SNAPSHOT_MIN_INTERVAL_SECS, MAX_SNAPSHOTS).unwrap();
        assert!(written.is_some());
        assert_eq!(list_snapshots(v.path(), &doc.id).unwrap().len(), 1);
    }

    #[test]
    fn rapid_saves_coalesce_within_interval() {
        let v = vault();
        let doc = crate::document::create_document(v.path(), None, "A").unwrap();
        maybe_snapshot_with(v.path(), &doc, SNAPSHOT_MIN_INTERVAL_SECS, MAX_SNAPSHOTS).unwrap();
        let second = maybe_snapshot_with(v.path(), &doc, SNAPSHOT_MIN_INTERVAL_SECS, MAX_SNAPSHOTS).unwrap();
        assert!(second.is_none());
        assert_eq!(list_snapshots(v.path(), &doc.id).unwrap().len(), 1);
    }

    #[test]
    fn zero_interval_snapshots_every_time_and_prunes_to_max() {
        let v = vault();
        let doc = crate::document::create_document(v.path(), None, "A").unwrap();
        for _ in 0..5 {
            maybe_snapshot_with(v.path(), &doc, 0, 3).unwrap();
            std::thread::sleep(std::time::Duration::from_millis(3));
        }
        let snaps = list_snapshots(v.path(), &doc.id).unwrap();
        assert_eq!(snaps.len(), 3);
        let mut sorted = snaps.clone();
        sorted.sort_by(|a, b| b.cmp(a));
        assert_eq!(snaps, sorted, "newest first");
    }

    #[test]
    fn snapshot_content_round_trips() {
        let v = vault();
        let doc = crate::document::create_document(v.path(), None, "Snapshot me").unwrap();
        maybe_snapshot_with(v.path(), &doc, 0, MAX_SNAPSHOTS).unwrap();
        let name = &list_snapshots(v.path(), &doc.id).unwrap()[0];
        let raw = fs::read_to_string(v.path().join("documents").join(&doc.id).join("history").join(name)).unwrap();
        let restored: Document = serde_json::from_str(&raw).unwrap();
        assert_eq!(restored.title, "Snapshot me");
    }

    #[test]
    fn list_snapshots_rejects_bad_id_and_handles_missing_dir() {
        let v = vault();
        assert!(list_snapshots(v.path(), "../escape").is_err());
        let doc = crate::document::create_document(v.path(), None, "A").unwrap();
        assert!(list_snapshots(v.path(), &doc.id).unwrap().is_empty());
    }
}
```

Add `mod history;` to `src-tauri/src/lib.rs`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cargo test --manifest-path src-tauri/Cargo.toml history`
Expected: compile error — `maybe_snapshot_with`, `list_snapshots` not defined.

- [ ] **Step 3: Implement (above the tests)**

```rust
fn history_dir(vault: &Path, doc_id: &str) -> PathBuf {
    vault.join("documents").join(doc_id).join("history")
}

fn stamp_name(now: chrono::DateTime<chrono::Utc>) -> String {
    format!("{}.json", now.format("%Y%m%dT%H%M%S%3fZ"))
}

fn parse_stamp(name: &str) -> Option<chrono::DateTime<chrono::Utc>> {
    chrono::NaiveDateTime::parse_from_str(name.trim_end_matches(".json"), "%Y%m%dT%H%M%S%3fZ")
        .ok()
        .map(|naive| naive.and_utc())
}

/// Production entry point: snapshot with the default interval and cap.
pub fn maybe_snapshot(vault: &Path, current: &Document) -> Result<Option<String>> {
    maybe_snapshot_with(vault, current, SNAPSHOT_MIN_INTERVAL_SECS, MAX_SNAPSHOTS)
}

pub fn maybe_snapshot_with(
    vault: &Path,
    current: &Document,
    min_interval_secs: i64,
    max_snapshots: usize,
) -> Result<Option<String>> {
    validate_id(&current.id)?;
    let existing = list_snapshots(vault, &current.id)?;
    let now = chrono::Utc::now();
    if let Some(newest) = existing.first().and_then(|n| parse_stamp(n)) {
        if (now - newest).num_seconds() < min_interval_secs {
            return Ok(None);
        }
    }
    let dir = history_dir(vault, &current.id);
    fs::create_dir_all(&dir)?;
    let name = stamp_name(now);
    crate::fsx::write_atomic(&dir.join(&name), serde_json::to_string_pretty(current)?.as_bytes())?;
    // Prune beyond the cap (list is newest-first; drop the tail).
    for stale in list_snapshots(vault, &current.id)?.iter().skip(max_snapshots) {
        let _ = fs::remove_file(dir.join(stale));
    }
    Ok(Some(name))
}

/// Snapshot file names, newest first. Missing history dir -> empty.
pub fn list_snapshots(vault: &Path, doc_id: &str) -> Result<Vec<String>> {
    validate_id(doc_id)?;
    let dir = history_dir(vault, doc_id);
    if !dir.is_dir() {
        return Ok(vec![]);
    }
    let mut names: Vec<String> = fs::read_dir(&dir)?
        .filter_map(|e| e.ok())
        .filter_map(|e| e.file_name().into_string().ok())
        .filter(|n| parse_stamp(n).is_some())
        .collect();
    names.sort_by(|a, b| b.cmp(a));
    Ok(names)
}
```

Hook into `src-tauri/src/document.rs` `save_document` — after loading `existing` (the trash-guard load), before writing:

```rust
crate::history::maybe_snapshot(vault, &existing)?;
```

- [ ] **Step 4: Run the full Rust suite**

Run: `cargo test --manifest-path src-tauri/Cargo.toml`
Expected: all pass (36 + 5 = 41; existing document tests unaffected — snapshots are additive).

- [ ] **Step 5: Commit**

```bash
git add src-tauri
git commit -m "feat(rust): rolling version-history snapshots on document save

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 12: Soft design-language pass (spec §14)

**Files:**

- Modify: `src/assets/globals.css` (token tuning, both modes), `src/components/title-bar.tsx`, `src/components/sidebar-left.tsx`, `src/components/doc-tree.tsx`, `src/pages/document-page.tsx`, `src/pages/dashboard-page.tsx` (spacing/transitions polish)

**Interfaces:** none new — visual only. All testids and behaviors must stay intact.

**Before starting:** invoke the `frontend-design` skill (Skill tool) for guidance; the target aesthetic is spec §14: soft, calm, Notion-like — warm low-contrast neutrals, `--radius: 0.625rem`, barely-there borders, muted chrome, 150–200ms ease-out transitions.

- [ ] **Step 1: Tune tokens in `src/assets/globals.css`**

Adjust the existing shadcn token values in place (do not restructure the file). Targets — adapt to the file's format (oklch), keeping both `:root` and `.dark`:

- `--radius`: `0.625rem`.
- Light: `--background` warm off-white (e.g. `oklch(0.99 0.003 90)`), `--foreground` soft near-black (`oklch(0.32 0.012 60)`), `--border`/`--input` low-contrast warm (`oklch(0.92 0.004 85)`), `--muted-foreground` calmer (`oklch(0.55 0.01 60)`), `--sidebar` a tinted step off the background (`oklch(0.975 0.004 85)`).
- Dark: warm dark grays, never pure black (`--background` ≈ `oklch(0.22 0.006 60)`, `--sidebar` ≈ `oklch(0.2 0.006 60)`, borders ≈ `oklch(0.32 0.006 60)`).
- If the file defines `--shadow-*` or popover styling hooks, soften; otherwise leave shadows to component classes.

- [ ] **Step 2: Component polish (keep every testid)**

- `title-bar.tsx`: `border-b` → `border-b border-border/60`; app name `text-muted-foreground` stays, add `transition-colors`.
- `doc-tree.tsx`: icon spans get `text-muted-foreground`; menu buttons rely on sidebar primitives' hover but add `transition-colors duration-150` where classes are set.
- `sidebar-left.tsx`: "Hikki" wordmark `text-sm font-semibold tracking-tight`; New Page button `text-muted-foreground hover:text-foreground transition-colors`.
- `document-page.tsx`: editor column breathing room — outer wrapper `px-12 py-12` (was `px-8 py-10`); title input `placeholder:text-muted-foreground/50`.
- `dashboard-page.tsx`: heading `text-2xl font-semibold tracking-tight` with `text-muted-foreground` sub-line (calmer than `text-3xl font-bold`).

- [ ] **Step 3: Verify nothing broke**

Run: `pnpm test && pnpm exec tsc --noEmit && pnpm e2e`
Expected: all green (visual-only changes). Capture a screenshot for the report: with the dev server running, `pnpm exec playwright screenshot http://localhost:1420 /tmp/hikki-phase2-polish.png` (or a 3-line script if the CLI is unavailable) and note the path in your report.

- [ ] **Step 4: Commit**

```bash
git add src
git commit -m "style: soft Notion-like design pass — warm tokens, calm chrome

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 10: Documentation sync (run LAST)

**Files:**

- Modify: `CLAUDE.md`, `README.md`

- [ ] **Step 1: Update `CLAUDE.md`**

In the Architecture section, update/add these bullets (keep the rest):

- Under the Rust bullet, extend the module list: `asset.rs` (asset import + `hikki-asset://` URL resolution, traversal-checked), `fsx.rs` (atomic temp+rename writes).
- Add: `- **Assets:** imported via `import_asset`command into`documents/<uuid>/assets/`, served by the custom `hikki-asset://`protocol (vault-scoped, UUID + single-component filename validation). Frontend builds URLs with`backend.assetUrl`/`#lib/asset-url`.`
- Add: `- **Editor:** BlockNote (`#components/editor`) inside `src/pages/document-page.tsx`; block changes flow through the same debounced `save_document`autosave as the title. jsdom can't render BlockNote — unit tests mock`#components/editor`; real editor behavior is covered by Playwright.`
- Update the sidebar bullet: metas are served from the SQLite `documents` table (`Index::list_metas`), not fs scans.
- Update the testid convention line: `data-testid` attributes are stripped from production bundles by `babel-plugin-react-remove-properties` (see `vite.config.ts`); dev and test builds keep them.
- Add under Architecture: `- **Version history:** \`history.rs\` writes rolling snapshots to \`documents/<uuid>/history/\` on save (10-min coalescing, 50 kept); history UI arrives in Phase 6.`
- Add a Conventions bullet: `- Design language: soft Notion-like aesthetic per spec §14 — warm low-contrast tokens in \`globals.css\`, \`--radius: 0.625rem\`, muted chrome, 150–200ms transitions. Match it in all new UI.`

- [ ] **Step 2: Update `README.md`**

Change the Editor feature line from "(Phase 2)" to present tense: `- **Editor** — BlockNote block editor with slash commands, images and file attachments stored inside your vault; AI Writing Tools (Phase 3) and voice input (Phase 7) are next.`

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md README.md
git commit -m "docs: sync docs with phase 2 editor and asset pipeline

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Self-review notes

- **Coverage vs Phase-2 scope:** atomic writes ✅ (T1), corrupt-doc resilience ✅ (T1), index-backed metas ✅ (T2), asset import ✅ (T3), asset protocol + CSP ✅ (T4), TS asset layer ✅ (T5), BlockNote + block autosave ✅ (T6), page header icon/cover ✅ (T7), prod testid stripping ✅ (T8), e2e ✅ (T9), version-history snapshots ✅ (T11), soft design pass ✅ (T12), docs ✅ (T10, last). Deferred (named): AI slash items → Phase 3; templates/gradients/emoji-lib → Phase 6; watcher → later; block-URL portability across platforms (stored `hikki-asset://` URLs are platform-shaped) → noted for a future migration pass, acceptable for the macOS-first target.
- **Type consistency:** `ImportedAsset { fileName, url }` used by T5/T6/T7; `update(patch: Partial<Doc>)` defined in T6, consumed in T7; Rust `import_asset` returns stored file name (String) — TauriBackend builds the URL; `resolve_asset_path` consumes `"/<docId>/<fileName>"` which matches the URL shape `protocolAssetUrl` produces.
- **Known check-before-use points flagged inline:** base-ui `render` prop on PopoverTrigger (T7), BlockNote slash-menu DOM class (T9), negative margin on the editor wrapper (T6), `defineConfig` factory signature (T8).
