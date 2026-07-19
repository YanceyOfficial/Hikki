mod asset;
mod commands;
mod document;
mod error;
mod fsx;
mod index;
mod vault;

use std::sync::Mutex;

use tauri::Manager;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .register_uri_scheme_protocol("hikki-asset", |ctx, request| {
            let app = ctx.app_handle();
            let state = app.state::<commands::AppState>();
            let vault_path = state.settings.lock().unwrap_or_else(std::sync::PoisonError::into_inner).vault_path.clone();
            match asset::resolve_asset_path(&vault_path, request.uri().path()) {
                Ok(path) => {
                    let mime = asset::mime_for(&path);
                    match std::fs::read(&path) {
                        Ok(body) => tauri::http::Response::builder()
                            .header("Content-Type", mime)
                            .body(body)
                            .unwrap(),
                        Err(_) => tauri::http::Response::builder().status(404).body(Vec::new()).unwrap(),
                    }
                }
                Err(_) => tauri::http::Response::builder().status(404).body(Vec::new()).unwrap(),
            }
        })
        .setup(|app| {
            let app_data_dir = app.path().app_data_dir()?;
            std::fs::create_dir_all(&app_data_dir)?;
            let settings = vault::load_settings(&app_data_dir);
            vault::ensure_vault(&settings.vault_path)?;
            let mut idx = index::Index::open(&app_data_dir.join("index.db"))?;
            idx.reconcile(&settings.vault_path)?;
            app.manage(commands::AppState {
                app_data_dir,
                settings: Mutex::new(settings),
                index: Mutex::new(idx),
            });
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::get_vault_info,
            commands::list_documents,
            commands::create_document,
            commands::load_document,
            commands::save_document,
            commands::delete_document,
            commands::search,
            commands::rebuild_index,
            commands::set_vault_path,
            commands::import_asset,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
