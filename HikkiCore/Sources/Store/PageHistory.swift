import Foundation
import Synchronization

/// One saved version of a page: `history/<page id>/<timestamp>.json` in the workspace folder, so versions sync
/// with iCloud like the pages themselves. Holds what restoring needs (title, icon, cover, body) plus the text the
/// history list and its diff show.
public struct PageVersion: Codable, Equatable, Sendable, Identifiable {
    /// Bumped when the shape changes incompatibly; readers skip newer formats instead of guessing.
    public static let currentFormat = 1

    /// Why the version was kept.
    public enum Reason: String, Codable, Sendable {
        /// The page as it was before an editing session (the first save after a quiet interval).
        case edit
        /// The page just before a version was restored over it (so the restore can be undone).
        case restore
        /// The page as it was here before a newer copy from another device replaced it.
        case sync
    }

    public var format: Int
    public var pageId: String
    public var savedAt: Date
    /// The device the version was kept on (its user-visible name), when known.
    public var device: String?
    public var reason: Reason
    public var title: String
    public var icon: String?
    public var cover: String?
    public var plainText: String
    public var wordCount: Int
    /// Tiptap JSON (body only), nil for a never-edited page.
    public var content: JSONValue?

    /// The file name's stem (the timestamp) — unique per page.
    public var id: String { PageHistoryFiles.stem(for: savedAt) }

    public init(record: DocumentRecord, savedAt: Date, device: String?, reason: Reason) throws {
        format = Self.currentFormat
        pageId = record.id
        self.savedAt = savedAt
        self.device = device
        self.reason = reason
        title = record.title
        icon = record.icon
        cover = record.cover
        plainText = record.plainText
        wordCount = record.wordCount
        content = try record.contentValue()
    }

    /// Whether the version holds the same page body and title as `record` (nothing to keep, nothing to restore).
    public func matches(_ record: DocumentRecord) -> Bool {
        title == record.title && content == (try? record.contentValue())
    }
}

/// When versions are kept and how long. Notion-like: one version per editing session, a session being edits with
/// no gap of `interval`; everything from the last `keepAllFor` stays, older versions thin out to the newest of each
/// day, and nothing older than `keepDays` days is kept.
public struct PageHistoryPolicy: Sendable, Equatable {
    public var interval: TimeInterval
    public var keepAllFor: TimeInterval
    public var keepDays: Int

    public init(interval: TimeInterval = 10 * 60, keepAllFor: TimeInterval = 24 * 60 * 60, keepDays: Int = 30) {
        self.interval = interval
        self.keepAllFor = keepAllFor
        self.keepDays = keepDays
    }

    /// Whether an edit at `now` starts a new session (the last version is older than `interval`, or there is none).
    public func startsSession(latest: Date?, now: Date) -> Bool {
        guard let latest else { return true }
        return now.timeIntervalSince(latest) >= interval
    }

    /// The versions (by date) to delete: past `keepAllFor`, all but the newest of each calendar day; past
    /// `keepDays`, all.
    public func expired(_ dates: [Date], now: Date, calendar: Calendar = .current) -> [Date] {
        let cutoff = calendar.date(byAdding: .day, value: -keepDays, to: now) ?? now
        var newestOfDay: [DateComponents: Date] = [:]
        var expired: [Date] = []
        for date in dates.sorted(by: >) {
            if now.timeIntervalSince(date) < keepAllFor { continue }
            if date < cutoff {
                expired.append(date)
                continue
            }
            let day = calendar.dateComponents([.year, .month, .day], from: date)
            if newestOfDay[day] == nil {
                newestOfDay[day] = date
            } else {
                expired.append(date)
            }
        }
        return expired
    }
}

/// Reads and writes the version files of one workspace folder (`history/<page id>/`).
public struct PageHistoryFiles: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public var directory: URL { root.appending(path: "history", directoryHint: .isDirectory) }

    public func directory(for pageID: String) throws -> URL {
        guard PageFiles.isValid(pageID) else { throw PageFiles.PageFileError.invalidID(pageID) }
        return directory.appending(path: pageID, directoryHint: .isDirectory)
    }

    /// Atomic write (temp file + rename), like page files.
    public func write(_ version: PageVersion) throws {
        let folder = try directory(for: version.pageId)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try PageFiles.encoder.encode(version).write(to: folder.appending(path: "\(version.id).json"), options: .atomic)
    }

    /// When each kept version of the page was saved, from the file names alone (iCloud placeholders included).
    public func dates(of pageID: String) throws -> [Date] {
        try names(of: pageID).compactMap { Self.date(fromStem: $0) }.sorted(by: >)
    }

    /// Every readable version of the page, newest first. Unreadable files (half-downloaded, newer format) are skipped.
    public func versions(of pageID: String) throws -> [PageVersion] {
        let folder = try directory(for: pageID)
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        var versions: [PageVersion] = []
        for url in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            let name = url.lastPathComponent
            if let stem = Self.placeholderStem(name) {
                // In iCloud, not on this device yet: ask for it; it shows up the next time the list is read.
                try? FileManager.default.startDownloadingUbiquitousItem(at: folder.appending(path: "\(stem).json"))
                continue
            }
            guard url.pathExtension == "json", let data = try? Data(contentsOf: url),
                let version = try? PageFiles.decoder.decode(PageVersion.self, from: data),
                version.format <= PageVersion.currentFormat, version.pageId == pageID
            else { continue }
            versions.append(version)
        }
        return versions.sorted { $0.savedAt > $1.savedAt }
    }

    public func delete(pageID: String, savedAt: Date) throws {
        let folder = try directory(for: pageID)
        let url = folder.appending(path: "\(Self.stem(for: savedAt)).json")
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        let placeholder = folder.appending(path: ".\(Self.stem(for: savedAt)).json.icloud")
        if FileManager.default.fileExists(atPath: placeholder.path) { try FileManager.default.removeItem(at: placeholder) }
    }

    /// The page's whole history (the page was deleted for good).
    public func deleteAll(pageID: String) throws {
        let folder = try directory(for: pageID)
        if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
    }

    private func names(of pageID: String) throws -> [String] {
        let folder = try directory(for: pageID)
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: folder.path).compactMap { name in
            if let stem = Self.placeholderStem(name) { return stem }
            return name.hasSuffix(".json") ? String(name.dropLast(".json".count)) : nil
        }
    }

    // MARK: Names

    /// `20261015T101530.123Z`: sortable, and free of the colons an ISO 8601 date has (Finder shows them as slashes).
    static func stem(for date: Date) -> String {
        stemFormat.string(from: date)
    }

    static func date(fromStem stem: String) -> Date? {
        stemFormat.date(from: stem)
    }

    static func placeholderStem(_ name: String) -> String? {
        guard name.hasPrefix("."), name.hasSuffix(".json.icloud") else { return nil }
        return String(name.dropFirst().dropLast(".json.icloud".count))
    }

    nonisolated(unsafe) private static let stemFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss.SSS'Z'"
        return formatter
    }()
}

