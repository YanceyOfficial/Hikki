use std::path::PathBuf;
use std::sync::{Mutex, MutexGuard};

use serde::Serialize;
use tauri::State;

use crate::document::{self, Document, DocumentMeta};
use crate::error::Result;
use crate::index::{Index, SearchHit};
use crate::vault::{self, AppSettings};

pub struct AppState {
    pub app_data_dir: PathBuf,
    pub settings: Mutex<AppSettings>,
    pub index: Mutex<Index>,
}

/// Locks, recovering from poisoning: our state stays structurally valid even
/// if a panic unwound mid-command (SQLite transactions roll back on drop).
fn lock<T>(m: &Mutex<T>) -> MutexGuard<'_, T> {
    m.lock().unwrap_or_else(std::sync::PoisonError::into_inner)
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct VaultInfo {
    pub vault_path: String,
    pub document_count: usize,
}

pub fn get_vault_info_impl(state: &AppState) -> Result<VaultInfo> {
    let settings = lock(&state.settings);
    let metas = lock(&state.index).list_metas()?;
    Ok(VaultInfo {
        vault_path: settings.vault_path.to_string_lossy().into_owned(),
        document_count: metas.iter().filter(|m| m.deleted_at.is_none()).count(),
    })
}

pub fn list_documents_impl(state: &AppState) -> Result<Vec<DocumentMeta>> {
    lock(&state.index).list_metas()
}

pub fn create_document_impl(state: &AppState, parent_id: Option<String>, title: String) -> Result<Document> {
    let vault_path = lock(&state.settings).vault_path.clone();
    let doc = document::create_document(&vault_path, parent_id, &title)?;
    lock(&state.index).upsert(&doc)?;
    Ok(doc)
}

pub fn load_document_impl(state: &AppState, id: String) -> Result<Document> {
    let settings = lock(&state.settings);
    document::load_document(&settings.vault_path, &id)
}

pub fn save_document_impl(state: &AppState, doc: Document) -> Result<Document> {
    let vault_path = lock(&state.settings).vault_path.clone();
    let saved = document::save_document(&vault_path, doc)?;
    lock(&state.index).upsert(&saved)?;
    Ok(saved)
}

pub fn delete_document_impl(state: &AppState, id: String) -> Result<Vec<String>> {
    let vault_path = lock(&state.settings).vault_path.clone();
    let affected = document::delete_document(&vault_path, &id)?;
    let index = lock(&state.index);
    for doc_id in &affected {
        let doc = document::load_document(&vault_path, doc_id)?;
        index.upsert(&doc)?; // deleted_at now set → excluded from search
    }
    Ok(affected)
}

pub fn search_impl(state: &AppState, query: String) -> Result<Vec<SearchHit>> {
    lock(&state.index).search(&query)
}

pub fn rebuild_index_impl(state: &AppState) -> Result<usize> {
    let vault_path = lock(&state.settings).vault_path.clone();
    lock(&state.index).reconcile(&vault_path)
}

pub fn set_vault_path_impl(state: &AppState, path: String) -> Result<VaultInfo> {
    let new_root = PathBuf::from(path);
    vault::ensure_vault(&new_root)?;
    {
        let mut settings = lock(&state.settings);
        let candidate = AppSettings { vault_path: new_root, ..settings.clone() };
        vault::save_settings(&state.app_data_dir, &candidate)?;
        *settings = candidate;
    }
    rebuild_index_impl(state)?;
    get_vault_info_impl(state)
}

#[tauri::command]
pub fn get_vault_info(state: State<AppState>) -> Result<VaultInfo> {
    get_vault_info_impl(&state)
}

#[tauri::command]
pub fn list_documents(state: State<AppState>) -> Result<Vec<DocumentMeta>> {
    list_documents_impl(&state)
}

#[tauri::command]
pub fn create_document(state: State<AppState>, parent_id: Option<String>, title: String) -> Result<Document> {
    create_document_impl(&state, parent_id, title)
}

#[tauri::command]
pub fn load_document(state: State<AppState>, id: String) -> Result<Document> {
    load_document_impl(&state, id)
}

