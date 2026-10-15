import Foundation

/// A comment thread on a passage of a page. The passage itself is marked in the page's content (the editor's
/// `comment` mark carries the thread's id), so the anchor moves with edits; the thread's words live here.
public struct CommentThread: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    /// The passage's text when the thread started (shown with the thread; the mark may since have changed).
    public var quote: String
    public var createdAt: Date
    /// The last change to the thread (a comment, resolving, deleting) — what merging compares.
    public var updatedAt: Date
    public var resolvedAt: Date?
    /// Deleted threads stay as tombstones, so a device that still has them doesn't bring them back.
    public var deletedAt: Date?
    public var comments: [PageComment]

    public init(
        id: String, quote: String, createdAt: Date, updatedAt: Date, resolvedAt: Date? = nil, deletedAt: Date? = nil,
        comments: [PageComment]
    ) {
        self.id = id
        self.quote = quote
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.resolvedAt = resolvedAt
        self.deletedAt = deletedAt
        self.comments = comments
    }

    /// The comments still there, oldest first.
    public var visibleComments: [PageComment] { comments.filter { $0.deletedAt == nil }.sorted { $0.createdAt < $1.createdAt } }
}

public struct PageComment: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var body: String
    /// Who wrote it (the user's name where the system knows it) and on which device.
    public var author: String?
    public var device: String?
    public var createdAt: Date
    /// The last edit of `body` (nil: as written) — merging keeps the newer edit.
    public var editedAt: Date?
    public var deletedAt: Date?

    /// The words for plain display: a page mention (`[@Title](hikki://page/<id>)`, as the editor stores it) reads
    /// "@Title".
    public var plainBody: String {
        body.replacingOccurrences(
            of: #"\[@([^\]\n]*)\]\(hikki://page/[\w-]+\)"#, with: "@$1", options: .regularExpression)
    }

    public init(
        id: String, body: String, author: String?, device: String?, createdAt: Date, editedAt: Date? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.body = body
        self.author = author
        self.device = device
        self.createdAt = createdAt
        self.editedAt = editedAt
        self.deletedAt = deletedAt
    }
}

/// A page's comment threads on disk: `comments/<page id>.json` in the workspace folder, so they sync with the pages.
/// Every change reads the file, applies itself and writes the result atomically; two devices writing at once (iCloud
/// keeps both versions) are merged — threads and comments joined by id, the newer state of each winning, deletions
/// kept — never one overwriting the other.
public final class PageComments: @unchecked Sendable {
    public static let currentFormat = 1
    /// Longest comment kept (characters).
    public static let maxBody = 10_000

    struct File: Codable {
        var format: Int
        var pageId: String
        var threads: [CommentThread]
    }

    public enum Failure: Error, Equatable {
        case newerFormat
        case emptyComment
        case unknownThread
    }

    private let folder: URL
    private let author: String?
    private let device: String?
    private let lock = NSLock()

    public init(root: URL, author: String?, device: String?) {
        folder = root.appending(path: "comments", directoryHint: .isDirectory)
        self.author = author
        self.device = device
    }

    /// The page's comments file; the id comes from the editor, so one that could leave the folder ("../pages/x")
    /// is refused, as page files refuse it.
    func url(for pageId: String) throws -> URL {
        guard PageFiles.isValid(pageId) else { throw PageFiles.PageFileError.invalidID(pageId) }
        return folder.appending(path: "\(pageId).json")
    }

