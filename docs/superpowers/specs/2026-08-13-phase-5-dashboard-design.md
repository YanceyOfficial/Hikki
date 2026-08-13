# Phase 5: Dashboard — Design

**Date:** 2026-08-13
**Status:** Approved (design review with user)
**Source spec:** `docs/superpowers/specs/2026-07-18-hikki-design.md` §3/§4/§10/§13 (the original 8-phase design this implements)

Replaces the current `DashboardPage` stub (`data-testid="dashboard-page"`, a heading and a "Charts arrive in Phase 5" placeholder, no logic) with a real landing page: stat tiles, a 30-day words-written area chart, a month-view activity heatmap, a recently-edited list, and a greeting header with a quick "New document" action — the scope the original design's §10 lays out, minus the "favorites" list it also mentions (see the first decision below).

---

## 1. Decisions made during design review

| Decision                                 | Choice                                                                                   | Rationale                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| ---------------------------------------- | ---------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Favorites on the dashboard               | Deferred entirely to Phase 6, alongside favorites itself                                 | §10 lists "favorites" as a dashboard list, but §13's phase table assigns the favorites feature itself (star toggle, schema, IPC, UI) to Phase 6 — nothing favorites-related exists in the codebase today. Building even a minimal favorites slice inside Phase 5 would expand this phase's scope beyond "dashboard"; Phase 5 ships with only the "recently edited" list, and Phase 6 adds a favorites list once favorites itself exists                                 |
| `word_delta` sign                        | Signed — can be negative                                                                 | The `activity` table (already in the SQLite schema, currently dead/unwritten) names the column `word_delta`, not `words_added`; a save that nets out to fewer words (user deleted a paragraph) should show as a real dip in the chart, not be clamped to zero. Computed as `new_word_count - old_word_count` on every `create_document`/`save_document` call, in the same transaction as the `documents` upsert so the two can never drift apart                        |
| Streak definition                        | Consecutive days with ≥1 `activity` row, counted backward from today **or yesterday**    | Matches the common "don't punish someone before their day is over" streak convention (Duolingo/GitHub-style): if today has no activity yet, the streak still reflects the count through yesterday rather than dropping to 0 the moment midnight — it only actually breaks once a full day passes with zero activity                                                                                                                                                     |
| Calendar heatmap implementation          | Custom-built component, no new dependency                                                | No heatmap/contribution-graph library exists in the repo today (confirmed via a full-repo grep), and `calendar.tsx` is a `react-day-picker` date-picker, not a heatmap. A CSS-grid month view matches this app's established pattern of hand-building small visual primitives to fit its own soft, muted-token design language (`table-of-contents.tsx`, `heading-anchor-overlay.tsx`) rather than pulling in a third-party component that would need re-theming anyway |
| Historical backfill                      | None — the chart/heatmap/streak only reflect activity from the moment this feature ships | `document.json` stores only current content, not edit history, so there's no way to reconstruct past daily word deltas for existing documents without reading through every kept version-history snapshot (10-min-coalesced, 50 kept per doc) and diffing them — real added complexity with no spec requirement calling for it. A first cut starts every user's dashboard at zero and fills in going forward                                                            |
| `dashboard_stats` shape                  | One combined Rust query/command, not several granular ones                               | Matches the original design's own §4 command surface, which names a single `dashboard_stats` query; the dashboard page needs all of it on every mount, so one round-trip is both simpler and cheaper than four                                                                                                                                                                                                                                                          |
| Live updates while the dashboard is open | None — fetch-once on mount                                                               | This is a single-window app; a user can't be editing a document (which is what drives new `activity` rows) while the dashboard page itself is mounted. Matches the existing pattern elsewhere (`docMetasAtom` is refreshed by explicit calls after actions, not polled)                                                                                                                                                                                                 |

## 2. Architecture

**Rust (`src-tauri/src/index.rs`, `commands.rs`):** the `activity` table already exists in the schema (`id, doc_id, kind, word_delta, at`) but nothing writes to or reads from it today; `documents.word_count` is likewise already computed on every `upsert()` but never selected back out. This phase wires both up:

- `Index::upsert()` captures the document's previous `word_count` (already available at the call site, before the new value overwrites it) and inserts one `activity` row per call — `kind = 'create'` from `create_document_impl`, `kind = 'edit'` from `save_document_impl`, `word_delta = new_count - old_count` (0 on a document's first save) — in the same transaction as the `documents` write.
- A new `Index::dashboard_stats(local_today: &str)` method backs a new `dashboard_stats` command, returning one struct in one IPC round-trip:

  ```rust
  pub struct DashboardStats {
      pub total_documents: i64,             // COUNT(*) WHERE deleted_at IS NULL
      pub total_words: i64,                 // SUM(word_count) WHERE deleted_at IS NULL
      pub streak_days: i64,                 // consecutive days with ≥1 activity row, from today or yesterday
      pub docs_edited_this_week: i64,       // COUNT(DISTINCT doc_id) in activity, rolling 7 days
      pub daily_words: Vec<DailyWordCount>, // last 30 days: { date, word_delta }
      pub daily_activity: Vec<DailyActivity>, // last 35 days (enough to fill a month grid): { date, activity_count }
  }
  ```

  `local_today` is the caller's local calendar date (`"YYYY-MM-DD"`, computed frontend-side via a plain JS `new Date()` in local time — never UTC `now()`) and is the single anchor every day-bucketed field above counts backward from. `activity.at` itself stays stored as UTC (matching `created_at`/`updated_at`'s existing convention), but all _grouping into days_ — streak, the rolling week, the 30-day chart, the 35-day heatmap — buckets relative to this passed-in local anchor date rather than SQLite's own UTC-based `date()` function, so a user's streak/heatmap doesn't appear to reset or misalign near midnight for anyone not in UTC.

