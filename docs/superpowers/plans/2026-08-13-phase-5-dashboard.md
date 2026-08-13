# Phase 5: Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the `DashboardPage` stub with a real landing page — stat tiles, a 30-day words-written area chart, a month-view activity heatmap, a recently-edited list, and a greeting header with a "New document" action.

**Architecture:** Wires up two pieces of the SQLite schema that already exist but are currently dead: the `activity` table (nothing writes to it today) and `documents.word_count` (computed on every save but never read back). Rust gains a per-save activity-write path plus two new read commands (`dashboard_stats`, `recent_documents`); the frontend gains two new `Backend` methods (implemented in both `TauriBackend` and `MemoryBackend`), two Jotai atoms, and five new presentational components composed by the rewritten `DashboardPage`.

**Tech Stack:** Rust (rusqlite, chrono), React 19, Jotai, recharts (already installed) via the existing shadcn `chart.tsx` wrapper, date-fns (already installed), Vitest, Playwright, cargo test.

## Global Constraints

- TDD: write the failing test before the implementation, for every task.
- `data-testid` on every interactive/asserted element (project convention, `CLAUDE.md`).
- Never touch, stage, or commit the user's own separate, currently-uncommitted `tables` config block inside `src/components/editor.tsx`'s `useCreateBlockNote` options, or any other file not listed in this plan's tasks. Check `git status` before every commit; use `git add -p` if `editor.tsx` needs touching for an unrelated reason (it shouldn't, in this plan).
- Husky runs `oxlint`/`oxfmt` on commit — never `--no-verify`.
- IPC payloads are camelCase; Rust uses `serde(rename_all = "camelCase")` (already the project-wide convention — every new struct below follows it).
- Favorites, historical backfill, live/polling updates, per-document chart breakdowns, and a year-view heatmap are explicitly out of scope (see the spec's §5) — do not build any of them.
- No backfill: the very first `dashboard_stats`/`recent_documents` calls against a pre-existing vault will show the vault's real document/word totals (those come straight from `documents`) but zero activity/streak/chart data, since `activity` starts empty. This is expected, not a bug to fix.
- Every task must leave the project compiling/passing (`pnpm exec tsc --noEmit`, `cargo build`) before its commit — no task should depend on a later task to become whole again.

---

## Verified against the real codebase

Everything below was directly confirmed — either by reading the actual installed dependencies/existing source files, or by temporarily wiring the exact planned code into the real Rust files, running `cargo test`, then reverting. Two things changed from the approved spec (`docs/superpowers/specs/2026-08-13-phase-5-dashboard-design.md`) as a result — both are correctness fixes found during this verification, not scope changes:

- **The spec's `dashboard_stats(local_today: &str)` parameter is replaced with `dashboard_stats(utc_offset_minutes: i64)`.** A single "today" date string isn't enough to correctly bucket _past_ UTC timestamps into local calendar days — you need the offset itself. `utc_offset_minutes` matches JS's `Date.prototype.getTimezoneOffset()` convention exactly (positive = local time behind UTC, e.g. `480` for UTC-8), so `TauriBackend` passes it straight through with zero conversion. All day-bucketing (streak, the rolling week, the 30-day chart, the 35-day heatmap) happens in **Rust, not SQL** — the query fetches a plain, generously-bounded window of `activity` rows (45 days of UTC timestamps, which safely covers a 35-day local window at any real-world offset) and groups them with `chrono` in ordinary Rust code. This was verified live with a prototype `Index::dashboard_stats` and three tests, including the trickiest case — a 23:30-UTC row that's already "tomorrow" for a UTC+2 caller but still "today" for a UTC caller — all of which passed. Task 2 below has the exact, already-verified code.
- **`Index::upsert()` is not touched at all.** The spec described capturing "the previous word_count... before the new value overwrites it" inside `upsert()`, but `upsert()` has 12 call sites today (9 in its own test module, plus `reconcile()`, `delete_document_impl`, and the two real editing paths) — and `reconcile()` (every app startup and every "rebuild index" click) and `delete_document_impl` (soft-delete) must **never** record activity, or the streak/chart would fill with bogus rows from index rebuilds and deletions. Threading an `Option<&str>` "record activity or not" flag through `upsert()` would have meant updating all 12 call sites for a change only 2 of them need. Instead, Task 1 adds two small, independent methods — `Index::word_count_for(id) -> Result<Option<i64>>` and `Index::record_activity(doc_id, kind, word_delta, at) -> Result<()>` — called only from `create_document_impl`/`save_document_impl` in `commands.rs`. `upsert()`'s signature, its own 9 tests, `reconcile()`, and `delete_document_impl` are all completely unaffected. Verified live: `cargo test --lib commands::` and `cargo test --lib index::` both still pass in full, and a new test confirms `word_count_for` returns the right value after create/save/for a missing id.
- `recharts`' `AreaChart`/`Area`/`CartesianGrid`/`XAxis` compose correctly inside the existing `src/components/ui/chart.tsx`'s `ChartContainer` — verified by writing the exact planned JSX (Task 7, below) into a temporary file and running `pnpm exec tsc --noEmit` clean, then deleting the file.
- `date-fns` is already a project dependency (used by `page-header.tsx`'s `formatDistanceToNow`) — available for the greeting's date display and every day-bucketing/formatting need on the frontend side without adding anything to `package.json`.
- `sidebar-left.tsx`'s existing `createDoc` (`backend.createDocument(null, '')` → `refreshDocsAtom` → `navigate`) is the pattern Task 5's greeting button must copy **exactly**, including the `refreshDocsAtom` call — `SidebarLeft` is mounted once, as a sibling to the routed `<Outlet />` in `app-shell.tsx`, not remounted per route, so its own `docMetasAtom` only refreshes on the app's initial mount and after its own handlers explicitly call `refreshDocsAtom`. If the dashboard's own "New document" button skipped that call, the sidebar tree would silently miss the new document until some unrelated action happened to refresh it.
- `document-page.test.tsx`/`memory-backend.test.ts` establish two different, correct patterns this plan reuses: page-level tests seed Jotai atoms directly via `getDefaultStore().set(...)` (matching `page-mention.test.tsx`'s established pattern) rather than mocking the backend module, while `MemoryBackend`'s own tests instantiate a **fresh** `new MemoryBackend()` per test (never the shared `backend` singleton) specifically because dashboard stats are aggregate/global state that would otherwise leak across tests in the same file (Vitest isolates modules per test _file_, not per individual `test()` within one).
- Task 4 (frontend data layer) originally split into two tasks — `Backend` interface + `TauriBackend` in one, `MemoryBackend` in a second — but that left `tsc --noEmit` genuinely failing after the first task's own commit (`MemoryBackend` wouldn't yet satisfy the `Backend` interface it implements). Merged into one task instead: a reviewer couldn't sensibly approve "add the interface method" while rejecting "implement it in the in-memory backend," since the first alone breaks the build.

---

### Task 1: Rust — record activity on create/save

**Files:**

- Modify: `src-tauri/src/index.rs`
- Modify: `src-tauri/src/commands.rs`

**Interfaces:**

- Produces: `Index::word_count_for(&self, id: &str) -> Result<Option<i64>>`
- Produces: `Index::record_activity(&self, doc_id: &str, kind: &str, word_delta: i64, at: &str) -> Result<()>`
- Consumes: `crate::index::extract_text(blocks: &serde_json::Value) -> String` (already exists, already `pub`)

- [ ] **Step 1: Write the failing test**

Add to `src-tauri/src/commands.rs`'s `#[cfg(test)] mod tests`, right before `fn save_reindexes()`:

```rust
    #[test]
    fn create_then_edit_records_word_count_snapshots() {
        let (_v, _d, state) = state();
        let doc = create_document_impl(&state, None, "Note".into()).unwrap();
        let mut grown = doc.clone();
        grown.blocks = serde_json::json!([
            { "id": "b1", "type": "paragraph", "content": [{ "type": "text", "text": "one two three", "styles": {} }], "children": [] }
        ]);
        let saved = save_document_impl(&state, grown).unwrap();

        let index = lock(&state.index);
        assert_eq!(index.word_count_for(&saved.id).unwrap(), Some(3));
        assert_eq!(index.word_count_for("does-not-exist").unwrap(), None);
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd src-tauri && cargo test --lib commands::tests::create_then_edit_records_word_count_snapshots`
Expected: FAIL with `no method named 'word_count_for' found for struct 'Index'`.

- [ ] **Step 3: Implement `word_count_for` and `record_activity`**

In `src-tauri/src/index.rs`, add these two methods to `impl Index`, right before `pub fn list_metas`:

```rust
    pub fn word_count_for(&self, id: &str) -> Result<Option<i64>> {
        use rusqlite::OptionalExtension;
        Ok(self
            .conn
            .query_row("SELECT word_count FROM documents WHERE id = ?1", [id], |r| r.get(0))
            .optional()?)
    }

    pub fn record_activity(&self, doc_id: &str, kind: &str, word_delta: i64, at: &str) -> Result<()> {
        self.conn.execute(
            "INSERT INTO activity (doc_id, kind, word_delta, at) VALUES (?1, ?2, ?3, ?4)",
            rusqlite::params![doc_id, kind, word_delta, at],
        )?;
        Ok(())
    }
```

- [ ] **Step 4: Wire both into `create_document_impl`/`save_document_impl`**

In `src-tauri/src/commands.rs`, replace:

```rust
pub fn create_document_impl(state: &AppState, parent_id: Option<String>, title: String) -> Result<Document> {
    let vault_path = lock(&state.settings).vault_path.clone();
    let doc = document::create_document(&vault_path, parent_id, &title)?;
    lock(&state.index).upsert(&doc)?;
    Ok(doc)
}
```

with:

```rust
pub fn create_document_impl(state: &AppState, parent_id: Option<String>, title: String) -> Result<Document> {
    let vault_path = lock(&state.settings).vault_path.clone();
    let doc = document::create_document(&vault_path, parent_id, &title)?;
    let index = lock(&state.index);
    index.upsert(&doc)?;
    let word_count = crate::index::extract_text(&doc.blocks).split_whitespace().count() as i64;
    index.record_activity(&doc.id, "create", word_count, &doc.updated_at)?;
    Ok(doc)
}
```

and replace:

```rust
pub fn save_document_impl(state: &AppState, doc: Document) -> Result<Document> {
    let vault_path = lock(&state.settings).vault_path.clone();
    let saved = document::save_document(&vault_path, doc)?;
    lock(&state.index).upsert(&saved)?;
    Ok(saved)
}
```

with:

```rust
pub fn save_document_impl(state: &AppState, doc: Document) -> Result<Document> {
    let vault_path = lock(&state.settings).vault_path.clone();
    let index = lock(&state.index);
    let previous_word_count = index.word_count_for(&doc.id)?.unwrap_or(0);
    let saved = document::save_document(&vault_path, doc)?;
    index.upsert(&saved)?;
    let new_word_count = crate::index::extract_text(&saved.blocks).split_whitespace().count() as i64;
    index.record_activity(&saved.id, "edit", new_word_count - previous_word_count, &saved.updated_at)?;
    Ok(saved)
}
```

`delete_document_impl` and `Index::reconcile` are **not modified** — they must not record activity (see the "Verified" section above).

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd src-tauri && cargo test --lib commands::tests::create_then_edit_records_word_count_snapshots`
Expected: PASS.

- [ ] **Step 6: Run the full existing suite to confirm no regressions**

Run: `cd src-tauri && cargo test --lib`
Expected: every existing test (`index::tests::*`, `commands::tests::*`, and all other modules) still passes — this change touches `upsert()`'s callers, not `upsert()` itself, so nothing else should move.

- [ ] **Step 7: Commit**

```bash
git add src-tauri/src/index.rs src-tauri/src/commands.rs
git commit -m "feat: record activity rows on document create/save"
```

---

### Task 2: Rust — `dashboard_stats` and `recent_documents` commands

**Files:**

- Modify: `src-tauri/src/index.rs`
- Modify: `src-tauri/src/commands.rs`
- Modify: `src-tauri/src/lib.rs`

**Interfaces:**

- Consumes: `Index::record_activity` (Task 1), `crate::document::DocumentMeta` (existing)
- Produces: `Index::dashboard_stats(&self, utc_offset_minutes: i64) -> Result<DashboardStats>`, `Index::recently_edited(&self, limit: i64) -> Result<Vec<DocumentMeta>>`, public structs `DashboardStats`/`DailyWordCount`/`DailyActivity`, Tauri commands `dashboard_stats`/`recent_documents`

- [ ] **Step 1: Write the failing tests**

Add to `src-tauri/src/index.rs`'s `#[cfg(test)] mod tests` module, right before `fn list_metas_includes_soft_deleted()`:

```rust
    #[test]
    fn dashboard_stats_totals_reflect_alive_documents_only() {
        let idx = Index::open_in_memory().unwrap();
        idx.upsert(&doc_with("Alive", sample_blocks())).unwrap();
        let mut trashed = doc_with("Trashed", sample_blocks());
        trashed.deleted_at = Some("2026-01-02T00:00:00Z".into());
        idx.upsert(&trashed).unwrap();

        let stats = idx.dashboard_stats(0).unwrap();
        assert_eq!(stats.total_documents, 1);
        assert_eq!(stats.total_words, 6); // "the quick brown fox" + "jumps over"
    }

    #[test]
    fn dashboard_stats_buckets_by_local_day_not_utc_day() {
        let idx = Index::open_in_memory().unwrap();
        idx.record_activity("d1", "edit", 10, &Utc::now().to_rfc3339()).unwrap();
        // 23:30 UTC "today" is already tomorrow for a UTC+2 caller, but
        // still today for a UTC caller.
        let almost_midnight_utc = Utc::now().date_naive().and_hms_opt(23, 30, 0).unwrap().and_utc();
        idx.record_activity("d2", "edit", 5, &almost_midnight_utc.to_rfc3339()).unwrap();

        let utc_plus_2 = idx.dashboard_stats(-120).unwrap();
        assert_eq!(utc_plus_2.daily_words.last().unwrap().word_delta, 10);

        let utc = idx.dashboard_stats(0).unwrap();
        assert_eq!(utc.daily_words.last().unwrap().word_delta, 15);
    }

    #[test]
    fn dashboard_stats_streak_counts_backward_from_yesterday_when_today_is_empty() {
        let idx = Index::open_in_memory().unwrap();
        idx.record_activity("d1", "edit", 1, &(Utc::now() - Duration::days(1)).to_rfc3339()).unwrap();
        idx.record_activity("d1", "edit", 1, &(Utc::now() - Duration::days(2)).to_rfc3339()).unwrap();
        assert_eq!(idx.dashboard_stats(0).unwrap().streak_days, 2);
    }

    #[test]
    fn dashboard_stats_streak_breaks_on_a_full_gap_day() {
        let idx = Index::open_in_memory().unwrap();
        idx.record_activity("d1", "edit", 1, &(Utc::now() - Duration::days(3)).to_rfc3339()).unwrap();
        assert_eq!(idx.dashboard_stats(0).unwrap().streak_days, 0);
    }

    #[test]
    fn dashboard_stats_counts_distinct_docs_edited_this_week() {
        let idx = Index::open_in_memory().unwrap();
        let today = Utc::now().to_rfc3339();
        idx.record_activity("d1", "edit", 5, &today).unwrap();
        idx.record_activity("d1", "edit", 3, &today).unwrap(); // same doc, same day
        idx.record_activity("d2", "edit", 2, &(Utc::now() - Duration::days(8)).to_rfc3339()).unwrap(); // outside the window
        assert_eq!(idx.dashboard_stats(0).unwrap().docs_edited_this_week, 1);
    }

    #[test]
    fn recently_edited_orders_by_updated_at_desc_excludes_deleted_and_respects_limit() {
        let idx = Index::open_in_memory().unwrap();
        let mut a = doc_with("A", sample_blocks());
        a.updated_at = "2026-01-01T00:00:00Z".into();
        let mut b = doc_with("B", sample_blocks());
        b.updated_at = "2026-01-03T00:00:00Z".into();
        let mut c = doc_with("C", sample_blocks());
        c.updated_at = "2026-01-02T00:00:00Z".into();
        c.deleted_at = Some("2026-01-04T00:00:00Z".into());
        idx.upsert(&a).unwrap();
        idx.upsert(&b).unwrap();
        idx.upsert(&c).unwrap();

        let recent = idx.recently_edited(1).unwrap();
        assert_eq!(recent.len(), 1);
        assert_eq!(recent[0].title, "B");
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd src-tauri && cargo test --lib index::tests::dashboard_stats`
Expected: FAIL to compile (`no method named 'dashboard_stats' found`, `cannot find type 'DashboardStats'`, and `chrono`/`Duration`/`Utc` not imported in the test module yet).

- [ ] **Step 3: Implement**

In `src-tauri/src/index.rs`, change the top imports from:

```rust
use std::path::Path;

use rusqlite::Connection;
use serde::Serialize;

use crate::document::{self, Document};
use crate::error::Result;
```

to:

```rust
use std::collections::{BTreeMap, HashSet};
use std::path::Path;

use chrono::{DateTime, Duration, NaiveDate, Utc};
use rusqlite::Connection;
use serde::Serialize;

use crate::document::{self, Document};
use crate::error::Result;
```

Add these three structs right after the existing `SearchHit` struct definition:

```rust
#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct DailyWordCount {
    pub date: String,
    pub word_delta: i64,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct DailyActivity {
    pub date: String,
    pub activity_count: i64,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct DashboardStats {
    pub total_documents: i64,
    pub total_words: i64,
    pub streak_days: i64,
    pub docs_edited_this_week: i64,
    pub daily_words: Vec<DailyWordCount>,
    pub daily_activity: Vec<DailyActivity>,
}
```

Add these two methods to `impl Index`, right after `record_activity` (Task 1):

```rust
    /// `utc_offset_minutes` is the caller's local UTC offset (JS's
    /// `Date.prototype.getTimezoneOffset()` convention: positive means local
    /// time is *behind* UTC, e.g. 480 for UTC-8). All day-bucketing (streak,
    /// the rolling week, the 30/35-day series) shifts each row's UTC `at` by
    /// this offset before taking its calendar date, rather than relying on
    /// SQLite's own UTC-based `date()` function - done here in Rust (not
    /// SQL) so the bucketing logic is plain, unit-testable code.
    pub fn dashboard_stats(&self, utc_offset_minutes: i64) -> Result<DashboardStats> {
        let total_documents: i64 = self.conn.query_row(
            "SELECT COUNT(*) FROM documents WHERE deleted_at IS NULL",
            [],
            |r| r.get(0),
        )?;
        let total_words: i64 = self.conn.query_row(
            "SELECT COALESCE(SUM(word_count), 0) FROM documents WHERE deleted_at IS NULL",
            [],
            |r| r.get(0),
        )?;

        let offset = Duration::minutes(utc_offset_minutes);
        let today = (Utc::now() - offset).date_naive();
        // 45 days of UTC-timestamped rows safely covers the 35-day local
        // window at any real-world offset (max ±14h).
        let cutoff = (Utc::now() - Duration::days(45)).to_rfc3339();

        let mut stmt = self
            .conn
            .prepare("SELECT doc_id, word_delta, at FROM activity WHERE at >= ?1 ORDER BY at")?;
        let rows: Vec<(String, i64, String)> = stmt
            .query_map([&cutoff], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)))?
            .collect::<std::result::Result<Vec<_>, _>>()?;

        let local_day = |at: &str| -> Option<NaiveDate> {
            DateTime::parse_from_rfc3339(at)
                .ok()
                .map(|dt| (dt.with_timezone(&Utc) - offset).date_naive())
        };

        let mut words_by_day: BTreeMap<NaiveDate, i64> = BTreeMap::new();
        let mut activity_by_day: BTreeMap<NaiveDate, i64> = BTreeMap::new();
        let mut docs_this_week: HashSet<String> = HashSet::new();
        for (doc_id, delta, at) in &rows {
            let Some(day) = local_day(at) else { continue };
            *words_by_day.entry(day).or_insert(0) += delta;
            *activity_by_day.entry(day).or_insert(0) += 1;
            if day <= today && (today - day) < Duration::days(7) {
                docs_this_week.insert(doc_id.clone());
            }
        }

        let daily_words = (0..30)
            .rev()
            .map(|i| {
                let day = today - Duration::days(i);
                DailyWordCount {
                    date: day.to_string(),
                    word_delta: *words_by_day.get(&day).unwrap_or(&0),
                }
            })
            .collect();

        let daily_activity = (0..35)
            .rev()
            .map(|i| {
                let day = today - Duration::days(i);
                DailyActivity {
                    date: day.to_string(),
                    activity_count: *activity_by_day.get(&day).unwrap_or(&0),
                }
            })
            .collect();

        let mut streak_days = 0i64;
        let mut cursor = today;
        if !activity_by_day.contains_key(&cursor) {
            cursor -= Duration::days(1);
        }
        while activity_by_day.get(&cursor).copied().unwrap_or(0) > 0 {
            streak_days += 1;
            cursor -= Duration::days(1);
        }

        Ok(DashboardStats {
            total_documents,
            total_words,
            streak_days,
            docs_edited_this_week: docs_this_week.len() as i64,
            daily_words,
            daily_activity,
        })
    }

    pub fn recently_edited(&self, limit: i64) -> Result<Vec<crate::document::DocumentMeta>> {
        let mut stmt = self.conn.prepare(
            "SELECT id, parent_id, title, icon, created_at, updated_at, deleted_at
             FROM documents WHERE deleted_at IS NULL ORDER BY updated_at DESC LIMIT ?1",
        )?;
        let metas = stmt
            .query_map([limit], |row| {
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

In `src-tauri/src/commands.rs`, add these four functions right after `rebuild_index`/`#[tauri::command] pub fn rebuild_index`:

```rust
pub fn dashboard_stats_impl(state: &AppState, utc_offset_minutes: i64) -> Result<crate::index::DashboardStats> {
    lock(&state.index).dashboard_stats(utc_offset_minutes)
}

#[tauri::command]
pub fn dashboard_stats(state: State<AppState>, utc_offset_minutes: i64) -> Result<crate::index::DashboardStats> {
    dashboard_stats_impl(&state, utc_offset_minutes)
}

pub fn recent_documents_impl(state: &AppState, limit: i64) -> Result<Vec<DocumentMeta>> {
    lock(&state.index).recently_edited(limit)
}

#[tauri::command]
pub fn recent_documents(state: State<AppState>, limit: i64) -> Result<Vec<DocumentMeta>> {
    recent_documents_impl(&state, limit)
}
```

In `src-tauri/src/lib.rs`, add both new commands to the `generate_handler!` list, right after `commands::rebuild_index,`:

```rust
            commands::rebuild_index,
            commands::dashboard_stats,
            commands::recent_documents,
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd src-tauri && cargo test --lib index::tests::dashboard_stats && cargo test --lib index::tests::recently_edited`
Expected: PASS.

- [ ] **Step 5: Run the full existing suite and build**

Run: `cd src-tauri && cargo test --lib && cargo build`
Expected: every test passes; the build succeeds (confirms `lib.rs`'s registration compiles and every command's argument names match what `tauri::generate_handler!` expects).

- [ ] **Step 6: Commit**

```bash
git add src-tauri/src/index.rs src-tauri/src/commands.rs src-tauri/src/lib.rs
git commit -m "feat: add dashboard_stats and recent_documents commands"
```

---

### Task 3: Frontend — word-count helper

**Files:**

- Create: `src/lib/word-count.ts`
- Test: `src/lib/word-count.test.ts`

**Interfaces:**

- Produces: `countWords(blocks: unknown): number`

- [ ] **Step 1: Write the failing tests**

Create `src/lib/word-count.test.ts`:

```ts
import { countWords } from '#lib/word-count'

test('counts words across nested content and children', () => {
  const blocks = [
    {
      type: 'paragraph',
      content: [{ type: 'text', text: 'the quick brown fox' }],
      children: [
        {
          type: 'paragraph',
          content: [{ type: 'text', text: 'jumps over' }],
          children: []
        }
      ]
    }
  ]
  expect(countWords(blocks)).toBe(6)
})

test('returns 0 for an empty document', () => {
  expect(countWords([])).toBe(0)
})

test('walks table rows and cells', () => {
  const blocks = [
    {
      type: 'table',
      content: {
        rows: [
          {
            cells: [
              [{ type: 'text', text: 'a b' }],
              [{ type: 'text', text: 'c' }]
            ]
          }
        ]
      }
    }
  ]
  expect(countWords(blocks)).toBe(3)
})

test("collapses runs of whitespace the same way Rust's split_whitespace does", () => {
  const blocks = [
    {
      type: 'paragraph',
      content: [{ type: 'text', text: '  leading and   extra   spaces  ' }]
    }
  ]
  expect(countWords(blocks)).toBe(4)
})
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `pnpm test word-count`
Expected: FAIL — `Cannot find module '#lib/word-count'`.

- [ ] **Step 3: Write the implementation**

Create `src/lib/word-count.ts`:

```ts
// Mirrors `src-tauri/src/index.rs`'s `extract_text`/`collect_text` walk
// exactly (same four child keys, same depth-first order) so the frontend's
// own word count - used by `MemoryBackend`'s dashboard-stats simulation -
// matches the real Rust computation the Tauri backend uses.
function collectText(value: unknown, out: string[]): void {
  if (Array.isArray(value)) {
    for (const item of value) collectText(item, out)
    return
  }
  if (value && typeof value === 'object') {
    const obj = value as Record<string, unknown>
    if (typeof obj.text === 'string') out.push(obj.text)
    for (const key of ['content', 'children', 'rows', 'cells']) {
      if (key in obj) collectText(obj[key], out)
    }
  }
}

export function countWords(blocks: unknown): number {
  const out: string[] = []
  collectText(blocks, out)
  return out.join(' ').split(/\s+/).filter(Boolean).length
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `pnpm test word-count`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/lib/word-count.ts src/lib/word-count.test.ts
git commit -m "feat: add countWords helper mirroring the Rust word-count logic"
```

---

### Task 4: Frontend data layer — types, `Backend` interface, `TauriBackend`, `MemoryBackend`, Jotai atoms

**Files:**

- Modify: `src/lib/types.ts`
- Modify: `src/lib/backend/backend.ts`
- Modify: `src/lib/backend/tauri-backend.ts`
- Modify: `src/lib/backend/tauri-backend.test.ts`
- Modify: `src/lib/backend/memory-backend.ts`
- Modify: `src/lib/backend/memory-backend.test.ts`
- Modify: `src/lib/store.ts`

**Interfaces:**

- Consumes: `countWords` (Task 3)
- Produces types: `DailyWordCount { date: string; wordDelta: number }`, `DailyActivity { date: string; activityCount: number }`, `DashboardStats { totalDocuments: number; totalWords: number; streakDays: number; docsEditedThisWeek: number; dailyWords: DailyWordCount[]; dailyActivity: DailyActivity[] }`
- Produces: `Backend.getDashboardStats(): Promise<DashboardStats>`, `Backend.getRecentDocuments(limit: number): Promise<DocumentMeta[]>` — implemented in both `TauriBackend` and `MemoryBackend`
- Produces atoms: `dashboardStatsAtom: Atom<DashboardStats | null>`, `recentDocsAtom: Atom<DocumentMeta[]>`, `refreshDashboardAtom` (write-only)

- [ ] **Step 1: Write the failing `TauriBackend` tests**

Add to `src/lib/backend/tauri-backend.test.ts`, at the end of the file:

```ts
test('getDashboardStats invokes dashboard_stats with the local UTC offset', async () => {
  const calls: Array<[string, unknown]> = []
  mockIPC((cmd, args) => {
    calls.push([cmd, args])
    return {
      totalDocuments: 0,
      totalWords: 0,
      streakDays: 0,
      docsEditedThisWeek: 0,
      dailyWords: [],
      dailyActivity: []
    }
  })
  await new TauriBackend().getDashboardStats()
  expect(calls).toEqual([
    ['dashboard_stats', { utcOffsetMinutes: new Date().getTimezoneOffset() }]
  ])
})

test('getRecentDocuments invokes recent_documents with the limit', async () => {
  const calls: Array<[string, unknown]> = []
  mockIPC((cmd, args) => {
    calls.push([cmd, args])
    return []
  })
  await new TauriBackend().getRecentDocuments(8)
  expect(calls).toEqual([['recent_documents', { limit: 8 }]])
})
```

- [ ] **Step 2: Write the failing `MemoryBackend` tests**

Add to `src/lib/backend/memory-backend.test.ts`, at the end of the file:

```ts
describe('dashboard stats', () => {
  beforeEach(() => vi.useFakeTimers())
  afterEach(() => vi.useRealTimers())

  test('totals reflect alive documents only', async () => {
    const b = new MemoryBackend()
    const alive = await b.createDocument(null, 'Alive')
    await b.saveDocument({
      ...alive,
      blocks: [
        {
          type: 'paragraph',
          content: [{ type: 'text', text: 'one two three' }]
        }
      ]
    })
    const trashed = await b.createDocument(null, 'Trashed')
    await b.deleteDocument(trashed.id)

    const stats = await b.getDashboardStats()
    expect(stats.totalDocuments).toBe(1)
    expect(stats.totalWords).toBe(3)
  })

  test('streak counts backward from yesterday when today has no activity yet', async () => {
    const b = new MemoryBackend()
    vi.setSystemTime(new Date('2026-01-10T12:00:00Z'))
    const doc = await b.createDocument(null, 'D')
    vi.setSystemTime(new Date('2026-01-11T12:00:00Z'))
    await b.saveDocument({
      ...doc,
      blocks: [{ type: 'paragraph', content: [{ type: 'text', text: 'x' }] }]
    })
    vi.setSystemTime(new Date('2026-01-12T09:00:00Z')) // "today" - no activity yet

    const stats = await b.getDashboardStats()
    expect(stats.streakDays).toBe(2)
  })

  test('streak breaks on a full gap day', async () => {
    const b = new MemoryBackend()
    vi.setSystemTime(new Date('2026-01-01T12:00:00Z'))
    await b.createDocument(null, 'D')
    vi.setSystemTime(new Date('2026-01-04T12:00:00Z')) // 3 days later, a full gap

    const stats = await b.getDashboardStats()
    expect(stats.streakDays).toBe(0)
  })

  test('docsEditedThisWeek counts distinct documents, not distinct saves', async () => {
    const b = new MemoryBackend()
    const doc = await b.createDocument(null, 'D')
    await b.saveDocument({
      ...doc,
      blocks: [{ type: 'paragraph', content: [{ type: 'text', text: 'a' }] }]
    })
    await b.saveDocument({
      ...doc,
      blocks: [{ type: 'paragraph', content: [{ type: 'text', text: 'a b' }] }]
    })

    const stats = await b.getDashboardStats()
    expect(stats.docsEditedThisWeek).toBe(1)
  })

  test('dailyWords has exactly 30 entries and dailyActivity has exactly 35', async () => {
    const b = new MemoryBackend()
    const stats = await b.getDashboardStats()
    expect(stats.dailyWords).toHaveLength(30)
    expect(stats.dailyActivity).toHaveLength(35)
  })
})

describe('getRecentDocuments', () => {
  test('orders by updatedAt desc, excludes deleted, respects the limit', async () => {
    const b = new MemoryBackend()
    const a = await b.createDocument(null, 'A')
    const bDoc = await b.createDocument(null, 'B')
    const c = await b.createDocument(null, 'C')
    await b.saveDocument({ ...a, title: 'A' }) // bumps A's updatedAt to be latest
    await b.deleteDocument(c.id)

    const recent = await b.getRecentDocuments(1)
    expect(recent).toHaveLength(1)
    expect(recent[0].id).toBe(a.id)
    void bDoc
  })
})
```

- [ ] **Step 3: Run both test files to verify they fail**

Run: `pnpm test tauri-backend memory-backend`
Expected: FAIL — neither `TauriBackend` nor `MemoryBackend` implements `getDashboardStats`/`getRecentDocuments` yet.

- [ ] **Step 4: Add the types**

In `src/lib/types.ts`, add at the end of the file:

```ts
export interface DailyWordCount {
  date: string
  wordDelta: number
}

export interface DailyActivity {
  date: string
  activityCount: number
}

export interface DashboardStats {
  totalDocuments: number
  totalWords: number
  streakDays: number
  docsEditedThisWeek: number
  dailyWords: DailyWordCount[]
  dailyActivity: DailyActivity[]
}
```

- [ ] **Step 5: Add the `Backend` interface methods**

In `src/lib/backend/backend.ts`, add `DashboardStats` to the type-only import list (making it `import type { AiSettings, DashboardStats, Doc, DocumentMeta, LogEntry, LogFilter, SearchHit, VaultInfo } from '#lib/types'`), and add these two lines to the `Backend` interface, right after `rebuildIndex(): Promise<number>`:

```ts
  getDashboardStats(): Promise<DashboardStats>
  getRecentDocuments(limit: number): Promise<DocumentMeta[]>
```

- [ ] **Step 6: Implement in `TauriBackend`**

In `src/lib/backend/tauri-backend.ts`, add `DashboardStats` to the type-only import from `#lib/types`, and add these two methods right after `rebuildIndex()`:

```ts
  getDashboardStats() {
    return invoke<DashboardStats>('dashboard_stats', {
      utcOffsetMinutes: new Date().getTimezoneOffset()
    })
  }
  getRecentDocuments(limit: number) {
    return invoke<DocumentMeta[]>('recent_documents', { limit })
  }
```

- [ ] **Step 7: Implement in `MemoryBackend`**

In `src/lib/backend/memory-backend.ts`, add these imports at the top:

```ts
import { differenceInCalendarDays, format, subDays } from 'date-fns'

import { countWords } from '#lib/word-count'
```

and add `DashboardStats` to the existing type-only import from `#lib/types`.

Add this interface right after the existing `toMeta` helper:

```ts
interface ActivityEntry {
  docId: string
  wordDelta: number
  at: string
}
```

In the `MemoryBackend` class body, add two new private fields alongside the existing ones (`private docs = new Map<string, Doc>()`, etc.):

```ts
  private activity: ActivityEntry[] = []
  private wordCounts = new Map<string, number>()
```

In `createDocument`, right before `return structuredClone(doc)`, add:

```ts
const wordCount = countWords(doc.blocks)
this.wordCounts.set(doc.id, wordCount)
this.activity.push({ docId: doc.id, wordDelta: wordCount, at: doc.updatedAt })
```

In `saveDocument`, right before `this.docs.set(saved.id, saved)`, add:

```ts
const previousWordCount = this.wordCounts.get(doc.id) ?? 0
const newWordCount = countWords(saved.blocks)
this.wordCounts.set(saved.id, newWordCount)
this.activity.push({
  docId: saved.id,
  wordDelta: newWordCount - previousWordCount,
  at: saved.updatedAt
})
```

Add these two methods to the class, right after `rebuildIndex`:

```ts
  async getDashboardStats(): Promise<DashboardStats> {
    const alive = [...this.docs.values()].filter((d) => d.deletedAt === null)
    const totalWords = alive.reduce(
      (sum, d) => sum + (this.wordCounts.get(d.id) ?? 0),
      0
    )

    const today = new Date()
    const dayKey = (date: Date) => format(date, 'yyyy-MM-dd')
    const todayKey = dayKey(today)

    const wordsByDay = new Map<string, number>()
    const activityByDay = new Map<string, number>()
    const docsThisWeek = new Set<string>()

    for (const entry of this.activity) {
      const entryDate = new Date(entry.at)
      const key = dayKey(entryDate)
      wordsByDay.set(key, (wordsByDay.get(key) ?? 0) + entry.wordDelta)
      activityByDay.set(key, (activityByDay.get(key) ?? 0) + 1)
      const daysAgo = differenceInCalendarDays(today, entryDate)
      if (daysAgo >= 0 && daysAgo < 7) docsThisWeek.add(entry.docId)
    }

    const dailyWords = Array.from({ length: 30 }, (_, i) => {
      const key = dayKey(subDays(today, 29 - i))
      return { date: key, wordDelta: wordsByDay.get(key) ?? 0 }
    })

    const dailyActivity = Array.from({ length: 35 }, (_, i) => {
      const key = dayKey(subDays(today, 34 - i))
      return { date: key, activityCount: activityByDay.get(key) ?? 0 }
    })

    let streakDays = 0
    let cursor = activityByDay.has(todayKey) ? today : subDays(today, 1)
    while (activityByDay.has(dayKey(cursor))) {
      streakDays++
      cursor = subDays(cursor, 1)
    }

    return {
      totalDocuments: alive.length,
      totalWords,
      streakDays,
      docsEditedThisWeek: docsThisWeek.size,
      dailyWords,
      dailyActivity
    }
  }

  async getRecentDocuments(limit: number): Promise<DocumentMeta[]> {
    return [...this.docs.values()]
      .filter((d) => d.deletedAt === null)
      .map(toMeta)
      .sort((a, b) => b.updatedAt.localeCompare(a.updatedAt))
      .slice(0, limit)
  }
```

- [ ] **Step 8: Add the Jotai atoms**

In `src/lib/store.ts`, add `DashboardStats` to the type-only import (`import type { DashboardStats, DocumentMeta } from '#lib/types'`), and add at the end of the file:

```ts
export const dashboardStatsAtom = atom<DashboardStats | null>(null)
export const recentDocsAtom = atom<DocumentMeta[]>([])

export const refreshDashboardAtom = atom(null, async (_get, set) => {
  const [stats, recent] = await Promise.all([
    backend.getDashboardStats(),
    backend.getRecentDocuments(8)
  ])
  set(dashboardStatsAtom, stats)
  set(recentDocsAtom, recent)
})
```

- [ ] **Step 9: Run both test files to verify they pass, then `tsc` for the whole project**

Run: `pnpm test tauri-backend memory-backend`
Expected: PASS.

Run: `pnpm exec tsc --noEmit`
Expected: clean — both `TauriBackend` and `MemoryBackend` now fully satisfy `Backend`.

- [ ] **Step 10: Commit**

```bash
git add src/lib/types.ts src/lib/backend/backend.ts src/lib/backend/tauri-backend.ts src/lib/backend/tauri-backend.test.ts src/lib/backend/memory-backend.ts src/lib/backend/memory-backend.test.ts src/lib/store.ts
git commit -m "feat: add dashboard stats/recent-documents to the Backend layer and atoms"
```

---

### Task 5: `dashboard-greeting.tsx`

**Files:**

- Create: `src/components/dashboard-greeting.tsx`
- Test: `src/components/dashboard-greeting.test.tsx`

**Interfaces:**

- Produces: `timeOfDayGreeting(hour: number): string`, `DashboardGreeting` (component, no props)
- Consumes: `backend.createDocument` (existing), `refreshDocsAtom` (existing, `#lib/store` — **not** a new atom, reused so the persistent sidebar tree updates too)

- [ ] **Step 1: Write the failing tests**

Create `src/components/dashboard-greeting.test.tsx`:

```tsx
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router'

import {
  DashboardGreeting,
  timeOfDayGreeting
} from '#components/dashboard-greeting'
import { backend } from '#lib/backend/index'

test.each([
  [0, 'Good morning'],
  [11, 'Good morning'],
  [12, 'Good afternoon'],
  [17, 'Good afternoon'],
  [18, 'Good evening'],
  [23, 'Good evening']
])('timeOfDayGreeting(%i) is %s', (hour, expected) => {
  expect(timeOfDayGreeting(hour)).toBe(expected)
})

test('renders a New document button that creates a document', async () => {
  render(
    <MemoryRouter>
      <DashboardGreeting />
    </MemoryRouter>
  )
  const before = await backend.listDocuments()
  await userEvent.click(screen.getByTestId('dashboard-new-doc'))
  const after = await backend.listDocuments()
  expect(after.length).toBe(before.length + 1)
})
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `pnpm test dashboard-greeting`
Expected: FAIL — `Cannot find module '#components/dashboard-greeting'`.

- [ ] **Step 3: Write the implementation**

Create `src/components/dashboard-greeting.tsx`:

```tsx
import { format } from 'date-fns'
import { useSetAtom } from 'jotai'
import { useNavigate } from 'react-router'

import { Button } from '#components/ui/button'
import { backend } from '#lib/backend/index'
import { refreshDocsAtom } from '#lib/store'

export function timeOfDayGreeting(hour: number): string {
  if (hour < 12) return 'Good morning'
  if (hour < 18) return 'Good afternoon'
  return 'Good evening'
}

export function DashboardGreeting() {
  const navigate = useNavigate()
  // Reuses the sidebar's own atom - SidebarLeft is mounted once, as a
  // sibling to the routed page, not remounted per navigation, so it only
  // ever sees a document created here if this same refresh is called.
  const refreshDocs = useSetAtom(refreshDocsAtom)
  const now = new Date()

  const createDoc = async () => {
    const doc = await backend.createDocument(null, '')
    await refreshDocs()
    navigate(`/doc/${doc.id}`)
  }

  return (
    <div className="flex items-center justify-between">
      <div>
        <h1
          data-testid="dashboard-greeting"
          className="text-2xl font-semibold tracking-tight"
        >
          {timeOfDayGreeting(now.getHours())}
        </h1>
        <p className="text-muted-foreground mt-1 text-sm">
          {format(now, 'EEEE, MMMM d')}
        </p>
      </div>
      <Button onClick={createDoc} data-testid="dashboard-new-doc">
        New document
      </Button>
    </div>
  )
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `pnpm test dashboard-greeting`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/components/dashboard-greeting.tsx src/components/dashboard-greeting.test.tsx
git commit -m "feat: add dashboard greeting header with New document action"
```

---

### Task 6: `dashboard-stat-tiles.tsx`

**Files:**

- Create: `src/components/dashboard-stat-tiles.tsx`
- Test: `src/components/dashboard-stat-tiles.test.tsx`

**Interfaces:**

- Consumes: `DashboardStats` (Task 4), `Card`/`CardHeader`/`CardTitle`/`CardContent` (existing, `#components/ui/card`)
- Produces: `DashboardStatTiles({ stats: DashboardStats })`

- [ ] **Step 1: Write the failing test**

Create `src/components/dashboard-stat-tiles.test.tsx`:

```tsx
import { render, screen } from '@testing-library/react'

import { DashboardStatTiles } from '#components/dashboard-stat-tiles'
import type { DashboardStats } from '#lib/types'

const stats: DashboardStats = {
  totalDocuments: 12,
  totalWords: 3456,
  streakDays: 5,
  docsEditedThisWeek: 3,
  dailyWords: [],
  dailyActivity: []
}

test('renders all four tiles with their values', () => {
  render(<DashboardStatTiles stats={stats} />)
  expect(screen.getByTestId('stat-tile-total-documents')).toHaveTextContent(
    '12'
  )
  expect(screen.getByTestId('stat-tile-total-words')).toHaveTextContent('3,456')
  expect(screen.getByTestId('stat-tile-streak-days')).toHaveTextContent('5')
  expect(
    screen.getByTestId('stat-tile-docs-edited-this-week')
  ).toHaveTextContent('3')
})
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `pnpm test dashboard-stat-tiles`
Expected: FAIL — module not found.

- [ ] **Step 3: Write the implementation**

Create `src/components/dashboard-stat-tiles.tsx`:

```tsx
import { Card, CardContent, CardHeader, CardTitle } from '#components/ui/card'
import type { DashboardStats } from '#lib/types'

export function DashboardStatTiles({ stats }: { stats: DashboardStats }) {
  const tiles = [
    {
      key: 'total-documents',
      label: 'Documents',
      value: stats.totalDocuments
    },
    { key: 'total-words', label: 'Words written', value: stats.totalWords },
    { key: 'streak-days', label: 'Day streak', value: stats.streakDays },
    {
      key: 'docs-edited-this-week',
      label: 'Edited this week',
      value: stats.docsEditedThisWeek
    }
  ]

  return (
    <div
      data-testid="dashboard-stat-tiles"
      className="grid grid-cols-2 gap-4 @lg:grid-cols-4"
    >
      {tiles.map((tile) => (
        <Card key={tile.key} data-testid={`stat-tile-${tile.key}`}>
          <CardHeader>
            <CardTitle className="text-muted-foreground text-xs font-normal tracking-wide uppercase">
              {tile.label}
            </CardTitle>
          </CardHeader>
          <CardContent className="text-2xl font-semibold tabular-nums">
            {tile.value.toLocaleString()}
          </CardContent>
        </Card>
      ))}
    </div>
  )
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `pnpm test dashboard-stat-tiles`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/components/dashboard-stat-tiles.tsx src/components/dashboard-stat-tiles.test.tsx
git commit -m "feat: add dashboard stat tiles"
```

---

### Task 7: `dashboard-activity-chart.tsx`

**Files:**

- Create: `src/components/dashboard-activity-chart.tsx`
- Test: `src/components/dashboard-activity-chart.test.tsx`

**Interfaces:**

- Consumes: `DailyWordCount[]` (Task 4), `ChartContainer`/`ChartConfig` (existing, `#components/ui/chart`)
- Produces: `DashboardActivityChart({ days: DailyWordCount[] })`

- [ ] **Step 1: Write the failing test**

Create `src/components/dashboard-activity-chart.test.tsx`:

```tsx
import { render, screen } from '@testing-library/react'

import { DashboardActivityChart } from '#components/dashboard-activity-chart'
import type { DailyWordCount } from '#lib/types'

const days: DailyWordCount[] = [
  { date: '2026-01-01', wordDelta: 10 },
  { date: '2026-01-02', wordDelta: -3 }
]

test('renders the chart container', () => {
  render(<DashboardActivityChart days={days} />)
  expect(screen.getByTestId('dashboard-activity-chart')).toBeInTheDocument()
})
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `pnpm test dashboard-activity-chart`
Expected: FAIL — module not found.

- [ ] **Step 3: Write the implementation**

Create `src/components/dashboard-activity-chart.tsx`:

```tsx
import { format, parseISO } from 'date-fns'
import { Area, AreaChart, CartesianGrid, XAxis } from 'recharts'

import { ChartContainer, type ChartConfig } from '#components/ui/chart'
import type { DailyWordCount } from '#lib/types'

const chartConfig: ChartConfig = {
  wordDelta: { label: 'Words written', color: 'var(--chart-1)' }
}

export function DashboardActivityChart({ days }: { days: DailyWordCount[] }) {
  return (
    <ChartContainer
      config={chartConfig}
      data-testid="dashboard-activity-chart"
      className="aspect-auto h-48 w-full"
    >
      <AreaChart data={days}>
        <CartesianGrid vertical={false} />
        <XAxis
          dataKey="date"
          tickLine={false}
          axisLine={false}
          minTickGap={32}
          tickFormatter={(value: string) => format(parseISO(value), 'MMM d')}
        />
        <Area
          dataKey="wordDelta"
          type="monotone"
          fill="var(--color-wordDelta)"
          stroke="var(--color-wordDelta)"
          fillOpacity={0.2}
        />
      </AreaChart>
    </ChartContainer>
  )
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `pnpm test dashboard-activity-chart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/components/dashboard-activity-chart.tsx src/components/dashboard-activity-chart.test.tsx
git commit -m "feat: add dashboard words-written area chart"
```

---

### Task 8: activity-level bucketing + `dashboard-heatmap.tsx`

**Files:**

- Create: `src/lib/activity-level.ts`
- Test: `src/lib/activity-level.test.ts`
- Create: `src/components/dashboard-heatmap.tsx`
- Test: `src/components/dashboard-heatmap.test.tsx`

**Interfaces:**

- Produces: `bucketActivityLevel(count: number): 'none' | 'low' | 'medium' | 'high'`
- Consumes: `bucketActivityLevel`, `DailyActivity[]` (Task 4)
- Produces: `DashboardHeatmap({ days: DailyActivity[] })`

- [ ] **Step 1: Write the failing test for the pure bucketing function**

Create `src/lib/activity-level.test.ts`:

```ts
import { bucketActivityLevel } from '#lib/activity-level'

test.each([
  [0, 'none'],
  [1, 'low'],
  [2, 'low'],
  [3, 'medium'],
  [5, 'medium'],
  [6, 'high'],
  [20, 'high']
])('bucketActivityLevel(%i) is %s', (count, expected) => {
  expect(bucketActivityLevel(count)).toBe(expected)
})
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `pnpm test activity-level`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement the bucketing function**

Create `src/lib/activity-level.ts`:

```ts
export type ActivityLevel = 'none' | 'low' | 'medium' | 'high'

export function bucketActivityLevel(count: number): ActivityLevel {
  if (count === 0) return 'none'
  if (count <= 2) return 'low'
  if (count <= 5) return 'medium'
  return 'high'
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `pnpm test activity-level`
Expected: PASS.

- [ ] **Step 5: Write the failing test for the heatmap component**

Create `src/components/dashboard-heatmap.test.tsx`:

```tsx
import { render, screen } from '@testing-library/react'

import { DashboardHeatmap } from '#components/dashboard-heatmap'
import type { DailyActivity } from '#lib/types'

test('renders one cell per day, each with a title describing the count', () => {
  const days: DailyActivity[] = [
    { date: '2026-01-01', activityCount: 0 },
    { date: '2026-01-02', activityCount: 4 }
  ]
  render(<DashboardHeatmap days={days} />)
  expect(screen.getByTestId('heatmap-cell-2026-01-01')).toHaveAttribute(
    'title',
    expect.stringContaining('0 edits')
  )
  expect(screen.getByTestId('heatmap-cell-2026-01-02')).toHaveAttribute(
    'title',
    expect.stringContaining('4 edits')
  )
})
```

- [ ] **Step 6: Run the test to verify it fails**

Run: `pnpm test dashboard-heatmap`
Expected: FAIL — module not found.

- [ ] **Step 7: Write the heatmap implementation**

Create `src/components/dashboard-heatmap.tsx`:

```tsx
import { format, parseISO } from 'date-fns'

import { bucketActivityLevel } from '#lib/activity-level'
import type { DailyActivity } from '#lib/types'

// 35 days = exactly 5 full weeks, so a plain 7-column grid in chronological
// order naturally keeps every column aligned to the same weekday - no
// leading blank cells needed, unlike a literal calendar-month grid.
const LEVEL_CLASSES: Record<string, string> = {
  none: 'bg-muted',
  low: 'bg-primary/25',
  medium: 'bg-primary/55',
  high: 'bg-primary/90'
}

export function DashboardHeatmap({ days }: { days: DailyActivity[] }) {
  return (
    <div data-testid="dashboard-heatmap" className="grid grid-cols-7 gap-1">
      {days.map((day) => {
        const level = bucketActivityLevel(day.activityCount)
        const label = `${day.activityCount} edit${day.activityCount === 1 ? '' : 's'}`
        return (
          <div
            key={day.date}
            data-testid={`heatmap-cell-${day.date}`}
            title={`${format(parseISO(day.date), 'MMM d')}: ${label}`}
            className={`aspect-square rounded-sm ${LEVEL_CLASSES[level]}`}
          />
        )
      })}
    </div>
  )
}
```

- [ ] **Step 8: Run the test to verify it passes**

Run: `pnpm test dashboard-heatmap`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add src/lib/activity-level.ts src/lib/activity-level.test.ts src/components/dashboard-heatmap.tsx src/components/dashboard-heatmap.test.tsx
git commit -m "feat: add dashboard activity heatmap"
```

---

### Task 9: `dashboard-recent-list.tsx`

**Files:**

- Create: `src/components/dashboard-recent-list.tsx`
- Test: `src/components/dashboard-recent-list.test.tsx`

**Interfaces:**

- Consumes: `DocumentMeta[]` (existing)
- Produces: `DashboardRecentList({ docs: DocumentMeta[] })`

- [ ] **Step 1: Write the failing tests**

Create `src/components/dashboard-recent-list.test.tsx`:

```tsx
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter, Route, Routes } from 'react-router'

import { DashboardRecentList } from '#components/dashboard-recent-list'
import type { DocumentMeta } from '#lib/types'

const meta = (over: Partial<DocumentMeta> = {}): DocumentMeta => ({
  id: 'a',
  parentId: null,
  title: 'Alpha',
  icon: null,
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  deletedAt: null,
  ...over
})

test('shows an empty-state prompt when there are no documents', () => {
  render(
    <MemoryRouter>
      <DashboardRecentList docs={[]} />
    </MemoryRouter>
  )
  expect(screen.getByTestId('dashboard-recent-empty')).toBeInTheDocument()
})

test('falls back to "Untitled" for an empty title, and navigates on click', async () => {
  render(
    <MemoryRouter initialEntries={['/']}>
      <Routes>
        <Route
          path="/"
          element={<DashboardRecentList docs={[meta({ title: '' })]} />}
        />
        <Route path="/doc/:id" element={<div data-testid="doc-page" />} />
      </Routes>
    </MemoryRouter>
  )
  const row = screen.getByTestId('dashboard-recent-a')
  expect(row).toHaveTextContent('Untitled')
  await userEvent.click(row)
  expect(await screen.findByTestId('doc-page')).toBeInTheDocument()
})
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `pnpm test dashboard-recent-list`
Expected: FAIL — module not found.

- [ ] **Step 3: Write the implementation**

Create `src/components/dashboard-recent-list.tsx`:

```tsx
import { useNavigate } from 'react-router'

import type { DocumentMeta } from '#lib/types'

export function DashboardRecentList({ docs }: { docs: DocumentMeta[] }) {
  const navigate = useNavigate()

  if (docs.length === 0) {
    return (
      <p
        data-testid="dashboard-recent-empty"
        className="text-muted-foreground text-sm"
      >
        Create your first document to see it here.
      </p>
    )
  }

  return (
    <ul data-testid="dashboard-recent-list" className="flex flex-col gap-1">
      {docs.map((doc) => (
        <li key={doc.id}>
          <button
            type="button"
            onClick={() => navigate(`/doc/${doc.id}`)}
            data-testid={`dashboard-recent-${doc.id}`}
            className="hover:bg-accent flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left text-sm transition-colors"
          >
            {doc.icon && <span>{doc.icon}</span>}
            <span className="truncate">{doc.title || 'Untitled'}</span>
          </button>
        </li>
      ))}
    </ul>
  )
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `pnpm test dashboard-recent-list`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/components/dashboard-recent-list.tsx src/components/dashboard-recent-list.test.tsx
git commit -m "feat: add dashboard recently-edited list"
```

---

### Task 10: `dashboard-page.tsx` — compose everything, error handling, empty state

**Files:**

- Modify: `src/pages/dashboard-page.tsx`
- Create: `src/pages/dashboard-page.test.tsx`
- Modify: `src/lib/errors.ts`

**Interfaces:**

- Consumes: every component from Tasks 5-9, `dashboardStatsAtom`/`recentDocsAtom`/`refreshDashboardAtom` (Task 4), `reportError` (existing, `#lib/errors`)
- Produces: `DashboardPage` (default export, replaces the stub)

- [ ] **Step 1: Add the new error code**

In `src/lib/errors.ts`, add `'HK-7001'` to the `HkErrorCode` union (right after `'HK-6002'`):

```ts
  | 'HK-6002'
  | 'HK-7001'
  | 'HK-9001'
```

and add its definition to `ERROR_DEFINITIONS`, right after the `'HK-6002'` entry:

```ts
  'HK-6002': {
    message: 'Could not export the logs.',
    severity: 'error',
    openSettings: 'logs'
  },
  'HK-7001': {
    message: 'Could not load dashboard stats.',
    severity: 'error'
  },
```

- [ ] **Step 2: Write the failing tests**

Create `src/pages/dashboard-page.test.tsx`:

```tsx
import { render, screen } from '@testing-library/react'
import { getDefaultStore } from 'jotai'
import { MemoryRouter } from 'react-router'

import DashboardPage from '#pages/dashboard-page'
import { backend } from '#lib/backend/index'
import { dashboardStatsAtom, recentDocsAtom } from '#lib/store'
import type { DashboardStats } from '#lib/types'

const stats: DashboardStats = {
  totalDocuments: 2,
  totalWords: 40,
  streakDays: 1,
  docsEditedThisWeek: 1,
  dailyWords: [{ date: '2026-01-01', wordDelta: 40 }],
  dailyActivity: [{ date: '2026-01-01', activityCount: 1 }]
}

afterEach(() => {
  getDefaultStore().set(dashboardStatsAtom, null)
  getDefaultStore().set(recentDocsAtom, [])
  vi.restoreAllMocks()
})

test('fetches stats and recent documents on mount and renders every section', async () => {
  vi.spyOn(backend, 'getDashboardStats').mockResolvedValue(stats)
  vi.spyOn(backend, 'getRecentDocuments').mockResolvedValue([])

  render(
    <MemoryRouter>
      <DashboardPage />
    </MemoryRouter>
  )

  expect(await screen.findByTestId('dashboard-greeting')).toBeInTheDocument()
  expect(screen.getByTestId('dashboard-stat-tiles')).toBeInTheDocument()
  expect(screen.getByTestId('dashboard-activity-chart')).toBeInTheDocument()
  expect(screen.getByTestId('dashboard-heatmap')).toBeInTheDocument()
  expect(screen.getByTestId('dashboard-recent-empty')).toBeInTheDocument()
  expect(screen.getByTestId('stat-tile-total-documents')).toHaveTextContent('2')
})

test('a failed load reports HK-7001 and still renders a zeroed page instead of crashing', async () => {
  vi.spyOn(backend, 'getDashboardStats').mockRejectedValue(new Error('boom'))
  vi.spyOn(backend, 'getRecentDocuments').mockResolvedValue([])

  render(
    <MemoryRouter>
      <DashboardPage />
    </MemoryRouter>
  )

  expect(await screen.findByTestId('dashboard-greeting')).toBeInTheDocument()
  expect(screen.getByTestId('dashboard-recent-empty')).toBeInTheDocument()
})
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `pnpm test dashboard-page`
Expected: FAIL — the stub page has none of these `data-testid`s.

- [ ] **Step 4: Write the implementation**

Replace the entire contents of `src/pages/dashboard-page.tsx`:

```tsx
import { useAtomValue, useSetAtom } from 'jotai'
import { useEffect } from 'react'

import { DashboardActivityChart } from '#components/dashboard-activity-chart'
import { DashboardGreeting } from '#components/dashboard-greeting'
import { DashboardHeatmap } from '#components/dashboard-heatmap'
import { DashboardRecentList } from '#components/dashboard-recent-list'
import { DashboardStatTiles } from '#components/dashboard-stat-tiles'
import { reportError } from '#lib/errors'
import {
  dashboardStatsAtom,
  recentDocsAtom,
  refreshDashboardAtom
} from '#lib/store'

const EMPTY_STATS = {
  totalDocuments: 0,
  totalWords: 0,
  streakDays: 0,
  docsEditedThisWeek: 0,
  dailyWords: [],
  dailyActivity: []
}

export default function DashboardPage() {
  const stats = useAtomValue(dashboardStatsAtom)
  const recentDocs = useAtomValue(recentDocsAtom)
  const refreshDashboard = useSetAtom(refreshDashboardAtom)

  useEffect(() => {
    let active = true
    refreshDashboard().catch(() => {
      if (active) reportError('HK-7001')
    })
    return () => {
      active = false
    }
  }, [refreshDashboard])

  const shown = stats ?? EMPTY_STATS

  return (
    <div
      data-testid="dashboard-page"
      className="mx-auto flex w-full max-w-3xl flex-col gap-8 p-8"
    >
      <DashboardGreeting />
      <DashboardStatTiles stats={shown} />
      <DashboardActivityChart days={shown.dailyWords} />
      <DashboardHeatmap days={shown.dailyActivity} />
      <div>
        <h2 className="mb-2 text-sm font-medium">Recently edited</h2>
        <DashboardRecentList docs={recentDocs} />
      </div>
    </div>
  )
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `pnpm test dashboard-page`
Expected: PASS.

- [ ] **Step 6: Run the full unit test suite, `tsc`, and lint**

Run: `pnpm test -- run && pnpm exec tsc --noEmit && pnpm lint`
Expected: everything passes — this is the first point where every piece from Tasks 1-9 is wired together end to end.

- [ ] **Step 7: Commit**

```bash
git add src/pages/dashboard-page.tsx src/pages/dashboard-page.test.tsx src/lib/errors.ts
git commit -m "feat: compose the real dashboard page from its stat/chart/heatmap/list pieces"
```

---

### Task 11: Playwright e2e

**Files:**

- Modify: `e2e-tests/app.spec.ts`

**Interfaces:**

- Consumes: every `data-testid` from Tasks 5-10 (`dashboard-new-doc`, `stat-tile-*`, `dashboard-activity-chart`, `dashboard-heatmap`, `dashboard-recent-list`), plus existing ones (`new-doc`, `editor`, `nav-dashboard`, `doc-title`)

- [ ] **Step 1: Write the failing test**

Add to `e2e-tests/app.spec.ts`, at the end of the file:

```ts
test.describe('Dashboard', () => {
  test('creating and editing a document updates the dashboard stats, chart, heatmap, and recent list', async ({
    page
  }) => {
    await page.goto('/')
    await expect(page.getByTestId('stat-tile-total-documents')).toContainText(
      '0'
    )

    await page.getByTestId('new-doc').click()
    const editable = page
      .getByTestId('editor')
      .locator('[contenteditable="true"]')
      .first()
    await editable.click()
    await page.keyboard.type('one two three four five')
    // Same 800ms-debounced-autosave wait used elsewhere in this suite -
    // waits out the pending save rather than racing navigation against it.
    await page.waitForTimeout(1000)

    await page.getByTestId('nav-dashboard').click()
    await expect(page.getByTestId('stat-tile-total-documents')).toContainText(
      '1'
    )
    await expect(page.getByTestId('stat-tile-total-words')).toContainText('5')
    await expect(page.getByTestId('stat-tile-streak-days')).toContainText('1')
    await expect(
      page.getByTestId('stat-tile-docs-edited-this-week')
    ).toContainText('1')
    await expect(page.getByTestId('dashboard-activity-chart')).toBeVisible()
    await expect(page.getByTestId('dashboard-heatmap')).toBeVisible()
    await expect(page.getByTestId('dashboard-recent-list')).toContainText(
      'Untitled'
    )
  })

  test("the dashboard's New document button creates a document and navigates to it", async ({
    page
  }) => {
    await page.goto('/')
    await page.getByTestId('dashboard-new-doc').click()
    await expect(page).toHaveURL(/#\/doc\//)
    await expect(page.getByTestId('doc-title')).toBeVisible()
  })
})
```

- [ ] **Step 2: Run the test to verify it passes**

Run: `pnpm exec playwright test -g "Dashboard"`
Expected: PASS — by this point in the plan (after Task 10's commit) the feature is fully wired, so this test should already be green; running it here is what proves the e2e layer genuinely exercises the real Tauri-mocked-IPC dev-server flow end to end, not just the unit-test layer's assumptions about it.

- [ ] **Step 3: Run the full e2e suite**

Run: `pnpm exec playwright test`
Expected: every test passes except the 3 pre-existing, unrelated "floating badges" failures already documented as predating this work.

- [ ] **Step 4: Commit**

```bash
git add e2e-tests/app.spec.ts
git commit -m "test: cover the dashboard end to end"
```

---

## Self-review

**Spec coverage:** every §2/§3 architecture item has a task — activity write path (Task 1), `dashboard_stats`/`recent_documents` (Task 2), word-count helper (Task 3), the full frontend data layer including both `Backend` implementations and atoms (Task 4), all five components (Tasks 5-9), the composed page with error handling and the empty-vault state (Task 10), e2e proof (Task 11). The §1 decisions (favorites deferred, signed word-delta, custom heatmap, no backfill, single `dashboard_stats` command, no live polling) are all reflected directly in the tasks above and restated in Global Constraints. The two corrections found during Rust verification (`utc_offset_minutes` instead of `local_today`, `upsert()` left untouched) and the one correction found during this self-review (merging the originally-split Task 4/5 into one so no task leaves `tsc` failing) are all documented in "Verified against the real codebase" with the reasoning for each.

**Placeholder scan:** no TBD/TODO markers; every step has real, complete code, not a description of code.

**Type consistency:** `DashboardStats`/`DailyWordCount`/`DailyActivity` are defined once in Task 4 (frontend) and Task 2 (Rust, with matching camelCase serialization via `serde(rename_all = "camelCase")`), and every later task imports rather than redefines them. `bucketActivityLevel`'s four levels (`none`/`low`/`medium`/`high`) match between Task 8's pure function and its `LEVEL_CLASSES` lookup in the same task's heatmap component. `refreshDocsAtom` (not a new atom) is what Task 5's greeting button reuses — confirmed against the real `sidebar-left.tsx` source, not assumed. Every cross-task "Interfaces: Consumes" reference (e.g. Task 6 consuming `DashboardStats` from Task 4, Task 10 consuming all of Tasks 5-9) points at a task number that actually produces that name after this renumbering pass.