#[tauri::command]
pub fn save_document(state: State<AppState>, doc: Document) -> Result<Document> {
    save_document_impl(&state, doc)
}

#[tauri::command]
pub fn delete_document(state: State<AppState>, id: String) -> Result<Vec<String>> {
    delete_document_impl(&state, id)
}

#[tauri::command]
pub fn search(state: State<AppState>, query: String) -> Result<Vec<SearchHit>> {
    search_impl(&state, query)
}

#[tauri::command]
pub fn rebuild_index(state: State<AppState>) -> Result<usize> {
    rebuild_index_impl(&state)
}

#[tauri::command]
pub fn set_vault_path(state: State<AppState>, path: String) -> Result<VaultInfo> {
    set_vault_path_impl(&state, path)
}

pub fn import_asset_impl(state: &AppState, doc_id: String, file_name: String, bytes: Vec<u8>) -> Result<String> {
    let vault_path = lock(&state.settings).vault_path.clone();
    crate::asset::import_asset(&vault_path, &doc_id, &file_name, &bytes)
}

#[tauri::command]
pub fn import_asset(state: State<AppState>, doc_id: String, file_name: String, bytes: Vec<u8>) -> Result<String> {
    import_asset_impl(&state, doc_id, file_name, bytes)
}

#[tauri::command]
pub fn get_api_key(provider: String) -> Result<Option<String>> {
    crate::ai::get_api_key_impl(&provider)
}

#[tauri::command]
pub fn set_api_key(provider: String, key: String) -> Result<()> {
    crate::ai::set_api_key_impl(&provider, &key)
}

#[tauri::command]
pub fn delete_api_key(provider: String) -> Result<()> {
    crate::ai::delete_api_key_impl(&provider)
}

pub fn save_ai_settings_impl(
    state: &AppState,
    default_ai_provider: Option<String>,
    default_ai_model: Option<String>,
) -> Result<AppSettings> {
    let mut settings = lock(&state.settings);
    let candidate = AppSettings { default_ai_provider, default_ai_model, ..settings.clone() };
    vault::save_settings(&state.app_data_dir, &candidate)?;
    *settings = candidate.clone();
    Ok(candidate)
}

#[tauri::command]
pub fn save_ai_settings(
    state: State<AppState>,
    default_ai_provider: Option<String>,
    default_ai_model: Option<String>,
) -> Result<AppSettings> {
    save_ai_settings_impl(&state, default_ai_provider, default_ai_model)
}

#[tauri::command]
pub fn get_ai_settings(state: State<AppState>) -> Result<AppSettings> {
    Ok(lock(&state.settings).clone())
}

#[tauri::command]
pub fn append_log(state: State<AppState>, entry: crate::logging::LogEntry) -> Result<()> {
    crate::logging::append_log_impl(&state.app_data_dir, entry)
}

#[tauri::command]
pub fn read_logs(
    state: State<AppState>,
    filter: crate::logging::LogFilter,
) -> Result<Vec<crate::logging::LogEntry>> {
    crate::logging::read_logs_impl(&state.app_data_dir, filter)
}

