use keyring::Entry;

use crate::error::Result;

const SERVICE: &str = "com.hikki.app.ai";

pub fn get_api_key_impl(provider: &str) -> Result<Option<String>> {
    let entry = Entry::new(SERVICE, provider)?;
    match entry.get_password() {
        Ok(key) => Ok(Some(key)),
        Err(keyring::Error::NoEntry) => Ok(None),
        Err(e) => Err(e.into()),
    }
}

pub fn set_api_key_impl(provider: &str, key: &str) -> Result<()> {
    let entry = Entry::new(SERVICE, provider)?;
    entry.set_password(key)?;
    Ok(())
}

pub fn delete_api_key_impl(provider: &str) -> Result<()> {
    let entry = Entry::new(SERVICE, provider)?;
    match entry.delete_credential() {
        Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
        Err(e) => Err(e.into()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Keychain tests use a unique provider-id-per-test (not a fixed constant)
    // so parallel `cargo test` runs never collide on the same real Keychain
    // entry, and each test cleans up its own entry when done.
    fn unique_provider(tag: &str) -> String {
        format!("test-{tag}-{}", std::process::id())
    }

    #[test]
    fn get_missing_key_returns_none() {
        let provider = unique_provider("missing");
        assert_eq!(get_api_key_impl(&provider).unwrap(), None);
    }

    #[test]
    fn set_then_get_round_trips() {
        let provider = unique_provider("roundtrip");
        set_api_key_impl(&provider, "sk-test-123").unwrap();
        assert_eq!(get_api_key_impl(&provider).unwrap(), Some("sk-test-123".to_string()));
        delete_api_key_impl(&provider).unwrap();
    }

    #[test]
    fn delete_is_idempotent() {
        let provider = unique_provider("delete-idempotent");
        set_api_key_impl(&provider, "sk-test-456").unwrap();
        delete_api_key_impl(&provider).unwrap();
        delete_api_key_impl(&provider).unwrap(); // second delete must not error
        assert_eq!(get_api_key_impl(&provider).unwrap(), None);
    }
}
