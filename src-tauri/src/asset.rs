use std::fs;
use std::path::Path;

use crate::document::validate_id;
use crate::error::Result;

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
