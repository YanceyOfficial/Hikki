import Foundation
import Testing

@testable import HikkiCore

/// iCloud key-value storage stand-in: what was set, and how often it was told to synchronize.
private final class FakeCloud: SettingsCloudStore {
    var values: [String: Any] = [:]
    var synchronized = 0

    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
    func synchronize() -> Bool {
        synchronized += 1
        return true
    }

    func entry(_ key: String) -> SettingsEntry? { SettingsEntry(cloud: values[SettingsSync.cloudPrefix + key]) }
}

private func freshDefaults() -> UserDefaults {
    let name = "settings-sync-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

struct SettingsValueTests {
    @Test func readsThePropertyListTypesSettingsUse() {
        #expect(SettingsValue(plist: true) == .bool(true))
        #expect(SettingsValue(plist: 30) == .int(30))
        #expect(SettingsValue(plist: 0.5) == .double(0.5))
        #expect(SettingsValue(plist: "dark") == .string("dark"))
        #expect(SettingsValue(plist: Data([1, 2])) == .data(Data([1, 2])))
        #expect(SettingsValue(plist: ["a", "b"]) == .strings(["a", "b"]))
        #expect(SettingsValue(plist: Date.now) == nil)
    }

    @Test func aBoolStaysABoolThroughUserDefaults() {
        let defaults = freshDefaults()
        defaults.set(true, forKey: "flag")
        defaults.set(1, forKey: "count")
        #expect(SettingsValue(plist: defaults.object(forKey: "flag")!) == .bool(true))
        #expect(SettingsValue(plist: defaults.object(forKey: "count")!) == .int(1))
    }

    @Test func anEntryRoundTripsThroughItsCloudForm() {
        let entry = SettingsEntry(value: .string("dark"), changedAt: Date(timeIntervalSince1970: 100))
        #expect(SettingsEntry(cloud: entry.cloudObject) == entry)
        // A reset (back to the default) travels as an entry without a value.
        let reset = SettingsEntry(value: nil, changedAt: Date(timeIntervalSince1970: 200))
        #expect(SettingsEntry(cloud: reset.cloudObject) == reset)
        #expect(SettingsEntry(cloud: "dark") == nil)
        #expect(SettingsEntry(cloud: nil) == nil)
        #expect(SettingsEntry(cloud: ["at": 1.0, "value": Date.now] as [String: Any]) == nil)
    }
}

struct SettingsMergeTests {
    private let old = Date(timeIntervalSince1970: 100)
    private let new = Date(timeIntervalSince1970: 200)

    @Test func theLaterChangeWins() {
        let local = SettingsEntry(value: .string("light"), changedAt: old)
        let cloud = SettingsEntry(value: .string("dark"), changedAt: new)
        #expect(SettingsMerge.resolve(local: local, cloud: cloud) == .takeCloud(cloud))
        #expect(SettingsMerge.resolve(local: cloud, cloud: local) == .sendLocal)
    }

    @Test func nothingInICloudSendsWhatIsSetHere() {
        #expect(SettingsMerge.resolve(local: SettingsEntry(value: .bool(false), changedAt: old), cloud: nil) == .sendLocal)
        #expect(SettingsMerge.resolve(local: SettingsEntry(value: nil, changedAt: old), cloud: nil) == .keep)
    }

    @Test func aTieGoesToICloudSoDevicesAgree() {
        let local = SettingsEntry(value: .int(7), changedAt: SettingsEntry.unknownAge)
        let cloud = SettingsEntry(value: .int(90), changedAt: SettingsEntry.unknownAge)
        #expect(SettingsMerge.resolve(local: local, cloud: cloud) == .takeCloud(cloud))
        #expect(SettingsMerge.resolve(local: cloud, cloud: cloud) == .keep)
    }

    @Test func aResetIsAChangeLikeAnyOther() {
        let local = SettingsEntry(value: .data(Data([1])), changedAt: old)
        let reset = SettingsEntry(value: nil, changedAt: new)
        #expect(SettingsMerge.resolve(local: local, cloud: reset) == .takeCloud(reset))
    }

    @Test func notingStampsChangesAndGivesUnseenKeysNoAge() {
        let state = ["a": SettingsEntry(value: .bool(true), changedAt: old)]
        let (next, changed) = SettingsMerge.noting(
            current: ["a": .bool(false), "b": .string("x"), "c": nil], in: state, now: new)
        #expect(changed == ["a"])
        #expect(next["a"] == SettingsEntry(value: .bool(false), changedAt: new))
        #expect(next["b"] == SettingsEntry(value: .string("x"), changedAt: SettingsEntry.unknownAge))
        #expect(next["c"] == SettingsEntry(value: nil, changedAt: SettingsEntry.unknownAge))
        // Unchanged: nothing to note.
        let again = SettingsMerge.noting(current: ["a": .bool(false)], in: next, now: .now)
        #expect(again.changed.isEmpty)
        #expect(again.state == next)
    }

    @Test func onlyRunsOnTheirOwnDataFolderAskToSync() {
        #expect(SettingsSync.allowed(environment: [:]))
        #expect(!SettingsSync.allowed(environment: ["HIKKI_DATA_DIR": "/tmp/x"]))
        #expect(SettingsSync.allowed(environment: ["HIKKI_DATA_DIR": "/tmp/x", "HIKKI_SETTINGS_SYNC": "1"]))
    }
}

@MainActor
struct SettingsSyncTests {
    private let keys = ["appearance", "trash.keepDays", "shortcutOverrides"]

    private func sync(_ defaults: UserDefaults, _ cloud: FakeCloud) -> SettingsSync {
        SettingsSync(keys: keys, defaults: defaults, cloud: cloud, center: NotificationCenter())
    }

    @Test func aNewDeviceTakesTheSettingsInICloud() {
        let cloud = FakeCloud()
        cloud.values["settings.appearance"] = SettingsEntry(value: .string("dark"), changedAt: .now).cloudObject
        let defaults = freshDefaults()
        sync(defaults, cloud).mergeAll()
        #expect(defaults.string(forKey: "appearance") == "dark")
    }

    @Test func valuesFromBeforeSyncingGoUpWhenICloudHasNone() {
        let cloud = FakeCloud()
        let defaults = freshDefaults()
        defaults.set(7, forKey: "trash.keepDays")
        sync(defaults, cloud).mergeAll()
        #expect(cloud.entry("trash.keepDays") == SettingsEntry(value: .int(7), changedAt: SettingsEntry.unknownAge))
        #expect(cloud.values["settings.appearance"] == nil)
    }

    @Test func twoDevicesFromBeforeSyncingEndUpAgreeing() {
        let cloud = FakeCloud()
        let mac = freshDefaults()
        mac.set("dark", forKey: "appearance")
        sync(mac, cloud).mergeAll()
        let phone = freshDefaults()
        phone.set("light", forKey: "appearance")
        sync(phone, cloud).mergeAll()
        #expect(phone.string(forKey: "appearance") == "dark")
    }

    @Test func aChangeHereGoesUpAndAChangeThereComesDown() {
        let cloud = FakeCloud()
        let mac = freshDefaults()
        let phone = freshDefaults()
        let macSync = sync(mac, cloud)
        let phoneSync = sync(phone, cloud)
        macSync.mergeAll()
        phoneSync.mergeAll()

        mac.set(90, forKey: "trash.keepDays")
        macSync.localChanged()
        #expect(cloud.entry("trash.keepDays")?.value == .int(90))

        let received = NotificationRecorder()
        let center = NotificationCenter()
        let observed = SettingsSync(keys: keys, defaults: phone, cloud: cloud, center: center)
        let token = center.addObserver(forName: SettingsSync.changedRemotely, object: nil, queue: nil) { note in
            received.keys = note.userInfo?["keys"] as? [String] ?? []
        }
        defer { center.removeObserver(token) }
        observed.cloudChanged(reason: NSUbiquitousKeyValueStoreServerChange, keys: ["settings.trash.keepDays"])
        #expect(phone.integer(forKey: "trash.keepDays") == 90)
        #expect(received.keys == ["trash.keepDays"])

        // What came down isn't a change here: nothing goes back up.
        let before = cloud.synchronized
        observed.localChanged()
        #expect(cloud.synchronized == before)
    }

    @Test func aResetThereRemovesTheValueHere() {
        let cloud = FakeCloud()
        let defaults = freshDefaults()
        defaults.set(Data([1, 2]), forKey: "shortcutOverrides")
        let settings = sync(defaults, cloud)
        settings.mergeAll()
        cloud.values["settings.shortcutOverrides"] = SettingsEntry(value: nil, changedAt: .now.addingTimeInterval(60)).cloudObject
        settings.cloudChanged(reason: NSUbiquitousKeyValueStoreServerChange, keys: ["settings.shortcutOverrides"])
        #expect(defaults.object(forKey: "shortcutOverrides") == nil)
    }

    @Test func anOlderValueArrivingLateSendsOursBack() {
        let cloud = FakeCloud()
        let defaults = freshDefaults()
        let settings = sync(defaults, cloud)
        settings.mergeAll()
        defaults.set("dark", forKey: "appearance")
        settings.localChanged()
        cloud.values["settings.appearance"] = SettingsEntry(value: .string("light"), changedAt: Date(timeIntervalSince1970: 100)).cloudObject
        settings.cloudChanged(reason: NSUbiquitousKeyValueStoreServerChange, keys: ["settings.appearance"])
        #expect(defaults.string(forKey: "appearance") == "dark")
        #expect(cloud.entry("appearance")?.value == .string("dark"))
    }

    @Test func quotaAndAccountChangesKeepWhatIsHere() {
        let cloud = FakeCloud()
        let defaults = freshDefaults()
        defaults.set("dark", forKey: "appearance")
        let settings = sync(defaults, cloud)
        settings.mergeAll()
        cloud.values["settings.appearance"] = SettingsEntry(value: .string("light"), changedAt: .now.addingTimeInterval(60)).cloudObject
        settings.cloudChanged(reason: NSUbiquitousKeyValueStoreQuotaViolationChange, keys: ["settings.appearance"])
        settings.cloudChanged(reason: NSUbiquitousKeyValueStoreAccountChange, keys: ["settings.appearance"])
        #expect(defaults.string(forKey: "appearance") == "dark")
    }

    @Test func keysOffTheListAreNeverSynced() {
        let cloud = FakeCloud()
        let defaults = freshDefaults()
        defaults.set(320.0, forKey: "inspector.width")
        let settings = sync(defaults, cloud)
        settings.mergeAll()
        cloud.values["settings.inspector.width"] = SettingsEntry(value: .double(500), changedAt: .now).cloudObject
        settings.cloudChanged(reason: NSUbiquitousKeyValueStoreServerChange, keys: ["settings.inspector.width"])
        #expect(defaults.double(forKey: "inspector.width") == 320)
        // Nothing of this device's went up either: only what the test put there.
        #expect(cloud.values.count == 1)
    }

    @Test func theStateOutlivesARelaunch() {
        let cloud = FakeCloud()
        let defaults = freshDefaults()
        sync(defaults, cloud).mergeAll()
        defaults.set("dark", forKey: "appearance")
        // The app quit before the change was seen: the next launch notices it and sends it as a change made now.
        let relaunched = sync(defaults, cloud)
        relaunched.mergeAll()
        let entry = cloud.entry("appearance")
        #expect(entry?.value == .string("dark"))
        #expect((entry?.changedAt ?? SettingsEntry.unknownAge) > SettingsEntry.unknownAge)
    }
}

private final class NotificationRecorder: @unchecked Sendable {
    var keys: [String] = []
}
