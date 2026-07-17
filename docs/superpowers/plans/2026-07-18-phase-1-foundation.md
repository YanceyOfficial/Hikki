# Hikki Phase 1 — Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Working vault storage (files as source of truth) + derived SQLite FTS5 index in Rust, a typed frontend backend layer with an in-memory browser fallback, hash routing with a macOS-aware AppShell, and a sidebar wired to the real document tree with create/delete/title-autosave.

**Architecture:** Rust owns all I/O (vault fs + rusqlite index) behind Tauri commands. The frontend talks only to a `Backend` interface: `TauriBackend` (invoke) inside Tauri, `MemoryBackend` in plain browsers — which is also what Playwright e2e drives. Jotai atoms hold the document tree; React Router (`createHashRouter`) renders Dashboard and Document pages inside an `AppShell` that handles traffic-light inset and window dragging.

**Tech Stack:** Tauri 2, Rust (rusqlite bundled/FTS5, uuid, chrono, thiserror, dirs, tempfile), React 19, react-router 8 (hash), Jotai, shadcn/ui, Vitest + @testing-library/react + jsdom, Playwright.

**Spec:** `docs/superpowers/specs/2026-07-18-hikki-design.md` (§2–§4, §12, phase 1 of §13). Later phases (editor, AI, settings, dashboard, extras, voice, updater) get their own plans.

## Global Constraints

- Package manager: **pnpm** (`pnpm add`, `pnpm exec`). Rust deps via `cargo add` from `src-tauri/`.
- **shadcn/ui first** — never hand-roll a UI primitive that exists in `src/components/ui`; install missing ones via `pnpm dlx shadcn@latest add <name>`.
- Import aliases (package.json `imports`): `#components/*`, `#lib/*`, `#hooks/*`.
- Every interactive element gets `data-testid`.
- TDD: write the failing test first, watch it fail, implement, watch it pass, commit.
- Commit messages: conventional commits, ending with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- Husky + lint-staged run oxlint/oxfmt on commit — if a commit fails on lint, fix and re-commit; never `--no-verify`.
- `document.json` schema and IPC payloads use **camelCase** keys (serde `rename_all = "camelCase"`; Tauri v2 maps JS `parentId` → Rust `parent_id` automatically).
- Timestamps are RFC-3339 UTC strings.

---

### Task 1: Baseline commit + Vitest infrastructure

**Files:**

- Create: `vitest.config.ts`, `src/lib/tree.test.ts` (placeholder moved to Task 6 — here just a smoke test),
- Modify: `package.json` (scripts, devDeps), `tsconfig.json` (vitest globals)

**Interfaces:**

- Produces: `pnpm test` (vitest run), `pnpm test:watch`. jsdom environment for all `src/**/*.test.{ts,tsx}`.

- [ ] **Step 1: Commit the untracked template as baseline**

```bash
git add -A
git commit -m "chore: baseline Tauri + React template

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

(The repo currently has only the two spec commits; all template files are untracked. `IMG_6065.jpeg` and `INIT_PROMPT.md` are committed too — they're referenced by the spec and removed in later phases.)

- [ ] **Step 2: Install test dependencies**

```bash
pnpm add -D jsdom @testing-library/react @testing-library/user-event
```

(vitest and @playwright/test are already installed.)

- [ ] **Step 3: Create `vitest.config.ts`**

```ts
import react from '@vitejs/plugin-react'
import { defineConfig } from 'vitest/config'

export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    globals: true,
    include: ['src/**/*.test.{ts,tsx}']
  }
})
```

- [ ] **Step 4: Add scripts and vitest globals types**

In `package.json` scripts add:

```json
"test": "vitest run",
"test:watch": "vitest"
```

In `tsconfig.json` `compilerOptions`, add `"types": ["vitest/globals"]` (append to the array if one exists).

- [ ] **Step 5: Write a smoke test to prove the harness works**

Create `src/lib/utils.test.ts`:

```ts
import { cn } from '#lib/utils'

test('cn merges tailwind classes', () => {
  expect(cn('p-2', 'p-4')).toBe('p-4')
})
```

- [ ] **Step 6: Run it**

Run: `pnpm test`
Expected: 1 passed. If the `#lib` alias fails to resolve under vitest, add to `vitest.config.ts`: `resolve: { alias: { '#components': new URL('./src/components', import.meta.url).pathname, '#lib': new URL('./src/lib', import.meta.url).pathname, '#hooks': new URL('./src/hooks', import.meta.url).pathname } }` and re-run.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "test: add vitest harness with jsdom + testing-library

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Rust error type + vault settings module

**Files:**

- Create: `src-tauri/src/error.rs`, `src-tauri/src/vault.rs`
- Modify: `src-tauri/Cargo.toml` (deps), `src-tauri/src/lib.rs` (declare modules)

**Interfaces:**

- Produces (used by Tasks 3–5):
  - `error::AppError` (variants `Io`, `Json`, `NotFound(String)`, `Index`), `error::Result<T>`; serializes to `{ "code": "HK-....", "message": "..." }`.
  - `vault::AppSettings { vault_path: PathBuf }`, `vault::load_settings(app_data_dir: &Path) -> AppSettings`, `vault::save_settings(app_data_dir: &Path, s: &AppSettings) -> std::io::Result<()>`, `vault::ensure_vault(root: &Path) -> std::io::Result<()>`, `vault::default_vault_path() -> PathBuf`.

- [ ] **Step 1: Add Rust dependencies**

```bash
cd src-tauri
cargo add thiserror dirs chrono
cargo add rusqlite --features bundled
cargo add uuid --features v4
cargo add --dev tempfile
cd ..
```

- [ ] **Step 2: Write failing tests inside `src-tauri/src/vault.rs`**

Create `src-tauri/src/vault.rs` with only a test module first:

```rust
use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn load_settings_defaults_when_missing() {
        let dir = tempfile::tempdir().unwrap();
        let s = load_settings(dir.path());
        assert_eq!(s.vault_path, default_vault_path());
    }

    #[test]
    fn settings_round_trip() {
        let dir = tempfile::tempdir().unwrap();
        let s = AppSettings { vault_path: PathBuf::from("/tmp/custom-vault") };
        save_settings(dir.path(), &s).unwrap();
        assert_eq!(load_settings(dir.path()), s);
    }

    #[test]
    fn ensure_vault_creates_layout() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path().join("MyVault");
        ensure_vault(&root).unwrap();
        assert!(root.join("documents").is_dir());
        assert!(root.join("vault.json").is_file());
        // idempotent
        ensure_vault(&root).unwrap();
    }
}
```

Declare modules in `src-tauri/src/lib.rs` (top of file):

```rust
mod error;
mod vault;
```

Create `src-tauri/src/error.rs` (needed to compile; it's exercised via later tasks' tests):

```rust
use serde::Serialize;

#[derive(Debug, thiserror::Error)]
pub enum AppError {
    #[error("io error: {0}")]
    Io(#[from] std::io::Error),
    #[error("invalid json: {0}")]
    Json(#[from] serde_json::Error),
    #[error("document not found: {0}")]
    NotFound(String),
    #[error("index error: {0}")]
    Index(#[from] rusqlite::Error),
}

impl AppError {
    pub fn code(&self) -> &'static str {
        match self {
            AppError::Io(_) => "HK-1001",
            AppError::Json(_) => "HK-1002",
            AppError::NotFound(_) => "HK-1003",
            AppError::Index(_) => "HK-2001",
        }
    }
}

#[derive(Serialize)]
struct ErrorPayload {
    code: &'static str,
    message: String,
}

impl Serialize for AppError {
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        ErrorPayload { code: self.code(), message: self.to_string() }.serialize(s)
    }
}

pub type Result<T> = std::result::Result<T, AppError>;
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cargo test --manifest-path src-tauri/Cargo.toml vault`
Expected: compile error — `load_settings`, `AppSettings`, etc. not found.

- [ ] **Step 4: Implement `vault.rs` (above the test module)**

```rust
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct AppSettings {
    pub vault_path: PathBuf,
}

pub fn default_vault_path() -> PathBuf {
    dirs::home_dir().unwrap_or_else(|| PathBuf::from(".")).join("Hikki")
}

pub fn load_settings(app_data_dir: &Path) -> AppSettings {
    fs::read_to_string(app_data_dir.join("settings.json"))
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_else(|| AppSettings { vault_path: default_vault_path() })
}

pub fn save_settings(app_data_dir: &Path, settings: &AppSettings) -> io::Result<()> {
    fs::create_dir_all(app_data_dir)?;
    let json = serde_json::to_string_pretty(settings).expect("settings serialize");
    fs::write(app_data_dir.join("settings.json"), json)
}

pub fn ensure_vault(root: &Path) -> io::Result<()> {
    fs::create_dir_all(root.join("documents"))?;
    let vault_file = root.join("vault.json");
    if !vault_file.exists() {
        fs::write(vault_file, "{}\n")?;
    }
    Ok(())
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cargo test --manifest-path src-tauri/Cargo.toml vault`
Expected: 3 passed.

- [ ] **Step 6: Commit**

```bash
git add src-tauri
git commit -m "feat(rust): vault settings module and HK-coded error type

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Rust document store (fs CRUD)

**Files:**

- Create: `src-tauri/src/document.rs`
- Modify: `src-tauri/src/lib.rs` (add `mod document;`)

**Interfaces:**

- Consumes: `vault::ensure_vault`, `error::{AppError, Result}`.
- Produces (used by Tasks 4–5):

```rust
pub struct Document {
    pub schema_version: u32,
    pub id: String,
    pub parent_id: Option<String>,
    pub title: String,
    pub icon: Option<String>,
    pub cover: Option<String>,
    pub blocks: serde_json::Value,   // BlockNote JSON array
    pub created_at: String,
    pub updated_at: String,
    pub deleted_at: Option<String>,
}
pub struct DocumentMeta { /* Document minus blocks/cover/schema_version */ }