- A separate `recently_edited` query (existing `list_metas` shape, `ORDER BY updated_at DESC LIMIT 8`) backs a new `recent_documents` command — kept separate from `dashboard_stats` since it returns a different shape (`DocumentMeta[]`, already used elsewhere) and there's no cost benefit to folding it in.

**Frontend:** `Backend` (`src/lib/backend/backend.ts`) gains two methods:

```ts
getDashboardStats(): Promise<DashboardStats>
getRecentDocuments(limit: number): Promise<DocumentMeta[]>
```

`getDashboardStats()` stays parameterless in this public interface — component code shouldn't need to know about the local-date-anchoring detail above. `TauriBackend`'s implementation computes today's local date (`date-fns`' `format(new Date(), 'yyyy-MM-dd')`, already a project dependency) and passes it as the `local_today` IPC payload field to the `dashboard_stats` command. Both methods are implemented in `TauriBackend` (1:1 `invoke()` calls, matching every existing method) and in `MemoryBackend`, which needs its own from-scratch activity simulation — computing `word_count` the same way the Rust side does (`extractText(blocks)`, whitespace-split count), the same local-date anchoring, and appending to an in-memory activity log on every `createDocument`/`saveDocument` call, so dev-mode and Playwright behavior matches production logic exactly rather than faking a plausible-looking response.

Two new Jotai atoms (`src/lib/store.ts`): `dashboardStatsAtom`, `recentDocsAtom`, populated by a `refreshDashboardAtom` write-atom called once from `DashboardPage`'s mount effect (mirrors the existing `refreshDocsAtom` pattern for `docMetasAtom`).

## 3. Components & data flow

- `src/pages/dashboard-page.tsx` (replacing the stub) composes five new components, each reading only the atoms above:
  - `dashboard-greeting.tsx` — time-of-day greeting + today's date, and a "New document" button reusing the exact `backend.createDocument(null, 'Untitled')` + navigate logic `sidebar-left.tsx`'s existing new-doc button already has.
  - `dashboard-stat-tiles.tsx` — four tiles from `dashboardStatsAtom`: total documents, total words, streak, docs edited this week.
  - `dashboard-activity-chart.tsx` — an area chart via the already-installed `recharts` + the existing shadcn `chart.tsx` wrapper, fed `dashboardStats.dailyWords`.
  - `dashboard-heatmap.tsx` — the new custom month-grid component, fed `dashboardStats.dailyActivity`, cell color intensity bucketed (none/low/medium/high) using the app's existing muted/`--radius` token system, not new colors.
  - `dashboard-recent-list.tsx` — from `recentDocsAtom`, each row linking to `#/doc/:id`, reusing the sidebar tree's existing navigation pattern.
- **Data flow, end to end:** typing in the editor → existing debounced autosave → `save_document` → `Index::upsert()` writes `documents` and `activity` together → next dashboard visit → `DashboardPage` mount → one `getDashboardStats()` + one `getRecentDocuments(8)` round-trip → atoms populate → all five components render from them. No other page reads these atoms; this is a self-contained leaf feature that doesn't touch the sidebar, editor, or search paths.

## 4. Error handling & testing

- `getDashboardStats()`/`getRecentDocuments()` failures route through the existing `reportError()` funnel under a new `HK-7xxx` code (the next free band after this app's existing `1xxx`/`2xxx`/`3xxx`/`6xxx`/`9xxx` groups), toasting and falling back to a zeroed/empty page state rather than crashing — consistent with `document-page.tsx`'s existing load-failure handling.
- **Empty-vault state** (day one, zero `activity` rows): tiles show `0`, the area chart renders its native all-zero-series empty state, the heatmap renders every cell unlit, and the recent list shows a "Create your first document" prompt reusing the greeting's own "New document" button.
- **`cargo test`:** `Index::dashboard_stats()` — word-delta sign across growth/shrink/first-save-is-zero; streak calculation across day boundaries (today-not-yet-written still counts through yesterday; a full gap day resets to 0); `docs_edited_this_week`'s rolling-7-day boundary; confirms `create_document`/`save_document` each write exactly one correctly-`kind`ed `activity` row in the same transaction as their `documents` write.
- **Vitest:** `MemoryBackend`'s activity simulation needs the same edge-case coverage as the Rust tests above, since it's an independent reimplementation that must stay behaviorally identical; each of the five dashboard components tested with seeded atom values (empty state, populated state).
- **Playwright:** create a document, type content, navigate to the dashboard, assert the tiles/chart/heatmap/list reflect it — the first real end-to-end proof that the Rust activity-write path and the frontend read path agree with each other.

## 5. Out of scope

- Favorites, in any form (§1) — deferred to Phase 6 alongside the feature itself.
- Historical backfill of activity data for documents that existed before this feature ships (§1) — the dashboard starts accumulating from zero going forward.
- Live/polling updates while the dashboard page is open (§1) — fetch-once on mount is sufficient for a single-window app.
- Per-document or per-tag breakdowns of the word-count chart (e.g. "words written in Project X") — the original design's §10 scope is whole-vault aggregate stats only.
- A year-view heatmap (GitHub-contributions-style) — §10 specifically calls for a month view; a year view would need a different layout and isn't requested.
