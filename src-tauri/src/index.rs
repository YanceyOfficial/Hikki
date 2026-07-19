use std::path::Path;

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
}