pub fn create_document(vault: &Path, parent_id: Option<String>, title: &str) -> Result<Document>
pub fn load_document(vault: &Path, id: &str) -> Result<Document>
pub fn save_document(vault: &Path, doc: Document) -> Result<Document>  // bumps updated_at
pub fn delete_document(vault: &Path, id: &str) -> Result<Vec<String>> // soft, recursive; returns affected ids
pub fn list_documents(vault: &Path) -> Result<Vec<DocumentMeta>>
```

- [ ] **Step 1: Write failing tests**

Create `src-tauri/src/document.rs` starting with:

```rust
use std::fs;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::error::{AppError, Result};

#[cfg(test)]
mod tests {
    use super::*;

    fn vault() -> tempfile::TempDir {
        let dir = tempfile::tempdir().unwrap();
        crate::vault::ensure_vault(dir.path()).unwrap();
        dir
    }

    #[test]
    fn create_then_load_round_trips() {
        let v = vault();
        let doc = create_document(v.path(), None, "Hello").unwrap();
        assert_eq!(doc.schema_version, 1);
        assert!(doc.deleted_at.is_none());
        let loaded = load_document(v.path(), &doc.id).unwrap();
        assert_eq!(loaded.title, "Hello");
        assert_eq!(loaded.id, doc.id);
    }

    #[test]
    fn load_missing_is_not_found() {
        let v = vault();
        match load_document(v.path(), "nope") {
            Err(AppError::NotFound(_)) => {}
            other => panic!("expected NotFound, got {other:?}"),
        }
    }

    #[test]
    fn save_bumps_updated_at() {
        let v = vault();
        let doc = create_document(v.path(), None, "A").unwrap();
        let before = doc.updated_at.clone();
        std::thread::sleep(std::time::Duration::from_millis(5));
        let mut doc2 = doc.clone();
        doc2.title = "B".into();
        let saved = save_document(v.path(), doc2).unwrap();
        assert_eq!(saved.title, "B");
        assert!(saved.updated_at > before);
    }

    #[test]
    fn delete_is_soft_and_recursive() {
        let v = vault();
        let parent = create_document(v.path(), None, "P").unwrap();
        let child = create_document(v.path(), Some(parent.id.clone()), "C").unwrap();
        let affected = delete_document(v.path(), &parent.id).unwrap();
        assert_eq!(affected.len(), 2);
        let metas = list_documents(v.path()).unwrap();
        assert!(metas.iter().all(|m| m.deleted_at.is_some()));
        assert!(load_document(v.path(), &child.id).unwrap().deleted_at.is_some());
    }

    #[test]
    fn list_returns_metas_sorted_by_created_at() {
        let v = vault();
        create_document(v.path(), None, "first").unwrap();
        std::thread::sleep(std::time::Duration::from_millis(5));
        create_document(v.path(), None, "second").unwrap();
        let metas = list_documents(v.path()).unwrap();
        assert_eq!(metas.len(), 2);
        assert_eq!(metas[0].title, "first");
        assert_eq!(metas[1].title, "second");
    }
}
```

Add `mod document;` to `src-tauri/src/lib.rs`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cargo test --manifest-path src-tauri/Cargo.toml document`
Expected: compile error — types/functions not defined.

- [ ] **Step 3: Implement (above the test module)**

```rust
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Document {
    pub schema_version: u32,
    pub id: String,
    pub parent_id: Option<String>,
    pub title: String,
    pub icon: Option<String>,
    pub cover: Option<String>,
    pub blocks: serde_json::Value,
    pub created_at: String,
    pub updated_at: String,
    pub deleted_at: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DocumentMeta {
    pub id: String,
    pub parent_id: Option<String>,
    pub title: String,
    pub icon: Option<String>,
    pub created_at: String,
    pub updated_at: String,
    pub deleted_at: Option<String>,
}

impl From<&Document> for DocumentMeta {
    fn from(d: &Document) -> Self {
        DocumentMeta {
            id: d.id.clone(),
            parent_id: d.parent_id.clone(),
            title: d.title.clone(),
            icon: d.icon.clone(),
            created_at: d.created_at.clone(),
            updated_at: d.updated_at.clone(),
            deleted_at: d.deleted_at.clone(),
        }
    }
}

fn now() -> String {
    chrono::Utc::now().to_rfc3339()
}

fn doc_dir(vault: &Path, id: &str) -> PathBuf {
    vault.join("documents").join(id)
}

fn doc_file(vault: &Path, id: &str) -> PathBuf {
    doc_dir(vault, id).join("document.json")
}

fn write_doc(vault: &Path, doc: &Document) -> Result<()> {
    let dir = doc_dir(vault, &doc.id);
    fs::create_dir_all(dir.join("assets"))?;
    fs::write(doc_file(vault, &doc.id), serde_json::to_string_pretty(doc)?)?;
    Ok(())
}

pub fn create_document(vault: &Path, parent_id: Option<String>, title: &str) -> Result<Document> {
    let ts = now();
    let doc = Document {
        schema_version: 1,
        id: uuid::Uuid::new_v4().to_string(),
        parent_id,
        title: title.to_string(),
        icon: None,
        cover: None,
        blocks: serde_json::Value::Array(vec![]),
        created_at: ts.clone(),
        updated_at: ts,
        deleted_at: None,
    };
    write_doc(vault, &doc)?;
    Ok(doc)
}

pub fn load_document(vault: &Path, id: &str) -> Result<Document> {
    let path = doc_file(vault, id);
    if !path.is_file() {
        return Err(AppError::NotFound(id.to_string()));
    }
    Ok(serde_json::from_str(&fs::read_to_string(path)?)?)
}

pub fn save_document(vault: &Path, mut doc: Document) -> Result<Document> {
    // Guard against saving a document that was never created.
    load_document(vault, &doc.id)?;
    doc.updated_at = now();
    write_doc(vault, &doc)?;
    Ok(doc)
}

pub fn delete_document(vault: &Path, id: &str) -> Result<Vec<String>> {
    let metas = list_documents(vault)?;
    let mut affected = vec![id.to_string()];
    // Walk down the tree collecting descendants.
    let mut i = 0;
    while i < affected.len() {
        let current = affected[i].clone();
        for m in metas.iter().filter(|m| m.parent_id.as_deref() == Some(&current)) {
            affected.push(m.id.clone());
        }
        i += 1;
    }
    let ts = now();
    for doc_id in &affected {
        let mut doc = load_document(vault, doc_id)?;
        doc.deleted_at = Some(ts.clone());
        doc.updated_at = ts.clone();
        write_doc(vault, &doc)?;
    }
    Ok(affected)
}

pub fn list_documents(vault: &Path) -> Result<Vec<DocumentMeta>> {
    let mut metas = Vec::new();
    let documents_dir = vault.join("documents");
    for entry in fs::read_dir(&documents_dir)? {
        let entry = entry?;
        if !entry.path().is_dir() {
            continue;
        }
        let file = entry.path().join("document.json");
        if !file.is_file() {
            continue;
        }
        let doc: Document = serde_json::from_str(&fs::read_to_string(file)?)?;
        metas.push(DocumentMeta::from(&doc));
    }
    metas.sort_by(|a, b| a.created_at.cmp(&b.created_at));
    Ok(metas)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cargo test --manifest-path src-tauri/Cargo.toml document`
Expected: 5 passed.

- [ ] **Step 5: Commit**

```bash
git add src-tauri
git commit -m "feat(rust): document store with soft delete and recursive trash

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Rust SQLite index (FTS5, reconcile, search)

**Files:**

- Create: `src-tauri/src/index.rs`
- Modify: `src-tauri/src/lib.rs` (add `mod index;`)

**Interfaces:**

- Consumes: `document::{list_documents, load_document, Document}`, `error::Result`.
- Produces (used by Task 5):

```rust
pub struct Index { /* rusqlite::Connection */ }
pub struct SearchHit { pub id: String, pub title: String, pub snippet: String }

impl Index {
    pub fn open(path: &Path) -> Result<Index>          // creates schema
    pub fn open_in_memory() -> Result<Index>           // tests
    pub fn upsert(&self, doc: &Document) -> Result<()> // documents row + fts row
    pub fn remove(&self, id: &str) -> Result<()>
    pub fn search(&self, query: &str) -> Result<Vec<SearchHit>>
    pub fn reconcile(&mut self, vault: &Path) -> Result<usize> // full rebuild, returns doc count
}
pub fn extract_text(blocks: &serde_json::Value) -> String
```

- [ ] **Step 1: Write failing tests**

Create `src-tauri/src/index.rs` starting with:

```rust
use std::path::Path;

use rusqlite::Connection;
use serde::Serialize;

