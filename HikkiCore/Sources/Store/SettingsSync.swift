import Foundation

/// A setting's value as UserDefaults and iCloud key-value storage hold it: the property-list types settings use.
public enum SettingsValue: Equatable, Sendable, Codable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case data(Data)
    case strings([String])

    /// Reads a property-list value; nil for a type no setting uses. A Bool stays a Bool (UserDefaults keeps it as
    /// a CFBoolean), so `true` and `1` are told apart.
    public init?(plist: Any) {
        if let string = plist as? String {
            self = .string(string)
        } else if let data = plist as? Data {
            self = .data(data)
        } else if let strings = plist as? [String] {
            self = .strings(strings)
        } else if let number = plist as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else if CFNumberIsFloatType(number as CFNumber) {
                self = .double(number.doubleValue)
            } else {
                self = .int(number.intValue)
            }
        } else {
            return nil
        }
    }

    /// The value as UserDefaults and the key-value store take it.
    public var plist: Any {
        switch self {
        case .bool(let value): return value
        case .int(let value): return value
        case .double(let value): return value
        case .string(let value): return value
        case .data(let value): return value
        case .strings(let value): return value
        }
    }
}

/// One setting as last agreed: its value (nil: not set, the app's default) and when it was changed — on this
/// device or another. Kept per key on each device and, beside the value, in iCloud.
public struct SettingsEntry: Equatable, Sendable, Codable {
    public var value: SettingsValue?
    public var changedAt: Date

    public init(value: SettingsValue?, changedAt: Date) {
        self.value = value
        self.changedAt = changedAt
    }

    /// When a value nobody watched being set was set: values from before settings synced, and keys new to the list.
    /// The oldest time there is, so any change someone made wins over them.
    public static let unknownAge = Date(timeIntervalSince1970: 0)

    /// In iCloud key-value storage: `{at, value}`, or `{at}` for a setting put back to its default — so a reset
    /// reaches the other devices too.
    public var cloudObject: [String: Any] {
        var object: [String: Any] = ["at": changedAt.timeIntervalSince1970]
        if let value { object["value"] = value.plist }
        return object
    }

    /// Reads what `cloudObject` wrote; nil for anything else (missing, or not ours).
    public init?(cloud: Any?) {
        guard let object = cloud as? [String: Any], let at = object["at"] as? Double else { return nil }
        let raw = object["value"]
        let value = raw.flatMap(SettingsValue.init(plist:))
        if raw != nil, value == nil { return nil }
        self.init(value: value, changedAt: Date(timeIntervalSince1970: at))
    }
}

/// How the settings on this device and the ones in iCloud are reconciled, key by key: the later change wins.
public enum SettingsMerge {
    public enum Outcome: Equatable, Sendable {
        /// Nothing to do.
        case keep
        /// iCloud's is newer (or as old and different): it replaces this device's.
        case takeCloud(SettingsEntry)
        /// This device's is newer, or iCloud has none: it goes up.
        case sendLocal
    }

    /// The later change wins. A tie with different values goes to iCloud's — whichever device sent first — so two
    /// devices that both had values from before syncing (both `unknownAge`) end up agreeing instead of each keeping
    /// its own.
    public static func resolve(local: SettingsEntry, cloud: SettingsEntry?) -> Outcome {
        guard let cloud else { return local.value == nil ? .keep : .sendLocal }
        if cloud.changedAt > local.changedAt { return .takeCloud(cloud) }
        if cloud.changedAt == local.changedAt { return cloud.value == local.value ? .keep : .takeCloud(cloud) }
        return cloud.value == local.value ? .keep : .sendLocal
    }

    /// The state after looking at what this device holds now: a key whose value is no longer the one last agreed
    /// was changed here, at `now`; a key never seen before gets `unknownAge`. Returns the keys changed here.
    public static func noting(
        current: [String: SettingsValue?], in state: [String: SettingsEntry], now: Date
    ) -> (state: [String: SettingsEntry], changed: [String]) {
        var next = state
        var changed: [String] = []
        for key in current.keys.sorted() {
            let value = current[key] ?? nil
            if let known = state[key] {
                guard known.value != value else { continue }
                next[key] = SettingsEntry(value: value, changedAt: now)
                changed.append(key)
            } else {
                next[key] = SettingsEntry(value: value, changedAt: SettingsEntry.unknownAge)
            }
        }
        return (next, changed)
    }
}

