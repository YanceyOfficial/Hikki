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