/// Page history: keeps versions of pages as they are edited (see `PageHistoryPolicy`), lists them and prunes them.
/// Versions are only kept when the page really changed — viewing a page never adds one.
public final class PageHistory: Sendable {
    public let files: PageHistoryFiles
    public let policy: PageHistoryPolicy
    private let device: String?
    /// The newest version per page this session knows of, so a save in the middle of a session costs no file listing.
    private let latest = Mutex<[String: Date]>([:])

    public init(root: URL, policy: PageHistoryPolicy = PageHistoryPolicy(), device: String? = nil) {
        files = PageHistoryFiles(root: root)
        self.policy = policy
        self.device = device
    }

    /// Before an edit is saved: when it starts a new editing session, the page as it was (`current`, read lazily —
    /// only when a version may be kept) is kept. Nothing is kept for an empty, never-edited page or when the edit
    /// changes nothing (`newTitle`/`newContent`). Returns whether a version was written.
    @discardableResult
    public func recordBeforeEdit(
        pageID: String, newTitle: String, newContent: JSONValue?, now: Date = .now, reason: PageVersion.Reason = .edit,
        current: () throws -> DocumentRecord?
    ) throws -> Bool {
        guard policy.startsSession(latest: try latestDate(of: pageID), now: now) else { return false }
        guard let record = try current(), record.id == pageID else { return false }
        if record.content == nil && record.title.isEmpty {
            // A new page: nothing worth keeping yet, but its first session starts now.
            latest.withLock { $0[pageID] = now }
            return false
        }
        let currentContent = try record.contentValue()
        if record.title == newTitle && currentContent == newContent { return false }  // no change
        try keep(record, reason: reason, now: now)
        return true
    }

    /// Before a newer copy of the page from another device replaces it here: the page as it was is kept when that
    /// starts a session (the same interval as edits). Returns whether a version was written.
    @discardableResult
    public func recordBeforeReplace(_ record: DocumentRecord, now: Date = .now) throws -> Bool {
        guard policy.startsSession(latest: try latestDate(of: record.id), now: now) else { return false }
        if record.content == nil && record.title.isEmpty { return false }
        try keep(record, reason: .sync, now: now)
        return true
    }

    /// Keeps the page as it is now, whatever the interval (before a restore). Skipped when the newest version
    /// already holds exactly this page. Returns whether a version was written.
    @discardableResult
    public func snapshot(_ record: DocumentRecord, reason: PageVersion.Reason, now: Date = .now) throws -> Bool {
        if let newest = try files.versions(of: record.id).first, newest.matches(record) { return false }
        try keep(record, reason: reason, now: now)
        return true
    }

    /// The page's versions, newest first.
    public func versions(of pageID: String) throws -> [PageVersion] {
        try files.versions(of: pageID)
    }

    /// Deletes the versions the policy no longer keeps; returns how many went.
    @discardableResult
    public func prune(pageID: String, now: Date = .now) throws -> Int {
        let expired = policy.expired(try files.dates(of: pageID), now: now)
        for date in expired { try files.delete(pageID: pageID, savedAt: date) }
        return expired.count
    }

    /// The page is gone for good: so is its history.
    public func forget(pageID: String) throws {
        try files.deleteAll(pageID: pageID)
        latest.withLock { $0[pageID] = nil }
    }

    private func keep(_ record: DocumentRecord, reason: PageVersion.Reason, now: Date) throws {
        let version = try PageVersion(record: record, savedAt: now, device: device, reason: reason)
        try files.write(version)
        latest.withLock { $0[record.id] = max($0[record.id] ?? .distantPast, now) }
        let pruned = try prune(pageID: record.id, now: now)
        Log.info(
            "page version kept", category: "history",
            context: ["docId": record.id, "reason": reason.rawValue, "pruned": "\(pruned)"])
    }

    private func latestDate(of pageID: String) throws -> Date? {
        if let known = latest.withLock({ $0[pageID] }) { return known }
        // Versions another device kept arrive through the folder; the listing is read once per page and session.
        guard let newest = try files.dates(of: pageID).first else { return nil }
        latest.withLock { $0[pageID] = max($0[pageID] ?? .distantPast, newest) }
        return newest
    }
}