/// Where synced settings go: iCloud key-value storage (`NSUbiquitousKeyValueStore`), or a fake in tests.
public protocol SettingsCloudStore: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: SettingsCloudStore {}

/// Settings follow the owner across their devices: a fixed list of UserDefaults keys mirrored into iCloud
/// key-value storage, so `@AppStorage` keeps reading and writing UserDefaults as before. At start what is in iCloud
/// and what is here are merged key by key (`SettingsMerge`: the later change wins, by a time kept beside each value
/// — the key-value store keeps no time of its own, and its "last write wins" only holds between devices online
/// together); from then on a change here goes up (`UserDefaults.didChangeNotification`) and one from another device
/// comes down (`didChangeExternallyNotification`) and is posted as `changedRemotely` for what doesn't observe
/// UserDefaults itself. Never secrets: the key-value store isn't end-to-end encrypted (AI keys go through iCloud
/// Keychain instead).
@MainActor
public final class SettingsSync {
    /// Settings another device changed were written here; `userInfo["keys"]` is `[String]`.
    public nonisolated static let changedRemotely = Notification.Name("app.yancey.hikki.settingsChangedRemotely")
    /// Each setting's key in iCloud: the UserDefaults key under this prefix.
    public nonisolated static let cloudPrefix = "settings."
    /// This device's state (`[key: SettingsEntry]` as JSON): the values last agreed and when each changed.
    public nonisolated static let stateKey = "settingsSync.state"

    public let keys: [String]
    private let defaults: UserDefaults
    private let cloud: any SettingsCloudStore
    private let center: NotificationCenter
    private var state: [String: SettingsEntry]
    /// Set while values from iCloud are written here, so their own change notifications send nothing back.
    private var applying = false
    private var observers: [any NSObjectProtocol] = []

    public init(
        keys: [String], defaults: UserDefaults = .standard, cloud: any SettingsCloudStore = NSUbiquitousKeyValueStore.default,
        center: NotificationCenter = .default
    ) {
        self.keys = keys
        self.defaults = defaults
        self.cloud = cloud
        self.center = center
        state = defaults.data(forKey: Self.stateKey).flatMap { try? JSONDecoder().decode([String: SettingsEntry].self, from: $0) } ?? [:]
        savedState = state
    }

    /// Whether this run may read and write the account's settings. Not a run on a data folder of its own
    /// (`HIKKI_DATA_DIR`: UI tests, demos) — their settings would land on the owner's devices — unless
    /// `HIKKI_SETTINGS_SYNC=1`.
    public nonisolated static func allowed(environment: [String: String]) -> Bool {
        guard let dir = environment["HIKKI_DATA_DIR"], !dir.isEmpty else { return true }
        return environment["HIKKI_SETTINGS_SYNC"] == "1"
    }