use crate::document::{self, Document};
use crate::error::Result;

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_blocks() -> serde_json::Value {
        serde_json::json!([
            {
                "id": "b1",
                "type": "paragraph",
                "content": [{ "type": "text", "text": "the quick brown fox", "styles": {} }],
                "children": [
                    {
                        "id": "b2",
                        "type": "paragraph",
                        "content": [{ "type": "text", "text": "jumps over", "styles": {} }],
                        "children": []
                    }
                ]
            }
        ])
    }

    fn doc_with(title: &str, blocks: serde_json::Value) -> Document {
        Document {
            schema_version: 1,
            id: uuid::Uuid::new_v4().to_string(),
            parent_id: None,
            title: title.into(),
            icon: None,
            cover: None,
            blocks,
            created_at: "2026-01-01T00:00:00Z".into(),
            updated_at: "2026-01-01T00:00:00Z".into(),
            deleted_at: None,
        }
    }

    #[test]
    fn extract_text_walks_content_and_children() {
        let text = extract_text(&sample_blocks());
        assert!(text.contains("quick brown fox"));
        assert!(text.contains("jumps over"));
    }

    #[test]
    fn upsert_then_search_finds_by_title_and_body() {
        let idx = Index::open_in_memory().unwrap();
        let doc = doc_with("Meeting notes", sample_blocks());
        idx.upsert(&doc).unwrap();

        let by_title = idx.search("meeting").unwrap();
        assert_eq!(by_title.len(), 1);
        assert_eq!(by_title[0].id, doc.id);

        let by_body = idx.search("quick bro").unwrap(); // prefix match
        assert_eq!(by_body.len(), 1);
        assert!(!by_body[0].snippet.is_empty());
    }

    #[test]
    fn upsert_replaces_not_duplicates() {
        let idx = Index::open_in_memory().unwrap();
        let mut doc = doc_with("One", sample_blocks());
        idx.upsert(&doc).unwrap();
        doc.title = "One renamed".into();
        idx.upsert(&doc).unwrap();
        assert_eq!(idx.search("renamed").unwrap().len(), 1);
        assert_eq!(idx.search("one").unwrap().len(), 1);
    }

    #[test]
    fn remove_drops_from_search() {
        let idx = Index::open_in_memory().unwrap();
        let doc = doc_with("Ephemeral", sample_blocks());
        idx.upsert(&doc).unwrap();
        idx.remove(&doc.id).unwrap();
        assert!(idx.search("ephemeral").unwrap().is_empty());
    }

    #[test]
    fn search_ignores_deleted_and_empty_query() {
        let idx = Index::open_in_memory().unwrap();
        let mut doc = doc_with("Trashed", sample_blocks());
        doc.deleted_at = Some("2026-01-02T00:00:00Z".into());
        idx.upsert(&doc).unwrap();
        assert!(idx.search("trashed").unwrap().is_empty());
        assert!(idx.search("   ").unwrap().is_empty());
    }

    #[test]
    fn reconcile_rebuilds_from_vault() {
        let dir = tempfile::tempdir().unwrap();
        crate::vault::ensure_vault(dir.path()).unwrap();
        document::create_document(dir.path(), None, "Alpha").unwrap();
        document::create_document(dir.path(), None, "Beta").unwrap();

        let mut idx = Index::open_in_memory().unwrap();
        let count = idx.reconcile(dir.path()).unwrap();
        assert_eq!(count, 2);
        assert_eq!(idx.search("alpha").unwrap().len(), 1);

        // Reconcile again: no duplicates.
        idx.reconcile(dir.path()).unwrap();
        assert_eq!(idx.search("alpha").unwrap().len(), 1);
    }
}
```

Add `mod index;` to `src-tauri/src/lib.rs`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cargo test --manifest-path src-tauri/Cargo.toml index`
Expected: compile error — `Index`, `extract_text` not defined.

- [ ] **Step 3: Implement (above the test module)**

```rust
pub struct Index {
    conn: Connection,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SearchHit {
    pub id: String,
    pub title: String,
    pub snippet: String,
}

const SCHEMA: &str = "
CREATE TABLE IF NOT EXISTS documents (
  id TEXT PRIMARY KEY,
  parent_id TEXT,
  title TEXT NOT NULL,
  icon TEXT,
  word_count INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT
);
CREATE VIRTUAL TABLE IF NOT EXISTS document_fts USING fts5(id UNINDEXED, title, body);
CREATE TABLE IF NOT EXISTS links (
  source_id TEXT NOT NULL,
  target_id TEXT NOT NULL,
  PRIMARY KEY (source_id, target_id)
);
CREATE TABLE IF NOT EXISTS activity (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  doc_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  word_delta INTEGER NOT NULL DEFAULT 0,
  at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
";

impl Index {
    pub fn open(path: &Path) -> Result<Index> {
        Self::from_conn(Connection::open(path)?)
    }

    pub fn open_in_memory() -> Result<Index> {
        Self::from_conn(Connection::open_in_memory()?)
    }

    fn from_conn(conn: Connection) -> Result<Index> {
        conn.execute_batch(SCHEMA)?;
        Ok(Index { conn })
    }

    pub fn upsert(&self, doc: &Document) -> Result<()> {
        let body = extract_text(&doc.blocks);
        let word_count = body.split_whitespace().count() as i64;
        self.conn.execute(
            "INSERT INTO documents (id, parent_id, title, icon, word_count, created_at, updated_at, deleted_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
             ON CONFLICT(id) DO UPDATE SET
               parent_id = excluded.parent_id, title = excluded.title, icon = excluded.icon,
               word_count = excluded.word_count, updated_at = excluded.updated_at,
               deleted_at = excluded.deleted_at",
            rusqlite::params![
                doc.id, doc.parent_id, doc.title, doc.icon, word_count,
                doc.created_at, doc.updated_at, doc.deleted_at
            ],
        )?;
        self.conn.execute("DELETE FROM document_fts WHERE id = ?1", [&doc.id])?;
        self.conn.execute(
            "INSERT INTO document_fts (id, title, body) VALUES (?1, ?2, ?3)",
            rusqlite::params![doc.id, doc.title, body],
        )?;
        Ok(())
    }

    pub fn remove(&self, id: &str) -> Result<()> {
        self.conn.execute("DELETE FROM documents WHERE id = ?1", [id])?;
        self.conn.execute("DELETE FROM document_fts WHERE id = ?1", [id])?;
        Ok(())
    }

    pub fn search(&self, query: &str) -> Result<Vec<SearchHit>> {
        let match_expr = fts_query(query);
        if match_expr.is_empty() {
            return Ok(vec![]);
        }
        let mut stmt = self.conn.prepare(
            "SELECT f.id, f.title, snippet(document_fts, 2, '<mark>', '</mark>', '…', 12)
             FROM document_fts f
             JOIN documents d ON d.id = f.id
             WHERE document_fts MATCH ?1 AND d.deleted_at IS NULL
             ORDER BY rank
             LIMIT 50",
        )?;
        let hits = stmt
            .query_map([&match_expr], |row| {
                Ok(SearchHit { id: row.get(0)?, title: row.get(1)?, snippet: row.get(2)? })
            })?
            .collect::<std::result::Result<Vec<_>, _>>()?;
        Ok(hits)
    }

    pub fn reconcile(&mut self, vault: &Path) -> Result<usize> {
        let tx = self.conn.transaction()?;
        tx.execute("DELETE FROM documents", [])?;
        tx.execute("DELETE FROM document_fts", [])?;
        tx.commit()?;
        let metas = document::list_documents(vault)?;
        for meta in &metas {
            let doc = document::load_document(vault, &meta.id)?;
            self.upsert(&doc)?;
        }
        Ok(metas.len())
    }
}

/// Quote each term and add prefix matching, so user input can't break FTS syntax.
fn fts_query(user: &str) -> String {
    user.split_whitespace()
        .map(|t| format!("\"{}\"*", t.replace('"', "")))
        .collect::<Vec<_>>()
        .join(" ")
}

/// Walk BlockNote JSON collecting inline text content, depth-first.
pub fn extract_text(blocks: &serde_json::Value) -> String {
    let mut out = Vec::new();
    collect_text(blocks, &mut out);
    out.join(" ")
}

fn collect_text(value: &serde_json::Value, out: &mut Vec<String>) {
    match value {
        serde_json::Value::Array(items) => {
            for item in items {
                collect_text(item, out);
            }
        }
        serde_json::Value::Object(map) => {
            if let Some(serde_json::Value::String(text)) = map.get("text") {
                out.push(text.clone());
            }
            for key in ["content", "children", "rows", "cells"] {
                if let Some(child) = map.get(key) {
                    collect_text(child, out);
                }
            }
        }
        _ => {}
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cargo test --manifest-path src-tauri/Cargo.toml index`
Expected: 6 passed. (If FTS5 is unavailable the `open_in_memory` tests will error on the virtual table — the `bundled` feature of rusqlite compiles SQLite with FTS5 enabled, so this passing also proves the build config.)

- [ ] **Step 5: Commit**

```bash
git add src-tauri
git commit -m "feat(rust): SQLite FTS5 index with reconcile and prefix search

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Tauri commands + app state wiring

**Files:**

- Create: `src-tauri/src/commands.rs`
- Modify: `src-tauri/src/lib.rs` (setup hook, state, handler registration; delete `greet`)

**Interfaces:**

- Consumes: everything from Tasks 2–4.
- Produces (the IPC surface Task 7's `TauriBackend` calls; all return `error::Result<T>` so failures serialize as `{code, message}`):
  - `get_vault_info() -> VaultInfo { vault_path: String, document_count: usize }`
  - `list_documents() -> Vec<DocumentMeta>`
  - `create_document(parent_id: Option<String>, title: String) -> Document`
  - `load_document(id: String) -> Document`
  - `save_document(doc: Document) -> Document`
  - `delete_document(id: String) -> Vec<String>`
  - `search(query: String) -> Vec<SearchHit>`
  - `rebuild_index() -> usize`
  - `set_vault_path(path: String) -> VaultInfo`

- [ ] **Step 1: Write failing tests**

Command handlers are thin; test the logic layer by writing `commands.rs` with a plain (non-`#[tauri::command]`) core that tests call directly:

