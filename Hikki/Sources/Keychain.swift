import Foundation
import HikkiCore
import Security

/// A generic password in iCloud Keychain (the AI providers' API keys): synchronizable items, so a key typed on one
/// device reaches the owner's others — end-to-end encrypted, never in the key-value store with the other settings.
/// Synchronizable items live in the data protection keychain (on the Mac too, `kSecUseDataProtectionKeychain`) under
/// the app's default access group (team + bundle id, the same on every platform of the universal purchase).
/// Keys from before were device-only items — on the Mac in the file-based keychain — and move over once
/// (`migrateToSynchronizable`); until they have, reads still find them.
nonisolated enum Keychain {
    private static let service = "app.yancey.hikki"
    /// The device-only keys have moved into iCloud Keychain (set once nothing is left to move).
    static let migratedKey = "keychain.synchronizable"

    /// A Keychain call that failed, with its `OSStatus` (never the value).
    nonisolated struct Failure: Error, CustomStringConvertible {
        let status: OSStatus
        var description: String { "keychain status \(status)" }
    }

    /// The query for the synced item of `account`.
    private static func synced(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account, kSecAttrSynchronizable as String: kCFBooleanTrue as Any,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    /// The query for a device-only item from before (no synchronizable attribute matches only those; on the Mac,
    /// without the data protection flag, the file-based keychain they were written to).
    private static func deviceOnly(_ account: String?) -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        if let account { query[kSecAttrAccount as String] = account }
        return query
    }

    static func read(_ account: String) -> String? {
        value(synced(account)) ?? value(deviceOnly(account))
    }

    private static func value(_ query: [String: Any]) -> String? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Stores `value` in iCloud Keychain, or removes the item (synced and device-only) when it's empty. Updates the
    /// item in place, so a failed write never takes the key that was there with it. Throws `Failure`.
    static func write(_ value: String, for account: String) throws {
        guard !value.isEmpty else {
            for query in [synced(account), deviceOnly(account)] {
                let status = SecItemDelete(query as CFDictionary)
                guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
            }
            return
        }
        try store(Data(value.utf8), synced(account))
        // The device-only item from before, if any, would only shadow nothing now: it goes.
        SecItemDelete(deviceOnly(account) as CFDictionary)
    }

    private static func store(_ data: Data, _ query: [String: Any]) throws {
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw Failure(status: status) }
    }

    /// Moves every device-only key into iCloud Keychain: read the old item, write the synced one, and only once that
    /// worked delete the old — a key is never lost to a failed write (it stays where it was and moves next launch).
    /// Runs until nothing is left to move, then never again.
    static func migrateToSynchronizable(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: migratedKey) else { return }
        var query = deviceOnly(nil)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        var items: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &items)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            Log.warn("keychain migration couldn't list keys", category: "keychain", context: ["status": "\(status)"])
            return
        }
        let accounts = (items as? [[String: Any]] ?? []).compactMap { $0[kSecAttrAccount as String] as? String }
        var left = 0
        for account in accounts {
            guard let old = value(deviceOnly(account)) else { continue }
            do {
                // A key already typed on another device wins over this one's old copy.
                if value(synced(account)) == nil { try store(Data(old.utf8), synced(account)) }
                SecItemDelete(deviceOnly(account) as CFDictionary)
            } catch {
                left += 1
                Log.warn("keychain migration kept a key on this device: \(error)", category: "keychain")
            }
        }
        Log.info("keychain migrated", category: "keychain", context: ["moved": "\(accounts.count - left)", "left": "\(left)"])
        if left == 0 { defaults.set(true, forKey: migratedKey) }
    }
}
