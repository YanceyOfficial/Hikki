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
