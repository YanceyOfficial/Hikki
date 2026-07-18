use std::fs;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::error::{AppError, Result};

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
