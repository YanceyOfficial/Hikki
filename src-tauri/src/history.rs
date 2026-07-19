use std::fs;
use std::path::{Path, PathBuf};

use crate::document::{validate_id, Document};
use crate::error::Result;

pub const SNAPSHOT_MIN_INTERVAL_SECS: i64 = 600;
pub const MAX_SNAPSHOTS: usize = 50;

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