```rust
use std::path::PathBuf;
use std::sync::Mutex;

use serde::Serialize;
use tauri::State;

use crate::document::{self, Document, DocumentMeta};
use crate::error::Result;
use crate::index::{Index, SearchHit};
use crate::vault::{self, AppSettings};

pub struct AppState {
    pub app_data_dir: PathBuf,
    pub settings: Mutex<AppSettings>,
    pub index: Mutex<Index>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct VaultInfo {
    pub vault_path: String,
    pub document_count: usize,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn state() -> (tempfile::TempDir, tempfile::TempDir, AppState) {
        let vault_dir = tempfile::tempdir().unwrap();
        let data_dir = tempfile::tempdir().unwrap();
        vault::ensure_vault(vault_dir.path()).unwrap();
        let state = AppState {
            app_data_dir: data_dir.path().to_path_buf(),
            settings: Mutex::new(AppSettings { vault_path: vault_dir.path().to_path_buf() }),
            index: Mutex::new(Index::open_in_memory().unwrap()),
        };
        (vault_dir, data_dir, state)
    }

    #[test]
    fn create_updates_index_and_vault_info() {
        let (_v, _d, state) = state();
        let doc = create_document_impl(&state, None, "Note".into()).unwrap();
        assert_eq!(doc.title, "Note");
        assert_eq!(search_impl(&state, "note".into()).unwrap().len(), 1);
        assert_eq!(get_vault_info_impl(&state).unwrap().document_count, 1);
    }

    #[test]
    fn save_reindexes() {
        let (_v, _d, state) = state();
        let mut doc = create_document_impl(&state, None, "Old title".into()).unwrap();
        doc.title = "New title".into();
        save_document_impl(&state, doc).unwrap();
        assert!(search_impl(&state, "old".into()).unwrap().is_empty());
        assert_eq!(search_impl(&state, "new".into()).unwrap().len(), 1);
    }

    #[test]
    fn delete_removes_from_search() {
        let (_v, _d, state) = state();
        let doc = create_document_impl(&state, None, "Gone".into()).unwrap();
        delete_document_impl(&state, doc.id).unwrap();
        assert!(search_impl(&state, "gone".into()).unwrap().is_empty());
        // still listed (soft-deleted) so Trash UI can show it later
        assert_eq!(list_documents_impl(&state).unwrap().len(), 1);
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cargo test --manifest-path src-tauri/Cargo.toml commands`
Expected: compile error — `*_impl` functions not defined.

- [ ] **Step 3: Implement the `_impl` layer + `#[tauri::command]` wrappers (same file, above tests)**

```rust
pub fn get_vault_info_impl(state: &AppState) -> Result<VaultInfo> {
    let settings = state.settings.lock().unwrap();
    let metas = document::list_documents(&settings.vault_path)?;
    Ok(VaultInfo {
        vault_path: settings.vault_path.to_string_lossy().into_owned(),
        document_count: metas.iter().filter(|m| m.deleted_at.is_none()).count(),
    })
}

pub fn list_documents_impl(state: &AppState) -> Result<Vec<DocumentMeta>> {
    let settings = state.settings.lock().unwrap();
    document::list_documents(&settings.vault_path)
}

pub fn create_document_impl(state: &AppState, parent_id: Option<String>, title: String) -> Result<Document> {
    let vault_path = state.settings.lock().unwrap().vault_path.clone();
    let doc = document::create_document(&vault_path, parent_id, &title)?;
    state.index.lock().unwrap().upsert(&doc)?;
    Ok(doc)
}

pub fn load_document_impl(state: &AppState, id: String) -> Result<Document> {
    let settings = state.settings.lock().unwrap();
    document::load_document(&settings.vault_path, &id)
}

pub fn save_document_impl(state: &AppState, doc: Document) -> Result<Document> {
    let vault_path = state.settings.lock().unwrap().vault_path.clone();
    let saved = document::save_document(&vault_path, doc)?;
    state.index.lock().unwrap().upsert(&saved)?;
    Ok(saved)
}

pub fn delete_document_impl(state: &AppState, id: String) -> Result<Vec<String>> {
    let vault_path = state.settings.lock().unwrap().vault_path.clone();
    let affected = document::delete_document(&vault_path, &id)?;
    let index = state.index.lock().unwrap();
    for doc_id in &affected {
        let doc = document::load_document(&vault_path, doc_id)?;
        index.upsert(&doc)?; // deleted_at now set → excluded from search
    }
    Ok(affected)
}

pub fn search_impl(state: &AppState, query: String) -> Result<Vec<SearchHit>> {
    state.index.lock().unwrap().search(&query)
}

pub fn rebuild_index_impl(state: &AppState) -> Result<usize> {
    let vault_path = state.settings.lock().unwrap().vault_path.clone();
    state.index.lock().unwrap().reconcile(&vault_path)
}

pub fn set_vault_path_impl(state: &AppState, path: String) -> Result<VaultInfo> {
    let new_root = PathBuf::from(path);
    vault::ensure_vault(&new_root)?;
    {
        let mut settings = state.settings.lock().unwrap();
        settings.vault_path = new_root;
        vault::save_settings(&state.app_data_dir, &settings)?;
    }
    rebuild_index_impl(state)?;
    get_vault_info_impl(state)
}

#[tauri::command]
pub fn get_vault_info(state: State<AppState>) -> Result<VaultInfo> {
    get_vault_info_impl(&state)
}

#[tauri::command]
pub fn list_documents(state: State<AppState>) -> Result<Vec<DocumentMeta>> {
    list_documents_impl(&state)
}

#[tauri::command]
pub fn create_document(state: State<AppState>, parent_id: Option<String>, title: String) -> Result<Document> {
    create_document_impl(&state, parent_id, title)
}

#[tauri::command]
pub fn load_document(state: State<AppState>, id: String) -> Result<Document> {
    load_document_impl(&state, id)
}

#[tauri::command]
pub fn save_document(state: State<AppState>, doc: Document) -> Result<Document> {
    save_document_impl(&state, doc)
}

#[tauri::command]
pub fn delete_document(state: State<AppState>, id: String) -> Result<Vec<String>> {
    delete_document_impl(&state, id)
}

#[tauri::command]
pub fn search(state: State<AppState>, query: String) -> Result<Vec<SearchHit>> {
    search_impl(&state, query)
}

#[tauri::command]
pub fn rebuild_index(state: State<AppState>) -> Result<usize> {
    rebuild_index_impl(&state)
}

#[tauri::command]
pub fn set_vault_path(state: State<AppState>, path: String) -> Result<VaultInfo> {
    set_vault_path_impl(&state, path)
}
```

Replace `src-tauri/src/lib.rs` entirely with:

```rust
mod commands;
mod document;
mod error;
mod index;
mod vault;

use std::sync::Mutex;

use tauri::Manager;

pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .setup(|app| {
            let app_data_dir = app.path().app_data_dir()?;
            std::fs::create_dir_all(&app_data_dir)?;
            let settings = vault::load_settings(&app_data_dir);
            vault::ensure_vault(&settings.vault_path)?;
            let mut idx = index::Index::open(&app_data_dir.join("index.db"))?;
            idx.reconcile(&settings.vault_path)?;
            app.manage(commands::AppState {
                app_data_dir,
                settings: Mutex::new(settings),
                index: Mutex::new(idx),
            });
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::get_vault_info,
            commands::list_documents,
            commands::create_document,
            commands::load_document,
            commands::save_document,
            commands::delete_document,
            commands::search,
            commands::rebuild_index,
            commands::set_vault_path,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
```

- [ ] **Step 4: Run all Rust tests + a full check**

Run: `cargo test --manifest-path src-tauri/Cargo.toml`
Expected: all tests pass (vault 3, document 5, index 6, commands 3).

Run: `cargo check --manifest-path src-tauri/Cargo.toml`
Expected: no errors (proves command macros/registration compile).

- [ ] **Step 5: Commit**

```bash
git add src-tauri
git commit -m "feat(rust): tauri command surface with managed vault/index state

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: TS domain types, tree builder, MemoryBackend

**Files:**

- Create: `src/lib/types.ts`, `src/lib/tree.ts`, `src/lib/tree.test.ts`, `src/lib/backend/backend.ts`, `src/lib/backend/memory-backend.ts`, `src/lib/backend/memory-backend.test.ts`

**Interfaces:**

- Produces (consumed by Tasks 7–10):

```ts
// types.ts
export interface DocumentMeta {
  id: string
  parentId: string | null
  title: string
  icon: string | null
  createdAt: string
  updatedAt: string
  deletedAt: string | null
}
export interface Doc extends DocumentMeta {
  schemaVersion: number
  cover: string | null
  blocks: unknown[]
}
export interface SearchHit {
  id: string
  title: string
  snippet: string
}
export interface VaultInfo {
  vaultPath: string
  documentCount: number
}

// tree.ts
export interface TreeNode {
  meta: DocumentMeta
  children: TreeNode[]
}
export function buildTree(metas: DocumentMeta[]): TreeNode[]

// backend/backend.ts
export interface Backend {
  getVaultInfo(): Promise<VaultInfo>
  listDocuments(): Promise<DocumentMeta[]>
  createDocument(parentId: string | null, title: string): Promise<Doc>
  loadDocument(id: string): Promise<Doc>
  saveDocument(doc: Doc): Promise<Doc>
  deleteDocument(id: string): Promise<string[]>
  search(query: string): Promise<SearchHit[]>
  rebuildIndex(): Promise<number>
}
```

- [ ] **Step 1: Write failing tests**

`src/lib/tree.test.ts`:

```ts
import { buildTree } from '#lib/tree'
import type { DocumentMeta } from '#lib/types'

const meta = (over: Partial<DocumentMeta>): DocumentMeta => ({
  id: 'x',
  parentId: null,
  title: '',
  icon: null,
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  deletedAt: null,
  ...over
})

test('nests children under parents', () => {
  const tree = buildTree([
    meta({ id: 'a', title: 'A' }),
    meta({ id: 'b', parentId: 'a', title: 'B' }),
    meta({ id: 'c', parentId: 'b', title: 'C' })
  ])
  expect(tree).toHaveLength(1)
  expect(tree[0].children[0].meta.id).toBe('b')
  expect(tree[0].children[0].children[0].meta.id).toBe('c')
})

test('excludes deleted documents and their subtrees', () => {
  const tree = buildTree([
    meta({ id: 'a', title: 'A', deletedAt: '2026-01-02T00:00:00Z' }),
    meta({ id: 'b', parentId: 'a', title: 'B' })
  ])
  expect(tree).toHaveLength(0)
})

test('orphans (missing parent) surface at root', () => {
  const tree = buildTree([meta({ id: 'b', parentId: 'ghost', title: 'B' })])
  expect(tree).toHaveLength(1)
  expect(tree[0].meta.id).toBe('b')
})

