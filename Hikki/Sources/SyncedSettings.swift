import CloudKit
import Foundation
import HikkiAI
import HikkiCore

/// Settings follow the owner across their devices (Mac, iPhone, iPad): every value in Settings is mirrored between
/// UserDefaults and iCloud key-value storage by HikkiCore's `SettingsSync` — the later change wins, key by key — and
/// the AI keys go through iCloud Keychain (`Keychain`), never the key-value store. Layout a window keeps (the
/// inspector's width, the split's boundary, Home's layout, the last Settings page) stays on each device; so does the
/// app's language, which is the system's per-app setting.
@MainActor
final class SyncedSettings {
    /// Every value in Settings, by its UserDefaults key.
    static var keys: [String] {
        [
            AppearancePreference.storageKey, EditorPreferences.spellcheckKey, MenuBarPreferences.showKey,
            SpotlightPreferences.enabledKey, TrashPreferences.keepDaysKey, TransferPreferences.formatKey,
            ShortcutStore.storageKey, AIPreferences.modelKey, AIPreferences.favoritesKey, AIPreferences.reviewStyleKey,
            AIPreferences.chatRetentionKey, AIPreferences.filesKey, PublishPreferences.authorKey,
        ] + AIProvider.allCases.map(AIPreferences.baseURLKey)
    }

    /// Whether this run syncs settings at all: not a run on its own data folder (`SettingsSync.allowed`).
    static var allowed: Bool { SettingsSync.allowed(environment: ProcessInfo.processInfo.environment) }

    private let sync: SettingsSync
    private var observer: (any NSObjectProtocol)?

    /// Starts syncing (merging what iCloud has first) and applies what other devices change to what doesn't follow
    /// UserDefaults by itself; nil for a run that mustn't touch the account's settings.
    static func start(model: AppModel) -> SyncedSettings? {
        guard allowed else {
            Log.info("settings sync off for this run", category: "settings")
            return nil
        }
        return SyncedSettings(model: model)
    }

    private init(model: AppModel) {
        sync = SettingsSync(keys: Self.keys)
        observer = NotificationCenter.default.addObserver(forName: SettingsSync.changedRemotely, object: nil, queue: .main) {
            [weak model] note in
            let keys = note.userInfo?["keys"] as? [String] ?? []
            MainActor.assumeIsolated { model.map { Self.apply(keys, to: $0) } }
        }
        sync.start()
    }

    /// What another device changed, applied where reading UserDefaults again isn't enough. `@AppStorage` views
    /// (the theme, spelling, the AI model and review style, the menu bar item) follow on their own.
    private static func apply(_ keys: [String], to model: AppModel) {
        if keys.contains(ShortcutStore.storageKey) { ShortcutStore.shared.reload() }
        if keys.contains(SpotlightPreferences.enabledKey) {
            model.searchIndexer.setSpotlight(
                enabled: UserDefaults.standard.object(forKey: SpotlightPreferences.enabledKey) as? Bool ?? true)
        }
        if keys.contains(TrashPreferences.keepDaysKey) { model.purgeTrash() }
        if keys.contains(AIPreferences.chatRetentionKey), let chats = model.chats {
            let retention = AIPreferences.chatRetention
            Task.detached(priority: .utility) { chats.prune(retention) }
        }
    }

    /// Where syncing stands, for Settings: on, no iCloud account on this device, or off for this run.
    enum Status {
        case on, noAccount, off
    }

    static func status() async -> Status {
        guard allowed else { return .off }
        let account = try? await CKContainer(identifier: CloudSync.containerID).accountStatus()
        return account == .available ? .on : .noAccount
    }
}
