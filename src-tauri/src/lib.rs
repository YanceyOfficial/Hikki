mod ai;
mod asset;
mod commands;
mod document;
mod error;
mod fsx;
mod history;
mod index;
mod logging;
mod vault;

use std::sync::Mutex;

use tauri::Manager;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_http::init())
        .plugin(tauri_plugin_dialog::init())
        .register_uri_scheme_protocol("hikki-asset", |ctx, request| {
            let app = ctx.app_handle();
            let state = app.state::<commands::AppState>();
            let vault_path = state.settings.lock().unwrap_or_else(std::sync::PoisonError::into_inner).vault_path.clone();
            match asset::resolve_asset_path(&vault_path, request.uri().path()) {
                Ok(path) => {
                    let mime = asset::mime_for(&path);
                    match std::fs::read(&path) {
                        Ok(body) => {
                            let range_header = request.headers().get("range").and_then(|v| v.to_str().ok());
                            match asset::parse_range(range_header, body.len() as u64) {
                                Some((start, end)) => tauri::http::Response::builder()
                                    .status(206)
                                    .header("Content-Type", mime)
                                    .header("Accept-Ranges", "bytes")
                                    .header("Content-Range", format!("bytes {start}-{end}/{}", body.len()))
                                    .body(body[start as usize..=end as usize].to_vec())
                                    .unwrap(),
                                None => tauri::http::Response::builder()
                                    .header("Content-Type", mime)
                                    .header("Accept-Ranges", "bytes")
                                    .body(body)
                                    .unwrap(),
                            }
                        }
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
            commands::dashboard_stats,
            commands::recent_documents,
            commands::set_vault_path,
            commands::import_asset,
            commands::get_api_key,
            commands::set_api_key,
            commands::delete_api_key,
            commands::save_ai_settings,
            commands::get_ai_settings,
            commands::append_log,
            commands::read_logs,
            commands::clear_logs,
            commands::export_logs,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