test('siblings sort by createdAt', () => {
  const tree = buildTree([
    meta({ id: 'later', createdAt: '2026-01-02T00:00:00Z' }),
    meta({ id: 'earlier', createdAt: '2026-01-01T00:00:00Z' })
  ])
  expect(tree.map((n) => n.meta.id)).toEqual(['earlier', 'later'])
})
```

`src/lib/backend/memory-backend.test.ts`:

```ts
import { MemoryBackend } from '#lib/backend/memory-backend'

test('create, list, load round trip', async () => {
  const b = new MemoryBackend()
  const doc = await b.createDocument(null, 'Hello')
  expect(doc.id).toBeTruthy()
  expect(await b.listDocuments()).toHaveLength(1)
  expect((await b.loadDocument(doc.id)).title).toBe('Hello')
})

test('load missing rejects with HK-1003 code', async () => {
  const b = new MemoryBackend()
  await expect(b.loadDocument('nope')).rejects.toMatchObject({
    code: 'HK-1003'
  })
})

test('save bumps updatedAt and persists changes', async () => {
  const b = new MemoryBackend()
  const doc = await b.createDocument(null, 'v1')
  const saved = await b.saveDocument({ ...doc, title: 'v2' })
  expect(saved.title).toBe('v2')
  expect(saved.updatedAt >= doc.updatedAt).toBe(true)
  expect((await b.loadDocument(doc.id)).title).toBe('v2')
})

test('delete is soft and recursive', async () => {
  const b = new MemoryBackend()
  const parent = await b.createDocument(null, 'P')
  const child = await b.createDocument(parent.id, 'C')
  const affected = await b.deleteDocument(parent.id)
  expect(affected.sort()).toEqual([parent.id, child.id].sort())
  const metas = await b.listDocuments()
  expect(metas.every((m) => m.deletedAt !== null)).toBe(true)
})

