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
