use std::fs;
use std::path::{Path, PathBuf};

use crate::document::validate_id;
use crate::error::{AppError, Result};

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
}