test('search matches title and body case-insensitively, skipping deleted', async () => {
  const b = new MemoryBackend()
  await b.createDocument(null, 'Groceries')
  const trashed = await b.createDocument(null, 'Trashed')
  await b.deleteDocument(trashed.id)
  expect(await b.search('gro')).toHaveLength(1)
  expect(await b.search('trashed')).toHaveLength(0)
  expect(await b.search('  ')).toHaveLength(0)
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pnpm test`
Expected: FAIL — modules `#lib/tree`, `#lib/backend/memory-backend` not found.

Note: `#lib/*` maps to `./src/lib/*.ts` only. For the `backend/` subdirectory to resolve, add to `package.json` `imports`: `"#lib/backend/*": "./src/lib/backend/*.ts"` (subpath patterns don't span directory separators reliably — add the explicit entry).

- [ ] **Step 3: Implement**

`src/lib/types.ts` — exactly the interfaces from the Interfaces block above.

`src/lib/tree.ts`:

```ts
import type { DocumentMeta } from '#lib/types'

export interface TreeNode {
  meta: DocumentMeta
  children: TreeNode[]
}

export function buildTree(metas: DocumentMeta[]): TreeNode[] {
  const alive = metas.filter((m) => m.deletedAt === null)
  const ids = new Set(alive.map((m) => m.id))
  const byParent = new Map<string | null, DocumentMeta[]>()
  for (const m of alive) {
    const key = m.parentId !== null && ids.has(m.parentId) ? m.parentId : null
    const list = byParent.get(key) ?? []
    list.push(m)
    byParent.set(key, list)
  }
  const build = (parentId: string | null): TreeNode[] =>
    (byParent.get(parentId) ?? [])
      .sort((a, b) => a.createdAt.localeCompare(b.createdAt))
      .map((meta) => ({ meta, children: build(meta.id) }))
  return build(null)
}
```

`src/lib/backend/backend.ts` — the `Backend` interface from the Interfaces block, importing types from `#lib/types`.

`src/lib/backend/memory-backend.ts`:

```ts
import type { Backend } from '#lib/backend/backend'
import type { Doc, DocumentMeta, SearchHit, VaultInfo } from '#lib/types'

const notFound = (id: string) =>
  Object.assign(new Error(`document not found: ${id}`), { code: 'HK-1003' })
const toMeta = ({
  schemaVersion: _s,
  cover: _c,
  blocks: _b,
  ...meta
}: Doc): DocumentMeta => meta

export class MemoryBackend implements Backend {
  private docs = new Map<string, Doc>()

  async getVaultInfo(): Promise<VaultInfo> {
    const alive = [...this.docs.values()].filter((d) => d.deletedAt === null)
    return { vaultPath: '(in-memory)', documentCount: alive.length }
  }

  async listDocuments(): Promise<DocumentMeta[]> {
    return [...this.docs.values()]
      .map(toMeta)
      .sort((a, b) => a.createdAt.localeCompare(b.createdAt))
  }

  async createDocument(parentId: string | null, title: string): Promise<Doc> {
    const now = new Date().toISOString()
    const doc: Doc = {
      schemaVersion: 1,
      id: crypto.randomUUID(),
      parentId,
      title,
      icon: null,
      cover: null,
      blocks: [],
      createdAt: now,
      updatedAt: now,
      deletedAt: null
    }
    this.docs.set(doc.id, doc)
    return structuredClone(doc)
  }

  async loadDocument(id: string): Promise<Doc> {
    const doc = this.docs.get(id)
    if (!doc) throw notFound(id)
    return structuredClone(doc)
  }

  async saveDocument(doc: Doc): Promise<Doc> {
    if (!this.docs.has(doc.id)) throw notFound(doc.id)
    const saved = {
      ...structuredClone(doc),
      updatedAt: new Date().toISOString()
    }
    this.docs.set(saved.id, saved)
    return structuredClone(saved)
  }

  async deleteDocument(id: string): Promise<string[]> {
    if (!this.docs.has(id)) throw notFound(id)
    const affected = [id]
    for (let i = 0; i < affected.length; i++) {
      for (const doc of this.docs.values()) {
        if (doc.parentId === affected[i]) affected.push(doc.id)
      }
    }
    const now = new Date().toISOString()
    for (const docId of affected) {
      const doc = this.docs.get(docId)!
      this.docs.set(docId, { ...doc, deletedAt: now, updatedAt: now })
    }
    return affected
  }

  async search(query: string): Promise<SearchHit[]> {
    const q = query.trim().toLowerCase()
    if (!q) return []
    return [...this.docs.values()]
      .filter((d) => d.deletedAt === null)
      .filter(
        (d) =>
          d.title.toLowerCase().includes(q) ||
          JSON.stringify(d.blocks).toLowerCase().includes(q)
      )
      .map((d) => ({ id: d.id, title: d.title, snippet: '' }))
  }

  async rebuildIndex(): Promise<number> {
    return [...this.docs.values()].length
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pnpm test`
Expected: all pass (tree 4, memory-backend 5, plus Task 1 smoke).

- [ ] **Step 5: Commit**

```bash
git add src package.json
git commit -m "feat: domain types, tree builder, in-memory backend

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: TauriBackend + backend selection

**Files:**

- Create: `src/lib/backend/tauri-backend.ts`, `src/lib/backend/tauri-backend.test.ts`, `src/lib/backend/index.ts`

**Interfaces:**

- Consumes: `Backend` interface, Task 5's command names/payloads.
- Produces: `import { backend } from '#lib/backend/index'` — the singleton every component/atom uses. `TauriBackend` maps camelCase args to the Tauri commands 1:1.

- [ ] **Step 1: Write failing tests**

`src/lib/backend/tauri-backend.test.ts`:

```ts
import { clearMocks, mockIPC } from '@tauri-apps/api/mocks'

import { TauriBackend } from '#lib/backend/tauri-backend'
import type { Doc } from '#lib/types'

const fixture: Doc = {
  schemaVersion: 1,
  id: 'doc-1',
  parentId: null,
  title: 'Hello',
  icon: null,
  cover: null,
  blocks: [],
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  deletedAt: null
}

afterEach(() => clearMocks())

test('createDocument invokes create_document with camelCase args', async () => {
  const calls: Array<[string, unknown]> = []
  mockIPC((cmd, args) => {
    calls.push([cmd, args])
    return fixture
  })
  const doc = await new TauriBackend().createDocument(null, 'Hello')
  expect(calls).toEqual([
    ['create_document', { parentId: null, title: 'Hello' }]
  ])
  expect(doc.title).toBe('Hello')
})

test('search and delete map their commands', async () => {
  const calls: Array<[string, unknown]> = []
  mockIPC((cmd, args) => {
    calls.push([cmd, args])
    if (cmd === 'search') return []
    if (cmd === 'delete_document') return ['doc-1']
    return null
  })
  const b = new TauriBackend()
  await b.search('fox')
  await b.deleteDocument('doc-1')
  expect(calls).toEqual([
    ['search', { query: 'fox' }],
    ['delete_document', { id: 'doc-1' }]
  ])
})

test('rust error payloads reject with code intact', async () => {
  mockIPC(() =>
    Promise.reject({ code: 'HK-1003', message: 'document not found: x' })
  )
  await expect(new TauriBackend().loadDocument('x')).rejects.toMatchObject({
    code: 'HK-1003'
  })
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pnpm test`
Expected: FAIL — `#lib/backend/tauri-backend` not found.

- [ ] **Step 3: Implement**

`src/lib/backend/tauri-backend.ts`:

```ts
import { invoke } from '@tauri-apps/api/core'

import type { Backend } from '#lib/backend/backend'
import type { Doc, DocumentMeta, SearchHit, VaultInfo } from '#lib/types'

export class TauriBackend implements Backend {
  getVaultInfo() {
    return invoke<VaultInfo>('get_vault_info')
  }
  listDocuments() {
    return invoke<DocumentMeta[]>('list_documents')
  }
  createDocument(parentId: string | null, title: string) {
    return invoke<Doc>('create_document', { parentId, title })
  }
  loadDocument(id: string) {
    return invoke<Doc>('load_document', { id })
  }
  saveDocument(doc: Doc) {
    return invoke<Doc>('save_document', { doc })
  }
  deleteDocument(id: string) {
    return invoke<string[]>('delete_document', { id })
  }
  search(query: string) {
    return invoke<SearchHit[]>('search', { query })
  }
  rebuildIndex() {
    return invoke<number>('rebuild_index')
  }
}
```

`src/lib/backend/index.ts`:

```ts
import type { Backend } from '#lib/backend/backend'
import { MemoryBackend } from '#lib/backend/memory-backend'
import { TauriBackend } from '#lib/backend/tauri-backend'

export const isTauri = () =>
  typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window

/** Singleton backend: real Tauri IPC inside the app, in-memory in plain browsers (dev + Playwright). */
export const backend: Backend = isTauri()
  ? new TauriBackend()
  : new MemoryBackend()
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pnpm test`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add src
git commit -m "feat: tauri backend over IPC with browser fallback selection

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: Router + AppShell with macOS titlebar

**Files:**

- Create: `src/components/app-shell.tsx`, `src/components/title-bar.tsx`, `src/components/title-bar.test.tsx`, `src/hooks/use-traffic-light-inset.ts`, `src/pages/dashboard-page.tsx`, `src/pages/document-page.tsx` (placeholder here; real content in Task 10)
- Modify: `src/main.tsx`, `package.json` (`imports`: add `"#pages/*": "./src/pages/*.tsx"`)
- Delete: nothing yet (`src/containers/app.tsx` is removed in Task 9 when the sidebar moves)

**Interfaces:**

- Consumes: nothing new.
- Produces: `AppShell` layout route (renders `TitleBar` + `SidebarProvider` + `Outlet`); `useTrafficLightInset(): boolean`; routes `/` → `DashboardPage`, `/doc/:id` → `DocumentPage`.

- [ ] **Step 1: Write failing test**

`src/components/title-bar.test.tsx`:

```tsx
import { render, screen } from '@testing-library/react'
import { MemoryRouter } from 'react-router'

import { TitleBar } from '#components/title-bar'
import { SidebarProvider } from '#components/ui/sidebar'

const renderBar = () =>
  render(
    <MemoryRouter>
      <SidebarProvider>
        <TitleBar />
      </SidebarProvider>
    </MemoryRouter>
  )

test('titlebar is a drag region', () => {
  renderBar()
  const bar = screen.getByTestId('titlebar')
  expect(bar).toHaveAttribute('data-tauri-drag-region')
})

test('no traffic-light inset outside Tauri', () => {
  renderBar()
  expect(screen.getByTestId('titlebar').className).not.toContain('pl-[76px]')
})

test('renders sidebar toggle', () => {
  renderBar()
  expect(screen.getByTestId('sidebar-toggle')).toBeInTheDocument()
})
```

`toHaveAttribute`/`toBeInTheDocument` need jest-dom: `pnpm add -D @testing-library/jest-dom`, create `src/test-setup.ts` containing `import '@testing-library/jest-dom/vitest'`, and add `setupFiles: ['./src/test-setup.ts']` to the `test` block of `vitest.config.ts`.

- [ ] **Step 2: Run test to verify it fails**

Run: `pnpm test`
Expected: FAIL — `#components/title-bar` not found.

- [ ] **Step 3: Implement**

`src/hooks/use-traffic-light-inset.ts`:

```ts
import { useEffect, useState } from 'react'

const isMacTauri = () =>
  typeof window !== 'undefined' &&
  '__TAURI_INTERNALS__' in window &&
  navigator.userAgent.includes('Mac')

/**
 * True when the macOS traffic lights overlay our window chrome (Tauri, macOS,
 * windowed). False in fullscreen — macOS hides the buttons there.
 */
export function useTrafficLightInset(): boolean {
  const [fullscreen, setFullscreen] = useState(false)

  useEffect(() => {
    if (!isMacTauri()) return
    let unlisten: (() => void) | undefined
    let cancelled = false
    import('@tauri-apps/api/window').then(async ({ getCurrentWindow }) => {
      if (cancelled) return
      const win = getCurrentWindow()
      const sync = () =>
        win
          .isFullscreen()
          .then(setFullscreen)
          .catch(() => {})
      sync()
      unlisten = await win.onResized(sync)
    })
    return () => {
      cancelled = true
      unlisten?.()
    }
  }, [])

  return isMacTauri() && !fullscreen
}
```

`src/components/title-bar.tsx`:

```tsx
import { Separator } from '#components/ui/separator'
import { SidebarTrigger } from '#components/ui/sidebar'
import { useTrafficLightInset } from '#hooks/use-traffic-light-inset'
import { cn } from '#lib/utils'

export function TitleBar() {
  const inset = useTrafficLightInset()
  return (
    <header
      data-tauri-drag-region
      data-testid="titlebar"
      className={cn(
        'bg-background flex h-11 shrink-0 items-center gap-2 border-b px-3',
        inset && 'pl-[76px]'
      )}
    >
      <SidebarTrigger data-testid="sidebar-toggle" />
      <Separator
        orientation="vertical"
        className="mr-1 data-[orientation=vertical]:h-4"
      />
      <span
        data-tauri-drag-region
        className="text-muted-foreground select-none text-sm font-medium"
      >
        Hikki
      </span>
    </header>
  )
}
```

`src/components/app-shell.tsx`:

```tsx
import { Outlet } from 'react-router'

import { SidebarLeft } from '#components/sidebar-left'
import { TitleBar } from '#components/title-bar'
import { SidebarInset, SidebarProvider } from '#components/ui/sidebar'

export function AppShell() {
  return (
    <SidebarProvider>
      <SidebarLeft />
      <SidebarInset className="h-svh overflow-hidden">
        <TitleBar />
        <main
          data-testid="page-content"
          className="min-h-0 flex-1 overflow-y-auto"
        >
          <Outlet />
        </main>
      </SidebarInset>
    </SidebarProvider>
  )
}
```

`src/pages/dashboard-page.tsx`:

```tsx
export default function DashboardPage() {
  return (
    <div data-testid="dashboard-page" className="mx-auto w-full max-w-3xl p-8">
      <h1 className="text-3xl font-bold">Dashboard</h1>
      <p className="text-muted-foreground mt-2 text-sm">
        Charts arrive in Phase 5.
      </p>
    </div>
  )
}
```

`src/pages/document-page.tsx` (placeholder — Task 10 replaces it):

```tsx
export default function DocumentPage() {
  return <div data-testid="document-page" />
}
```

Replace `src/main.tsx`:

```tsx
import React from 'react'
import ReactDOM from 'react-dom/client'
import { createHashRouter, RouterProvider } from 'react-router'

import { AppShell } from '#components/app-shell'
import DashboardPage from '#pages/dashboard-page'
import DocumentPage from '#pages/document-page'

const router = createHashRouter([
  {
    path: '/',
    Component: AppShell,
    children: [
      { index: true, Component: DashboardPage },
      { path: 'doc/:id', Component: DocumentPage }
    ]
  }
])

ReactDOM.createRoot(document.getElementById('root') as HTMLElement).render(
  <React.StrictMode>
    <RouterProvider router={router} />
  </React.StrictMode>
)
```

Add `"#pages/*": "./src/pages/*.tsx"` to `package.json` `imports`.

- [ ] **Step 4: Run tests + typecheck**

Run: `pnpm test`
Expected: all pass.

Run: `pnpm exec tsc --noEmit`
Expected: clean. (`SidebarLeft` still renders template sample data — that's Task 9.)

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: hash router with AppShell and macOS-aware titlebar

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 9: Sidebar wired to real document tree

**Files:**

- Create: `src/lib/store.ts`, `src/components/doc-tree.tsx`, `src/components/doc-tree.test.tsx`
- Modify: `src/components/sidebar-left.tsx` (full rewrite)
- Delete: `src/containers/app.tsx`, `src/components/nav-workspaces.tsx`, `src/components/nav-favorites.tsx`, `src/components/team-switcher.tsx`, `src/components/sidebar-right.tsx`, `src/components/calendars.tsx`, `src/components/date-picker.tsx` (template sample components; favorites/right-sidebar return in later phases backed by real data)

**Interfaces:**

- Consumes: `backend`, `buildTree`, `TreeNode`.
- Produces:
  - `store.ts`: `docMetasAtom: Atom<DocumentMeta[]>` (primitive, default `[]`), `refreshDocsAtom` (write-only: fetches `backend.listDocuments()` into `docMetasAtom`).
  - `DocTree` pure component: `{ nodes: TreeNode[]; activeId?: string; onSelect(id: string): void; onDelete(id: string): void }`.

- [ ] **Step 1: Write failing test**

`src/components/doc-tree.test.tsx`:

```tsx
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'

import { DocTree } from '#components/doc-tree'
import { SidebarProvider } from '#components/ui/sidebar'
import type { TreeNode } from '#lib/tree'
import type { DocumentMeta } from '#lib/types'

const meta = (id: string, title: string): DocumentMeta => ({
  id,
  parentId: null,
  title,
  icon: null,
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  deletedAt: null
})

const nodes: TreeNode[] = [
  {
    meta: meta('a', 'Parent'),
    children: [{ meta: meta('b', 'Child'), children: [] }]
  }
]

const setup = (over: Partial<React.ComponentProps<typeof DocTree>> = {}) => {
  const onSelect = vi.fn()
  const onDelete = vi.fn()
  render(
    <SidebarProvider>
      <DocTree
        nodes={nodes}
        onSelect={onSelect}
        onDelete={onDelete}
        {...over}
      />
    </SidebarProvider>
  )
  return { onSelect, onDelete }
}

test('renders nested titles', () => {
  setup()
  expect(screen.getByText('Parent')).toBeInTheDocument()
  expect(screen.getByText('Child')).toBeInTheDocument()
})

test('untitled documents get a fallback label', () => {
  const onSelect = vi.fn()
  render(
    <SidebarProvider>
      <DocTree
        nodes={[{ meta: meta('x', ''), children: [] }]}
        onSelect={onSelect}
        onDelete={vi.fn()}
      />
    </SidebarProvider>
  )
  expect(screen.getByText('Untitled')).toBeInTheDocument()
})

test('clicking a row selects it', async () => {
  const { onSelect } = setup()
  await userEvent.click(screen.getByText('Child'))
  expect(onSelect).toHaveBeenCalledWith('b')
})

test('delete action fires onDelete', async () => {
  const { onDelete } = setup()
  await userEvent.click(screen.getByTestId('doc-actions-a'))
  await userEvent.click(await screen.findByTestId('doc-delete-a'))
  expect(onDelete).toHaveBeenCalledWith('a')
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pnpm test`
Expected: FAIL — `#components/doc-tree` not found.

- [ ] **Step 3: Implement `DocTree` and the store**

`src/lib/store.ts`:

```ts
import { atom } from 'jotai'

import { backend } from '#lib/backend/index'
import type { DocumentMeta } from '#lib/types'

export const docMetasAtom = atom<DocumentMeta[]>([])

export const refreshDocsAtom = atom(null, async (_get, set) => {
  set(docMetasAtom, await backend.listDocuments())
})
```

`src/components/doc-tree.tsx`:

```tsx
import { ChevronRight, FileText, MoreHorizontal, Trash2 } from 'lucide-react'

import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger
} from '#components/ui/collapsible'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger
} from '#components/ui/dropdown-menu'
import {
  SidebarGroup,
  SidebarGroupContent,
  SidebarGroupLabel,
  SidebarMenu,
  SidebarMenuAction,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarMenuSub
} from '#components/ui/sidebar'
import type { TreeNode } from '#lib/tree'

interface DocTreeProps {
  nodes: TreeNode[]
  activeId?: string
  onSelect: (id: string) => void
  onDelete: (id: string) => void
}

function TreeItem({
  node,
  activeId,
  onSelect,
  onDelete
}: { node: TreeNode } & Omit<DocTreeProps, 'nodes'>) {
  const { meta, children } = node
  return (
    <Collapsible defaultOpen>
      <SidebarMenuItem>
        <SidebarMenuButton
          isActive={meta.id === activeId}
          onClick={() => onSelect(meta.id)}
          data-testid={`doc-item-${meta.id}`}
        >
          <span className="flex size-4 items-center justify-center">
            {meta.icon ?? <FileText className="size-4" />}
          </span>
          <span className="truncate">{meta.title || 'Untitled'}</span>
        </SidebarMenuButton>
        {children.length > 0 && (
          <CollapsibleTrigger asChild>
            <SidebarMenuAction
              className="left-1 bg-transparent"
              showOnHover
              data-testid={`doc-toggle-${meta.id}`}
            >
              <ChevronRight className="transition-transform data-[state=open]:rotate-90" />
            </SidebarMenuAction>
          </CollapsibleTrigger>
        )}
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <SidebarMenuAction
              showOnHover
              data-testid={`doc-actions-${meta.id}`}
            >
              <MoreHorizontal />
            </SidebarMenuAction>
          </DropdownMenuTrigger>
          <DropdownMenuContent side="right" align="start">
            <DropdownMenuItem
              variant="destructive"
              onClick={() => onDelete(meta.id)}
              data-testid={`doc-delete-${meta.id}`}
            >
              <Trash2 />
              Move to Trash
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
        {children.length > 0 && (
          <CollapsibleContent>
            <SidebarMenuSub className="mr-0 pr-0">
              {children.map((child) => (
                <TreeItem
                  key={child.meta.id}
                  node={child}
                  activeId={activeId}
                  onSelect={onSelect}
                  onDelete={onDelete}
                />
              ))}
            </SidebarMenuSub>
          </CollapsibleContent>
        )}
      </SidebarMenuItem>
    </Collapsible>
  )
}

export function DocTree({ nodes, activeId, onSelect, onDelete }: DocTreeProps) {
  return (
    <SidebarGroup>
      <SidebarGroupLabel>Documents</SidebarGroupLabel>
      <SidebarGroupContent>
        <SidebarMenu data-testid="doc-tree">
          {nodes.map((node) => (
            <TreeItem
              key={node.meta.id}
              node={node}
              activeId={activeId}
              onSelect={onSelect}
              onDelete={onDelete}
            />
          ))}
        </SidebarMenu>
      </SidebarGroupContent>
    </SidebarGroup>
  )
}
```

(If `DropdownMenuItem` in `src/components/ui/dropdown-menu.tsx` has no `variant` prop, drop the prop — check the file before using it.)

- [ ] **Step 4: Run test to verify DocTree passes**

Run: `pnpm test`
Expected: doc-tree tests pass.

- [ ] **Step 5: Rewrite `src/components/sidebar-left.tsx`**

```tsx
import { LayoutDashboard, Plus } from 'lucide-react'
import { useAtomValue, useSetAtom } from 'jotai'
import { useEffect, useMemo } from 'react'
import { useLocation, useNavigate } from 'react-router'

import { DocTree } from '#components/doc-tree'
import { Button } from '#components/ui/button'
import {
  Sidebar,
  SidebarContent,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem
} from '#components/ui/sidebar'
import { backend } from '#lib/backend/index'
import { docMetasAtom, refreshDocsAtom } from '#lib/store'
import { buildTree } from '#lib/tree'

export function SidebarLeft(props: React.ComponentProps<typeof Sidebar>) {
  const metas = useAtomValue(docMetasAtom)
  const refresh = useSetAtom(refreshDocsAtom)
  const navigate = useNavigate()
  const location = useLocation()

  useEffect(() => {
    refresh()
  }, [refresh])

  const nodes = useMemo(() => buildTree(metas), [metas])
  const activeId = location.pathname.startsWith('/doc/')
    ? location.pathname.slice('/doc/'.length)
    : undefined

  const createDoc = async () => {
    const doc = await backend.createDocument(null, '')
    await refresh()
    navigate(`/doc/${doc.id}`)
  }

  const deleteDoc = async (id: string) => {
    await backend.deleteDocument(id)
    await refresh()
    if (id === activeId) navigate('/')
  }

  return (
    <Sidebar className="border-r-0" {...props}>
      <SidebarHeader>
        <div className="flex items-center justify-between px-2 pt-1">
          <span className="text-base font-semibold">Hikki</span>
          <Button
            variant="ghost"
            size="icon"
            className="size-7"
            onClick={createDoc}
            data-testid="new-doc"
          >
            <Plus />
            <span className="sr-only">New page</span>
          </Button>
        </div>
        <SidebarMenu>
          <SidebarMenuItem>
            <SidebarMenuButton
              isActive={location.pathname === '/'}
              onClick={() => navigate('/')}
              data-testid="nav-dashboard"
            >
              <LayoutDashboard />
              Dashboard
            </SidebarMenuButton>
          </SidebarMenuItem>
        </SidebarMenu>
      </SidebarHeader>
      <SidebarContent>
        <DocTree
          nodes={nodes}
          activeId={activeId}
          onSelect={(id) => navigate(`/doc/${id}`)}
          onDelete={deleteDoc}
        />
      </SidebarContent>
    </Sidebar>
  )
}
```

Delete the template sample components listed in **Files → Delete** and remove `src/containers/app.tsx`. Then run `pnpm exec tsc --noEmit`; if other template files (e.g. `nav-main.tsx`, `nav-secondary.tsx`, `settings-dialog.tsx`) still compile-error on deleted imports, remove the dead imports — keep `settings-dialog.tsx` itself (spec requires it in Phase 4) and `nav-user.tsx` if referenced, otherwise leave them untouched.

- [ ] **Step 6: Run everything**

Run: `pnpm test && pnpm exec tsc --noEmit`
Expected: all green.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: sidebar driven by real document tree with create/delete

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 10: Document page with title autosave

**Files:**

- Create: `src/lib/debounce.ts`, `src/lib/debounce.test.ts`, `src/pages/document-page.test.tsx`
- Modify: `src/pages/document-page.tsx` (replace placeholder)

**Interfaces:**

- Consumes: `backend`, `refreshDocsAtom`.
- Produces: `debounce<F>(fn: F, ms: number): F & { flush(): void }`; a document page that loads by route param, edits title, autosaves at 800 ms, flushes on unmount.

- [ ] **Step 1: Write failing tests**

`src/lib/debounce.test.ts`:

```ts
import { debounce } from '#lib/debounce'

beforeEach(() => vi.useFakeTimers())
afterEach(() => vi.useRealTimers())

test('collapses rapid calls into the last one', () => {
  const fn = vi.fn()
  const d = debounce(fn, 100)
  d('a')
  d('b')
  vi.advanceTimersByTime(99)
  expect(fn).not.toHaveBeenCalled()
  vi.advanceTimersByTime(1)
  expect(fn).toHaveBeenCalledExactlyOnceWith('b')
})

test('flush runs a pending call immediately', () => {
  const fn = vi.fn()
  const d = debounce(fn, 100)
  d('x')
  d.flush()
  expect(fn).toHaveBeenCalledExactlyOnceWith('x')
  vi.advanceTimersByTime(200)
  expect(fn).toHaveBeenCalledTimes(1)
})

test('flush without pending call is a no-op', () => {
  const fn = vi.fn()
  debounce(fn, 100).flush()
  expect(fn).not.toHaveBeenCalled()
})
```

`src/pages/document-page.test.tsx`:

```tsx
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter, Route, Routes } from 'react-router'

import { backend } from '#lib/backend/index'
import DocumentPage from '#pages/document-page'

const renderPage = (id: string) =>
  render(
    <MemoryRouter initialEntries={[`/doc/${id}`]}>
      <Routes>
        <Route path="/doc/:id" element={<DocumentPage />} />
      </Routes>
    </MemoryRouter>
  )

test('loads and shows the document title', async () => {
  const doc = await backend.createDocument(null, 'My note')
  renderPage(doc.id)
  expect(await screen.findByTestId('doc-title')).toHaveValue('My note')
})

test('typing autosaves after debounce', async () => {
  const doc = await backend.createDocument(null, '')
  renderPage(doc.id)
  const input = await screen.findByTestId('doc-title')
  await userEvent.type(input, 'Renamed')
  await waitFor(
    async () =>
      expect((await backend.loadDocument(doc.id)).title).toBe('Renamed'),
    {
      timeout: 3000
    }
  )
})

test('unknown id shows not-found state', async () => {
  renderPage('missing-id')
  expect(await screen.findByTestId('doc-not-found')).toBeInTheDocument()
})
```

(In vitest/jsdom there is no `__TAURI_INTERNALS__`, so `backend` is the `MemoryBackend` singleton — tests read/write it directly.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `pnpm test`
Expected: debounce FAIL (module missing); document-page FAIL (`doc-title` never appears).

- [ ] **Step 3: Implement**

`src/lib/debounce.ts`:

```ts
export function debounce<A extends unknown[]>(
  fn: (...args: A) => void,
  ms: number
) {
  let timer: ReturnType<typeof setTimeout> | undefined
  let pending: A | undefined
  const run = () => {
    if (!pending) return
    const args = pending
    pending = undefined
    fn(...args)
  }
  const debounced = (...args: A) => {
    pending = args
    clearTimeout(timer)
    timer = setTimeout(run, ms)
  }
  debounced.flush = () => {
    clearTimeout(timer)
    run()
  }
  return debounced
}
```

`src/pages/document-page.tsx`:

```tsx
import { useSetAtom } from 'jotai'
import { useEffect, useMemo, useRef, useState } from 'react'
import { useParams } from 'react-router'

import { backend } from '#lib/backend/index'
import { debounce } from '#lib/debounce'
import { refreshDocsAtom } from '#lib/store'
import type { Doc } from '#lib/types'

export default function DocumentPage() {
  const { id } = useParams<{ id: string }>()
  const [doc, setDoc] = useState<Doc | null>(null)
  const [notFound, setNotFound] = useState(false)
  const refresh = useSetAtom(refreshDocsAtom)
  const latest = useRef<Doc | null>(null)

  const save = useMemo(
    () =>
      debounce((next: Doc) => {
        backend.saveDocument(next).then(() => refresh())
      }, 800),
    [refresh]
  )

  useEffect(() => {
    let active = true
    setDoc(null)
    setNotFound(false)
    backend
      .loadDocument(id!)
      .then((loaded) => {
        if (active) {
          setDoc(loaded)
          latest.current = loaded
        }
      })
      .catch(() => active && setNotFound(true))
    return () => {
      active = false
      save.flush()
    }
  }, [id, save])

  if (notFound) {
    return (
      <div
        data-testid="doc-not-found"
        className="text-muted-foreground p-8 text-sm"
      >
        This page doesn't exist (it may have been deleted).
      </div>
    )
  }
  if (!doc) return null

  const update = (next: Doc) => {
    setDoc(next)
    latest.current = next
    save(next)
  }

  return (
    <div
      data-testid="document-page"
      className="mx-auto w-full max-w-3xl px-8 py-10"
    >
      <input
        data-testid="doc-title"
        className="w-full bg-transparent text-4xl font-bold outline-none"
        placeholder="Untitled"
        value={doc.title}
        onChange={(e) => update({ ...doc, title: e.target.value })}
      />
      <p
        data-testid="editor-placeholder"
        className="text-muted-foreground mt-6 text-sm"
      >
        The editor lands in Phase 2.
      </p>
    </div>
  )
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pnpm test`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add src
git commit -m "feat: document page with debounced title autosave

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 11: Playwright e2e smoke + manual Tauri run

**Files:**

- Create: `e2e-tests/app.spec.ts`
- Modify: `playwright.config.ts` (webServer + baseURL), `package.json` (script `"e2e": "playwright test"`)
- Delete: `e2e-tests/example.spec.ts`

**Interfaces:**

- Consumes: the running Vite dev server (MemoryBackend active — no Tauri).
- Produces: `pnpm e2e` green in CI and locally.

- [ ] **Step 1: Write the failing e2e test**

Replace `playwright.config.ts` content's `use`/`webServer` so it reads (keep existing projects config if present):

```ts
import { defineConfig, devices } from '@playwright/test'

export default defineConfig({
  testDir: './e2e-tests',
  use: { baseURL: 'http://localhost:1420' },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
  webServer: {
    command: 'pnpm dev',
    port: 1420,
    reuseExistingServer: !process.env.CI
  }
})
```

Create `e2e-tests/app.spec.ts`:

```ts
import { expect, test } from '@playwright/test'

test('dashboard is the home route', async ({ page }) => {
  await page.goto('/')
  await expect(page.getByTestId('dashboard-page')).toBeVisible()
  await expect(page.getByTestId('titlebar')).toBeVisible()
})

test('create, rename, and see the document in the sidebar', async ({
  page
}) => {
  await page.goto('/')
  await page.getByTestId('new-doc').click()
  await expect(page).toHaveURL(/#\/doc\//)
  await page.getByTestId('doc-title').fill('My first note')
  await expect(
    page.getByTestId('doc-tree').getByText('My first note')
  ).toBeVisible()
})

test('delete moves the document out of the sidebar', async ({ page }) => {
  await page.goto('/')
  await page.getByTestId('new-doc').click()
  await page.getByTestId('doc-title').fill('Doomed')
  const item = page.getByTestId('doc-tree').getByText('Doomed')
  await expect(item).toBeVisible()
  const docId = new URL(page.url()).hash.replace('#/doc/', '')
  await item.hover()
  await page.getByTestId(`doc-actions-${docId}`).click()
  await page.getByTestId(`doc-delete-${docId}`).click()
  await expect(item).not.toBeVisible()
  await expect(page.getByTestId('dashboard-page')).toBeVisible()
})

test('documents persist across in-page navigation', async ({ page }) => {
  await page.goto('/')
  await page.getByTestId('new-doc').click()
  await page.getByTestId('doc-title').fill('Sticky')
  await page.getByTestId('nav-dashboard').click()
  await page.getByTestId('doc-tree').getByText('Sticky').click()
  await expect(page.getByTestId('doc-title')).toHaveValue('Sticky')
})
```

Delete `e2e-tests/example.spec.ts`. Add `"e2e": "playwright test"` to package.json scripts.

- [ ] **Step 2: Install browsers and run**

Run: `pnpm exec playwright install chromium` (first time only), then `pnpm e2e`
Expected: first run may fail if selectors/flows have drifted — fix the app or test until green. All 4 pass.

- [ ] **Step 3: Manual Tauri smoke test**

Run: `pnpm tauri dev` and verify by hand:

1. App opens; traffic lights don't overlap the titlebar content; dragging the titlebar moves the window.
2. Fullscreen (green button): titlebar left padding collapses.
3. Create a doc, type a title, quit fully (⌘Q), relaunch — the doc is still there (`~/Hikki/documents/<uuid>/document.json` exists on disk).
4. Delete the doc — it leaves the sidebar; its `document.json` now has `deletedAt`.

Fix anything broken before committing.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "test: e2e smoke suite over memory backend

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 12: Documentation sync

**Files:**

- Modify: `README.md` (replace template content), `CLAUDE.md` (currently empty)

**Interfaces:** none — docs only.

- [ ] **Step 1: Write `CLAUDE.md`**

```markdown
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
```

- [ ] **Step 2: Write `README.md`**

````markdown
# Hikki

A Notion-like, local-first note-taking app for macOS.

- **Your files, yours** — documents live as plain JSON + assets in `~/Hikki` (relocatable, iCloud-friendly). A derived SQLite FTS5 index powers instant search and is always rebuildable.
- **Editor** — BlockNote block editor (Phase 2), AI Writing Tools in the style of Apple Intelligence (Phase 3), experimental voice input (Phase 7).
- **Stack** — Tauri 2 (Rust), React 19, shadcn/ui, Jotai, Vite.

## Development

```bash
pnpm install
pnpm tauri dev      # desktop app
pnpm dev            # browser-only mode (in-memory backend)
```
````

## Testing

```bash
pnpm test                                        # Vitest unit tests
cargo test --manifest-path src-tauri/Cargo.toml  # Rust tests
pnpm e2e                                         # Playwright e2e
```

## Project docs

- Design spec: `docs/superpowers/specs/2026-07-18-hikki-design.md`
- Implementation plans: `docs/superpowers/plans/`

````

- [ ] **Step 3: Commit**

```bash
git add README.md CLAUDE.md
git commit -m "docs: sync CLAUDE.md and README with phase 1 architecture

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
````

---

## Self-review notes

- **Spec coverage (phase 1 scope):** vault fs ✅ (T2–T3), index ✅ (T4), IPC ✅ (T5, T7), shell/router/titlebar ✅ (T8), sidebar tree ✅ (T9), autosave ✅ (T10), tests ✅ (T1, T11), docs ✅ (T12). Deliberately deferred within spec: assets/`import_asset` + `asset://` protocol (Phase 2, editor needs it), file-watcher reconcile (later phase), move/restore/purge commands (Phase 6 trash UI), `recent_documents`/`dashboard_stats` (Phase 5), CSP tightening (Phase 2 with asset protocol), zod-style payload validation (Phase 4 error system).
- **Type consistency:** `Doc`/`DocumentMeta` camelCase mirrors serde rename; `deleteDocument` returns `string[]` on both sides; `VaultInfo.documentCount` counts non-deleted docs on both sides; `search` empty-query → `[]` on both backends.
- **Known check-before-use points called out inline:** `DropdownMenuItem` `variant` prop (T9), `#lib` alias resolution under vitest (T1), subpath import for `#lib/backend/*` (T6).
