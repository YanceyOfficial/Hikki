import Foundation
import HikkiCore
import HikkiUI
import Observation
import UserNotifications
import os

#if os(iOS)
    import UIKit
#else
    import AppKit
#endif

/// Every date in the workspace's live pages (the editor's date chips), kept current from the store — read once at
/// launch (`pagesWithDates`), then from each committed page change — for Home's Upcoming and for reminders: the ones
/// still to ring are local notifications (`ReminderCenter`), so every device that has the workspace rings, and a
/// reminder marked done on one stops on the others once the page comes over.
@Observable
final class Reminders {
    /// The workspace's dates, in no order (`Upcoming` sorts them).
    private(set) var entries: [DateEntry] = []
    @ObservationIgnored private var byPage: [String: [DateEntry]] = [:]
    /// Pages a commit has reported since launch: the launch read, arriving later, doesn't overwrite them.
    @ObservationIgnored private var reported: Set<String> = []
    @ObservationIgnored private let store: DocumentStore
    @ObservationIgnored private var scheduling: Task<Void, Never>?
    /// Reads a page's dates out of its content off the commit's thread (the commit observer runs inside the save, on
    /// the typing thread; parsing a long page's JSON there held every save). One queue, so commits apply in order.
    @ObservationIgnored private let parsing = DispatchQueue(label: "app.yancey.hikki.reminders", qos: .utility)
    /// The commit each page's entries came from, so a slower parse of an older commit never overwrites a newer one.
    @ObservationIgnored private var appliedCommit: [String: Int] = [:]
    @ObservationIgnored private let commitCount = OSAllocatedUnfairLock(initialState: 0)

    init(store: DocumentStore) {
        self.store = store
    }

    func start() {
        do {
            try store.observePageCommits { [weak self] changed, deletions, live in
                guard let self else { return }
                let commit = commitCount.withLock { count in
                    count += 1
                    return count
                }
                parsing.async {
                    let updates = changed.map { ($0.id, Self.entries(of: $0)) }
                    Task { @MainActor in
                        self.apply(updates, commit: commit, live: deletions ? live : nil, reload: deletions && live == nil)
                    }
                }
            }
        } catch {
            Log.error("reminders observation failed: \(error)", category: "reminders")
        }
        ReminderCenter.shared.start()
        load()
    }

    private func load() {
        let store = store
        Task { [weak self] in
            do {
                let pages = try await Self.read(store)
                self?.loaded(pages)
            } catch {
                Log.error("dates unreadable: \(error)", category: "reminders")
            }
        }
    }

    @concurrent private static func read(_ store: DocumentStore) async throws -> [String: [DateEntry]] {
        Dictionary(try store.pagesWithDates().map { ($0.id, entries(of: $0)) }) { first, _ in first }
    }

    private func loaded(_ pages: [String: [DateEntry]]) {
        for (id, entries) in pages where !reported.contains(id) { byPage[id] = entries }
        changed()
    }

    private func apply(_ updates: [(String, [DateEntry])], commit: Int, live: Set<String>?, reload: Bool) {
        for (id, entries) in updates where (appliedCommit[id] ?? 0) < commit {
            appliedCommit[id] = commit
            reported.insert(id)
            byPage[id] = entries.isEmpty ? nil : entries
        }
        if let live { byPage = byPage.filter { live.contains($0.key) } }
        if reload {
            reported = []
            load()
        }
        changed()
    }

    private func changed() {
        let next = byPage.values.flatMap(\.self)
        guard next != entries else { return }
        entries = next
        scheduling?.cancel()
        // Typing saves every few seconds: the notifications follow once it rests.
        scheduling = Task { [next] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await ReminderCenter.shared.schedule(next)
        }
    }

    nonisolated private static func entries(of record: DocumentRecord) -> [DateEntry] {
        guard record.deletedAt == nil, let content = record.content, content.contains("\"dateMention\""),
            let json = try? JSONValue(jsonData: Data(content.utf8))
        else { return [] }
        return DateEntry.entries(pageId: record.id, title: record.title, content: json)
    }
}