#[tauri::command]
pub fn clear_logs(state: State<AppState>) -> Result<()> {
    crate::logging::clear_logs_impl(&state.app_data_dir)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn state() -> (tempfile::TempDir, tempfile::TempDir, AppState) {
        let vault_dir = tempfile::tempdir().unwrap();
        let data_dir = tempfile::tempdir().unwrap();
        vault::ensure_vault(vault_dir.path()).unwrap();
        let state = AppState {
            app_data_dir: data_dir.path().to_path_buf(),
            settings: Mutex::new(AppSettings {
                vault_path: vault_dir.path().to_path_buf(),
                default_ai_provider: None,
                default_ai_model: None,
            }),
            index: Mutex::new(Index::open_in_memory().unwrap()),
        };
        (vault_dir, data_dir, state)
    }

    #[test]
    fn create_updates_index_and_vault_info() {
        let (_v, _d, state) = state();
        let doc = create_document_impl(&state, None, "Note".into()).unwrap();
        assert_eq!(doc.title, "Note");
        assert_eq!(search_impl(&state, "note".into()).unwrap().len(), 1);
        assert_eq!(get_vault_info_impl(&state).unwrap().document_count, 1);
    }

    #[test]
    fn save_reindexes() {
        let (_v, _d, state) = state();
        let mut doc = create_document_impl(&state, None, "Old title".into()).unwrap();
        doc.title = "New title".into();
        save_document_impl(&state, doc).unwrap();
        assert!(search_impl(&state, "old".into()).unwrap().is_empty());
        assert_eq!(search_impl(&state, "new".into()).unwrap().len(), 1);
    }

    #[test]
    fn delete_removes_from_search() {
        let (_v, _d, state) = state();
        let doc = create_document_impl(&state, None, "Gone".into()).unwrap();
        delete_document_impl(&state, doc.id).unwrap();
        assert!(search_impl(&state, "gone".into()).unwrap().is_empty());
        // still listed (soft-deleted) so Trash UI can show it later
        assert_eq!(list_documents_impl(&state).unwrap().len(), 1);
    }

    #[test]
    fn set_vault_path_switches_vault_and_reindexes() {
        let (_v, _d, state) = state();
        create_document_impl(&state, None, "Old vault doc".into()).unwrap();
        let new_vault = tempfile::tempdir().unwrap();
        let info = set_vault_path_impl(&state, new_vault.path().to_string_lossy().into_owned()).unwrap();
        assert_eq!(info.document_count, 0);
        assert!(search_impl(&state, "old".into()).unwrap().is_empty());
        assert!(list_documents_impl(&state).unwrap().is_empty());
    }

    #[test]
    fn set_vault_path_failure_leaves_state_unchanged() {
        let (_v, _d, state) = state();
        let old_path = get_vault_info_impl(&state).unwrap().vault_path;
        // Make save_settings fail: replace app_data_dir with a FILE so create_dir_all/write fails.
        std::fs::remove_dir_all(&state.app_data_dir).unwrap();
        std::fs::write(&state.app_data_dir, b"not a dir").unwrap();
        let new_vault = tempfile::tempdir().unwrap();
        let result = set_vault_path_impl(&state, new_vault.path().to_string_lossy().into_owned());
        assert!(result.is_err());
        assert_eq!(get_vault_info_impl(&state).unwrap().vault_path, old_path);
    }

    #[test]
    fn list_documents_serves_from_index() {
        let (_v, _d, state) = state();
        let doc = create_document_impl(&state, None, "Indexed".into()).unwrap();
        // Remove from the index only — fs still has the doc. If list reads the
        // index (as required), the doc must disappear from the listing.
        lock(&state.index).remove(&doc.id).unwrap();
        assert!(list_documents_impl(&state).unwrap().is_empty());
    }

    #[test]
    fn save_ai_settings_impl_persists_and_preserves_vault_path() {
        let (_vault_dir, _data_dir, state) = state();
        let before_vault_path = lock(&state.settings).vault_path.clone();

        let updated = save_ai_settings_impl(
            &state,
            Some("anthropic".to_string()),
            Some("claude-test-model".to_string()),
        )
        .unwrap();

        assert_eq!(updated.default_ai_provider, Some("anthropic".to_string()));
        assert_eq!(updated.default_ai_model, Some("claude-test-model".to_string()));
        assert_eq!(updated.vault_path, before_vault_path);

        // Reloading from disk must see the same values.
        let reloaded = vault::load_settings(&state.app_data_dir);
        assert_eq!(reloaded.default_ai_provider, Some("anthropic".to_string()));
    }

    #[test]
    fn import_asset_stores_and_returns_file_name() {
        let (_v, _d, state) = state();
        let doc = create_document_impl(&state, None, "D".into()).unwrap();
        let stored = import_asset_impl(&state, doc.id.clone(), "a.png".into(), vec![1, 2, 3]).unwrap();
        let vault_path = std::path::PathBuf::from(get_vault_info_impl(&state).unwrap().vault_path);
        assert!(vault_path.join("documents").join(&doc.id).join("assets").join(&stored).is_file());
    }
}