    /// The page's threads still there (not deleted), oldest first, each with its remaining comments.
    public func threads(of pageId: String) throws -> [CommentThread] {
        try lock.withLock { try read(pageId) }
            .filter { $0.deletedAt == nil }
            .map { thread in
                var shown = thread
                shown.comments = thread.visibleComments
                return shown
            }
            .filter { !$0.comments.isEmpty }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Starts a thread on a passage with its first comment.
    public func create(pageId: String, threadId: String, quote: String, body: String, now: Date = .now) throws {
        let text = try Self.clean(body)
        try change(pageId) { threads in
            guard !threads.contains(where: { $0.id == threadId }) else { return }
            threads.append(
                CommentThread(
                    id: threadId, quote: String(quote.prefix(500)), createdAt: now, updatedAt: now,
                    comments: [self.comment(text, now)]))
        }
    }

    public func reply(pageId: String, threadId: String, body: String, now: Date = .now) throws {
        let text = try Self.clean(body)
        try change(pageId) { threads in
            guard let index = threads.firstIndex(where: { $0.id == threadId && $0.deletedAt == nil }) else {
                throw Failure.unknownThread
            }
            threads[index].comments.append(self.comment(text, now))
            threads[index].updatedAt = now
        }
    }

    /// Rewrites a comment (its own words; who wrote it and when stay).
    public func edit(pageId: String, threadId: String, commentId: String, body: String, now: Date = .now) throws {
        let text = try Self.clean(body)
        try change(pageId) { threads in
            guard let index = threads.firstIndex(where: { $0.id == threadId && $0.deletedAt == nil }),
                let comment = threads[index].comments.firstIndex(where: { $0.id == commentId && $0.deletedAt == nil })
            else { throw Failure.unknownThread }
            threads[index].comments[comment].body = text
            threads[index].comments[comment].editedAt = now
            threads[index].updatedAt = now
        }
    }

    public func setResolved(_ resolved: Bool, pageId: String, threadId: String, now: Date = .now) throws {
        try change(pageId) { threads in
            guard let index = threads.firstIndex(where: { $0.id == threadId }) else { throw Failure.unknownThread }
            threads[index].resolvedAt = resolved ? now : nil
            threads[index].updatedAt = now
        }
    }

    /// Deletes a comment, or the whole thread (`commentId` nil) — a thread whose last comment goes goes with it.
    public func delete(pageId: String, threadId: String, commentId: String? = nil, now: Date = .now) throws {
        try change(pageId) { threads in
            guard let index = threads.firstIndex(where: { $0.id == threadId }) else { return }
            if let commentId, let comment = threads[index].comments.firstIndex(where: { $0.id == commentId }) {
                threads[index].comments[comment].deletedAt = now
            }
            if commentId == nil || threads[index].visibleComments.isEmpty { threads[index].deletedAt = now }
            threads[index].updatedAt = now
        }
    }

    /// The page is gone for good: its comments go too.
    public func removeAll(pageId: String) {
        guard let file = try? url(for: pageId) else { return }
        lock.withLock { _ = try? FileManager.default.removeItem(at: file) }
    }

    // MARK: Reading, writing, merging

    private func comment(_ body: String, _ now: Date) -> PageComment {
        PageComment(id: UUID().uuidString.lowercased(), body: body, author: author, device: device, createdAt: now)
    }

    static func clean(_ body: String) throws -> String {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw Failure.emptyComment }
        return String(text.prefix(maxBody))
    }

    private func change(_ pageId: String, _ apply: (inout [CommentThread]) throws -> Void) throws {
        try lock.withLock {
            var threads = try read(pageId)
            try apply(&threads)
            try write(threads, pageId)
        }
    }

    /// The file's threads, with any conflicting versions iCloud kept merged in (and then let go).
    private func read(_ pageId: String) throws -> [CommentThread] {
        let file = try url(for: pageId)
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        var threads = try decode(Data(contentsOf: file))
        let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: file) ?? []
        if !conflicts.isEmpty {
            for version in conflicts {
                if let data = try? Data(contentsOf: version.url), let other = try? decode(data) {
                    threads = Self.merge(threads, other)
                }
            }
            try write(threads, pageId)
            for version in conflicts { version.isResolved = true }
            try? NSFileVersion.removeOtherVersionsOfItem(at: file)
        }
        return threads
    }

    private func decode(_ data: Data) throws -> [CommentThread] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(File.self, from: data)
        guard file.format <= Self.currentFormat else { throw Failure.newerFormat }
        return file.threads
    }

    private func write(_ threads: [CommentThread], _ pageId: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(File(format: Self.currentFormat, pageId: pageId, threads: threads))
        try data.write(to: try url(for: pageId), options: .atomic)
    }

    /// Two devices' versions as one: every thread and comment of either, by id; for a thread on both, the newer
    /// state (resolved, deleted, quote) and the union of their comments, a comment deleted on either deleted.
    static func merge(_ a: [CommentThread], _ b: [CommentThread]) -> [CommentThread] {
        var byID: [String: CommentThread] = [:]
        for thread in a + b {
            guard let existing = byID[thread.id] else {
                byID[thread.id] = thread
                continue
            }
            var merged = existing.updatedAt >= thread.updatedAt ? existing : thread
            var comments: [String: PageComment] = [:]
            for comment in existing.comments + thread.comments {
                if var known = comments[comment.id] {
                    // The newer edit's words.
                    if (comment.editedAt ?? .distantPast) > (known.editedAt ?? .distantPast) {
                        known.body = comment.body
                        known.editedAt = comment.editedAt
                    }
                    known.deletedAt = known.deletedAt ?? comment.deletedAt
                    comments[comment.id] = known
                } else {
                    comments[comment.id] = comment
                }
            }
            merged.comments = comments.values.sorted { $0.createdAt < $1.createdAt }
            merged.deletedAt = existing.deletedAt ?? thread.deletedAt
            merged.updatedAt = max(existing.updatedAt, thread.updatedAt)
            byID[thread.id] = merged
        }
        return byID.values.sorted { $0.createdAt < $1.createdAt }
    }
}