    /// Merges once, then follows both sides.
    public func start() {
        _ = cloud.synchronize()
        mergeAll()
        observers = [
            center.addObserver(forName: UserDefaults.didChangeNotification, object: defaults, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.localChanged() }
            },
            center.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud, queue: .main) {
                [weak self] note in
                let reason = note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
                let keys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
                MainActor.assumeIsolated { self?.cloudChanged(reason: reason, keys: keys) }
            },
        ]
    }

    /// Every key: iCloud's where it is newer, this device's sent where it is.
    func mergeAll() {
        noteLocalValues()
        var sent: [String] = []
        var taken: [String] = []
        for key in keys {
            let local = state[key] ?? SettingsEntry(value: nil, changedAt: SettingsEntry.unknownAge)
            switch SettingsMerge.resolve(local: local, cloud: SettingsEntry(cloud: cloud.object(forKey: Self.cloudPrefix + key))) {
            case .keep: break
            case .takeCloud(let entry):
                if take(entry, for: key, over: local) { taken.append(key) }
            case .sendLocal:
                cloud.set(local.cloudObject, forKey: Self.cloudPrefix + key)
                sent.append(key)
            }
        }
        saveState()
        if !sent.isEmpty { _ = cloud.synchronize() }
        Log.info("settings merged", category: "settings", context: ["sent": "\(sent.count)", "taken": "\(taken.count)"])
        announce(taken)
    }

    /// Something in UserDefaults changed: the synced keys that did go up.
    func localChanged() {
        guard !applying else { return }
        let changed = noteLocalValues()
        guard !changed.isEmpty else { return }
        for key in changed {
            if let entry = state[key] { cloud.set(entry.cloudObject, forKey: Self.cloudPrefix + key) }
        }
        _ = cloud.synchronize()
        Log.info("settings sent", category: "settings", context: ["keys": changed.joined(separator: ",")])
    }

    /// Another device's changes arrived (or iCloud said why it couldn't take ours).
    func cloudChanged(reason: Int?, keys changedKeys: [String]) {
        if reason == NSUbiquitousKeyValueStoreQuotaViolationChange {
            Log.warn("settings over the iCloud quota: kept on this device", category: "settings")
            return
        }
        if reason == NSUbiquitousKeyValueStoreAccountChange {
            // Another iCloud account: what it holds isn't this device's owner's — nothing here is replaced by it.
            Log.info("iCloud account changed: settings kept on this device", category: "settings")
            return
        }
        noteLocalValues()
        var taken: [String] = []
        var sent = false
        for cloudKey in changedKeys where cloudKey.hasPrefix(Self.cloudPrefix) {
            let key = String(cloudKey.dropFirst(Self.cloudPrefix.count))
            guard keys.contains(key) else { continue }
            let local = state[key] ?? SettingsEntry(value: nil, changedAt: SettingsEntry.unknownAge)
            switch SettingsMerge.resolve(local: local, cloud: SettingsEntry(cloud: cloud.object(forKey: cloudKey))) {
            case .keep: break
            case .takeCloud(let entry):
                if take(entry, for: key, over: local) { taken.append(key) }
            case .sendLocal:
                // An older value arrived after ours (a device that was offline): ours goes back up.
                cloud.set(local.cloudObject, forKey: cloudKey)
                sent = true
            }
        }
        saveState()
        if sent { _ = cloud.synchronize() }
        if !taken.isEmpty { Log.info("settings received", category: "settings", context: ["keys": taken.joined(separator: ",")]) }
        announce(taken)
    }

    // MARK: Private

    /// Reads the synced keys from UserDefaults into the state; the keys changed here since it was last agreed.
    @discardableResult
    private func noteLocalValues() -> [String] {
        var current: [String: SettingsValue?] = [:]
        for key in keys { current[key] = .some(defaults.object(forKey: key).flatMap(SettingsValue.init(plist:))) }
        let (next, changed) = SettingsMerge.noting(current: current, in: state, now: .now)
        guard next != state else { return [] }
        state = next
        saveState()
        return changed
    }

    /// Writes iCloud's value here; whether the value itself changed (not only its time).
    private func take(_ entry: SettingsEntry, for key: String, over local: SettingsEntry) -> Bool {
        state[key] = entry
        guard entry.value != local.value else { return false }
        applying = true
        defer { applying = false }
        if let value = entry.value {
            defaults.set(value.plist, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
        return true
    }

    private var savedState: [String: SettingsEntry]?

    private func saveState() {
        guard savedState != state else { return }
        guard let data = try? JSONEncoder().encode(state) else { return }
        savedState = state
        applying = true
        defer { applying = false }
        defaults.set(data, forKey: Self.stateKey)
    }

    private func announce(_ keys: [String]) {
        guard !keys.isEmpty else { return }
        center.post(name: Self.changedRemotely, object: self, userInfo: ["keys": keys])
    }
}