/// The reminders as local notifications, and what a notification does: its Mark done and Snooze actions change
/// the chip in its page; a tap opens the page at the chip's block. Authorization is asked for when the first
/// reminder needs scheduling. A run on its own data folder (UI tests, demos) schedules nothing unless
/// `HIKKI_REMINDERS=1`, so a test never meets the permission prompt.
nonisolated final class ReminderCenter: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = ReminderCenter()
    static let category = "hikki.reminder"
    static let prefix = "hikki.reminder."
    static let markDone = "done"
    static let snooze = "snooze"
    static let snoozeMinutes = 15

    static func schedulingAllowed(environment: [String: String]) -> Bool {
        guard let dir = environment["HIKKI_DATA_DIR"], !dir.isEmpty else { return true }
        return environment["HIKKI_REMINDERS"] == "1"
    }

    private var allowed: Bool { Self.schedulingAllowed(environment: ProcessInfo.processInfo.environment) }

    func start() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let done = UNNotificationAction(identifier: Self.markDone, title: String(localized: "app:reminder.markDone"), options: [])
        let snooze = UNNotificationAction(identifier: Self.snooze, title: String(localized: "app:reminder.snooze"), options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.category, actions: [done, snooze], intentIdentifiers: [])
        ])
    }

    /// The reminders still to ring become the app's pending notifications (at most 64, soonest first); ours that no
    /// longer match go. A notification already pending as wanted is left alone.
    func schedule(_ entries: [DateEntry]) async {
        guard allowed else { return }
        let center = UNUserNotificationCenter.current()
        let wanted = Upcoming.pending(entries.filter { $0.mention.id != nil }, now: .now, calendar: .current)
            .map { Self.request(for: $0.entry, at: $0.fire) }
        let pending = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(Self.prefix) }
        let have = Dictionary(pending.map { ($0.identifier, Self.signature(of: $0)) }) { first, _ in first }
        let keep = Set(wanted.filter { have[$0.identifier] == Self.signature(of: $0) }.map(\.identifier))
        let stale = pending.map(\.identifier).filter { !keep.contains($0) }
        if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale) }
        let add = wanted.filter { !keep.contains($0.identifier) }
        guard !add.isEmpty, await authorized(center) else { return }
        // One that the system refuses is said once per pass (the toast carries the code; every refusal is logged).
        var failed = 0
        var firstError: (any Error)?
        for request in add {
            do {
                try await center.add(request)
            } catch {
                failed += 1
                if firstError == nil { firstError = error }
                Log.warn("reminder not scheduled: \(error)", category: "reminders")
            }
        }
        if let firstError {
            Toasts.report(.reminderScheduleFailed, firstError, category: "reminders", context: ["failed": "\(failed)"])
        }
        Log.info(
            "reminders scheduled", category: "reminders",
            context: ["pending": "\(wanted.count)", "added": "\(add.count - failed)", "removed": "\(stale.count)"])
    }

    /// Whether the user has let Hikki notify. Denied, the reminders in the pages look set but would never ring: said
    /// once per run, with a way to the system's notification settings.
    private func authorized(_ center: UNUserNotificationCenter) async -> Bool {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                if !granted { await warnNotificationsOff() }
                return granted
            } catch {
                Log.warn("notification permission failed: \(error)", category: "reminders")
                return false
            }
        default:
            await warnNotificationsOff()
            return false
        }
    }

    private let warnedOff = OSAllocatedUnfairLock(initialState: false)

    @MainActor private func warnNotificationsOff() {
        let first = warnedOff.withLock { warned in
            defer { warned = true }
            return !warned
        }
        guard first else { return }
        Toasts.report(.reminderNotificationsOff, category: "reminders", actionTitle: "app:reminder.openSettings") {
            Self.openNotificationSettings()
        }
    }

    @MainActor private static func openNotificationSettings() {
        #if os(iOS)
            if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
        #else
            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
        #endif
    }

    /// The block's words as the title, the page's title under them (the system hides both on a locked screen
    /// unless the reader lets it show previews).
    static func request(for entry: DateEntry, at fire: DateComponents) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        let page = PageTitle.display(entry.pageTitle)
        content.title = entry.found.text.isEmpty ? page : entry.found.text
        content.body = entry.found.text.isEmpty ? "" : page
        content.sound = .default
        content.categoryIdentifier = category
        content.threadIdentifier = entry.pageId
        content.userInfo = ["pageId": entry.pageId, "blockId": entry.found.blockId, "mentionId": entry.mention.id ?? ""]
        let trigger = UNCalendarNotificationTrigger(dateMatching: fire, repeats: false)
        return UNNotificationRequest(identifier: prefix + entry.id, content: content, trigger: trigger)
    }

    /// What a pending notification says and when, to tell whether it is still as wanted.
    private static func signature(of request: UNNotificationRequest) -> String {
        let fire = (request.trigger as? UNCalendarNotificationTrigger)?.dateComponents
        let at = [fire?.year, fire?.month, fire?.day, fire?.hour, fire?.minute].map { "\($0 ?? -1)" }.joined(separator: "-")
        return "\(at)|\(request.content.title)|\(request.content.body)"
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let pageId = info["pageId"] as? String else { return }
        let mentionId = info["mentionId"] as? String ?? ""
        let blockId = (info["blockId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let action = response.actionIdentifier
        await MainActor.run {
            switch action {
            case Self.markDone:
                Task { await AppModel.current?.updateDate(pageId: pageId, mentionId: mentionId) { $0.markDone() } }
            case Self.snooze:
                let now = Date.now
                Task {
                    await AppModel.current?.updateDate(pageId: pageId, mentionId: mentionId) {
                        $0.snooze(minutes: Self.snoozeMinutes, now: now, calendar: .current)
                    }
                }
            case UNNotificationDefaultActionIdentifier:
                PageOpenRequests.shared.post(pageId: pageId, blockId: blockId)
            default: break
            }
        }
    }
}

/// A page to open from outside any window (a reminder's notification): the main window's ContentView opens it —
/// on the Mac the window `MenuBarRequests` brings forward.
@Observable
final class PageOpenRequests {
    struct Request: Equatable, Identifiable {
        let id = UUID()
        let pageId: String
        let blockId: String?
    }

    static let shared = PageOpenRequests()
    var pending: Request?

    func post(pageId: String, blockId: String?) {
        #if os(macOS)
            MenuBarRequests.shared.post(.openPage(pageId, blockId: blockId))
        #else
            pending = Request(pageId: pageId, blockId: blockId)
        #endif
    }
}

extension AppModel {
    /// A reminder's Mark done / Snooze from its notification: the chip `mentionId` names in the page, changed here —
    /// every editor hands over its unsaved edits first, and one showing the page reloads it. Nothing happens when the
    /// page or the chip is gone; a locked page refuses (said in a toast).
    func updateDate(pageId: String, mentionId: String, _ change: @escaping (inout DateMention) -> Void) async {
        await EditorController.flushAll(reason: "reminder")
        do {
            guard let record = try store.document(id: pageId), record.deletedAt == nil, let json = record.content,
                let next = DateMentions.updating(try JSONValue(jsonData: Data(json.utf8)), id: mentionId, change)
            else { return }
            guard !record.isLocked else { throw ReminderError.locked }
            _ = try store.saveContent(
                Snapshot(
                    docId: record.id, content: next, title: record.title, text: record.plainText,
                    wordCount: record.wordCount))
            Log.info("reminder updated", category: "reminders", context: ["docId": record.id])
            NotificationCenter.default.post(name: .pageSavedInEditor, object: nil, userInfo: ["id": record.id])
        } catch {
            Toasts.report(.reminderUpdateFailed, error, category: "reminders", context: ["docId": pageId])
        }
    }

    nonisolated enum ReminderError: Error {
        case locked
    }
}
