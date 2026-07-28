use serde::Serialize;

#[derive(Debug, thiserror::Error)]
pub enum AppError {
    #[error("io error: {0}")]
    Io(#[from] std::io::Error),
    #[error("invalid json: {0}")]
    Json(#[from] serde_json::Error),
    #[error("document not found: {0}")]
    NotFound(String),
    #[error("index error: {0}")]
    Index(#[from] rusqlite::Error),
    #[error("keychain error: {0}")]
    Keychain(#[from] keyring::Error),
}

impl AppError {
    pub fn code(&self) -> &'static str {
        match self {
            AppError::Io(_) => "HK-1001",
            AppError::Json(_) => "HK-1002",
            AppError::NotFound(_) => "HK-1003",
            AppError::Index(_) => "HK-2001",
            AppError::Keychain(_) => "HK-3001",
        }
    }
}

#[derive(Serialize)]
struct ErrorPayload {
    code: &'static str,
    message: String,
}

impl Serialize for AppError {
    fn serialize<S: serde::Serializer>(&self, s: S) -> std::result::Result<S::Ok, S::Error> {
        ErrorPayload { code: self.code(), message: self.to_string() }.serialize(s)
    }
}

pub type Result<T> = std::result::Result<T, AppError>;
