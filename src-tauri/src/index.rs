use std::collections::{BTreeMap, HashSet};
use std::path::Path;

use chrono::{DateTime, Duration, NaiveDate, Utc};
use rusqlite::Connection;
use serde::Serialize;

use crate::document::{self, Document};
use crate::error::Result;

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
CREATE INDEX IF NOT EXISTS idx_activity_at ON activity(at);
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
        let mut count = 0;
        for meta in &metas {
            let doc = match document::load_document(vault, &meta.id) {
                Ok(doc) => doc,
                Err(err) => {
                    eprintln!("hikki: skipping unindexable document {}: {err}", meta.id);
                    continue;
                }
            };
            self.upsert(&doc)?;
            count += 1;
        }
        Ok(count)
    }

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

    /// `utc_offset_minutes` is the caller's local UTC offset (JS's
    /// `Date.prototype.getTimezoneOffset()` convention: positive means local
    /// time is *behind* UTC, e.g. 480 for UTC-8). All day-bucketing (streak,
    /// the rolling week, the 30/35-day series) shifts each row's UTC `at` by
    /// this offset before taking its calendar date, rather than relying on
    /// SQLite's own UTC-based `date()` function - done here in Rust (not
    /// SQL) so the bucketing logic is plain, unit-testable code.
    pub fn dashboard_stats(&self, utc_offset_minutes: i64) -> Result<DashboardStats> {
        self.dashboard_stats_at(utc_offset_minutes, Utc::now())
    }

    /// `now`-parametrized core of [`Index::dashboard_stats`], so day-bucketing
    /// tests can pin an exact instant instead of racing the wall clock.
    fn dashboard_stats_at(
        &self,
        utc_offset_minutes: i64,
        now: DateTime<Utc>,
    ) -> Result<DashboardStats> {
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
        let today = (now - offset).date_naive();
        // 45 days of UTC-timestamped rows safely covers the 35-day local
        // window at any real-world offset (max ±14h).
        let cutoff = (now - Duration::days(45)).to_rfc3339();

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

        // Streak: a separate, unbounded query from the 45-day window above - a
        // real streak can run longer than 45 days without being silently
        // capped, unlike the fixed-length 30/35-day series which don't need
        // more than 45 days of history.
        let mut all_at_stmt = self.conn.prepare("SELECT at FROM activity")?;
        let all_at: Vec<String> = all_at_stmt
            .query_map([], |r| r.get(0))?
            .collect::<std::result::Result<Vec<_>, _>>()?;
        let activity_days: HashSet<NaiveDate> = all_at.iter().filter_map(|at| local_day(at)).collect();

        let mut streak_days = 0i64;
        let mut cursor = today;
        if !activity_days.contains(&cursor) {
            cursor -= Duration::days(1);
        }
        while activity_days.contains(&cursor) {
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
            threads: serde_json::Value::Object(serde_json::Map::new()),
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
        // A fixed reference instant, not Utc::now() - this test's correctness
        // must not depend on what time of day it happens to run.
        let base: DateTime<Utc> = "2026-06-15T12:00:00Z".parse().unwrap();
        idx.record_activity("d1", "edit", 10, &base.to_rfc3339()).unwrap();
        // 23:30 UTC "today" is already tomorrow for a UTC+2 caller, but
        // still today for a UTC caller.
        let almost_midnight_utc = base.date_naive().and_hms_opt(23, 30, 0).unwrap().and_utc();
        idx.record_activity("d2", "edit", 5, &almost_midnight_utc.to_rfc3339()).unwrap();

        let utc_plus_2 = idx.dashboard_stats_at(-120, base).unwrap();
        assert_eq!(
            utc_plus_2.daily_words.last().unwrap().word_delta,
            10,
            "the 23:30 UTC row should already be tomorrow for a UTC+2 caller"
        );

        let utc = idx.dashboard_stats_at(0, base).unwrap();
        assert_eq!(
            utc.daily_words.last().unwrap().word_delta,
            15,
            "both rows fall on today's UTC calendar date for a UTC caller"
        );
    }

    #[test]
    fn dashboard_stats_daily_words_reflects_a_net_negative_delta_from_a_shrink() {
        let idx = Index::open_in_memory().unwrap();
        let now = Utc::now();
        idx.record_activity("d1", "edit", 10, &now.to_rfc3339()).unwrap();
        idx.record_activity("d1", "edit", -4, &now.to_rfc3339()).unwrap();
        let stats = idx.dashboard_stats(0).unwrap();
        assert_eq!(stats.daily_words.last().unwrap().word_delta, 6);
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
    fn dashboard_stats_streak_is_not_capped_by_the_45_day_series_window() {
        let idx = Index::open_in_memory().unwrap();
        for i in 0..50 {
            idx.record_activity("d1", "edit", 1, &(Utc::now() - Duration::days(i)).to_rfc3339())
                .unwrap();
        }
        assert_eq!(idx.dashboard_stats(0).unwrap().streak_days, 50);
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
    fn dashboard_stats_docs_edited_this_week_boundary_is_six_days_ago_inclusive() {
        let idx = Index::open_in_memory().unwrap();
        idx.record_activity("d1", "edit", 1, &(Utc::now() - Duration::days(6)).to_rfc3339()).unwrap();
        idx.record_activity("d2", "edit", 1, &(Utc::now() - Duration::days(7)).to_rfc3339()).unwrap();
        let stats = idx.dashboard_stats(0).unwrap();
        assert_eq!(stats.docs_edited_this_week, 1, "6 days ago is in the window, 7 days ago is not");
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
}
