use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct AppSettings {
    pub vault_path: PathBuf,
    #[serde(default)]
    pub default_ai_provider: Option<String>,
    #[serde(default)]
    pub default_ai_model: Option<String>,
}

pub fn default_vault_path() -> PathBuf {
    dirs::home_dir().unwrap_or_else(|| PathBuf::from(".")).join("Hikki")
}

pub fn load_settings(app_data_dir: &Path) -> AppSettings {
    fs::read_to_string(app_data_dir.join("settings.json"))
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_else(|| AppSettings {
            vault_path: default_vault_path(),
            default_ai_provider: None,
            default_ai_model: None,
        })
}

pub fn save_settings(app_data_dir: &Path, settings: &AppSettings) -> io::Result<()> {
    fs::create_dir_all(app_data_dir)?;
    let json = serde_json::to_string_pretty(settings).expect("settings serialize");
    crate::fsx::write_atomic(&app_data_dir.join("settings.json"), json.as_bytes())
}

pub fn ensure_vault(root: &Path) -> io::Result<()> {
    fs::create_dir_all(root.join("documents"))?;
    let vault_file = root.join("vault.json");
    if !vault_file.exists() {
        fs::write(vault_file, "{}\n")?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn load_settings_defaults_when_missing() {
        let dir = tempfile::tempdir().unwrap();
        let s = load_settings(dir.path());
        assert_eq!(s.vault_path, default_vault_path());
        assert_eq!(s.default_ai_provider, None);
        assert_eq!(s.default_ai_model, None);
    }

    #[test]
    fn settings_round_trip() {
        let dir = tempfile::tempdir().unwrap();
        let s = AppSettings {
            vault_path: PathBuf::from("/tmp/custom-vault"),
            default_ai_provider: None,
            default_ai_model: None,
        };
        save_settings(dir.path(), &s).unwrap();
        assert_eq!(load_settings(dir.path()), s);
    }

    #[test]
    fn ensure_vault_creates_layout() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path().join("MyVault");
        ensure_vault(&root).unwrap();
        assert!(root.join("documents").is_dir());
        assert!(root.join("vault.json").is_file());
        // idempotent
        ensure_vault(&root).unwrap();
    }
}
