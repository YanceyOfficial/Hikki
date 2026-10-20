import Foundation

/// One turn of a page's AI conversation as it is kept: the words, who said them and when. Files sent with a question
/// are not kept (only their names — they may be large, and they went to the model once); an answer is kept once it
/// has finished.
public struct ChatTurn: Codable, Equatable, Sendable, Identifiable {
    public enum Role: String, Codable, Sendable { case user, assistant }

    public var id: String
    public var role: Role
    public var text: String
    public var sentAt: Date
    /// Names of the files sent with a question.
    public var attachments: [String]
    public var citations: [ChatCitation]
    /// Changes an answer proposed to the page, with how each was reviewed (absent in older files).
    public var changes: [AIPageChange]?
    /// How the answer was worked out: the model's thinking and its web searches, in order (the chat's timeline).
    public var thinking: ChatThinking?
    /// Pictures the answer's web search found (absent in older files and answers without any).
    public var images: [ChatImage]?

    public init(
        id: String, role: Role, text: String, sentAt: Date, attachments: [String] = [], citations: [ChatCitation] = [],
        changes: [AIPageChange]? = nil, thinking: ChatThinking? = nil, images: [ChatImage]? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.sentAt = sentAt
        self.attachments = attachments
        self.citations = citations
        self.changes = changes
        self.thinking = thinking
        self.images = images
    }
}

/// An answer's thinking timeline: its steps, and how long the model worked before answering.
public struct ChatThinking: Codable, Equatable, Sendable {
    public struct Step: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable { case thinking, search }
        public var kind: Kind
        /// The thinking's text, or the search's query ("" while the provider hasn't said it).
        public var text: String

        public init(kind: Kind, text: String) {
            self.kind = kind
            self.text = text
        }
    }

    public var steps: [Step]
    /// Seconds from asking to the answer's first words.
    public var seconds: Double?

    public init(steps: [Step] = [], seconds: Double? = nil) {
        self.steps = steps
        self.seconds = seconds
    }
}

/// A web page an answer cites.
public struct ChatCitation: Codable, Hashable, Sendable {
    public var url: String
    public var title: String?

    /// The page's address when it is a web page (http / https) — the only links a citation may open. Kept turns come
    /// from the workspace folder, which other devices write, so this is checked where they are shown, not trusted.
    public var webURL: URL? {
        guard let url = URL(string: url), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
            url.host() != nil
        else { return nil }
        return url
    }

    public init(url: String, title: String?) {
        self.url = url
        self.title = title
    }
}

/// A picture an answer's web search found: the picture, a smaller copy to show, the page it is on, what it shows.
public struct ChatImage: Codable, Hashable, Sendable {
    public var url: String
    public var thumbnail: String?
    public var source: String?
    public var caption: String?

    public init(url: String, thumbnail: String? = nil, source: String? = nil, caption: String? = nil) {
        self.url = url
        self.thumbnail = thumbnail
        self.source = source
        self.caption = caption
    }

    /// The picture's address when it is on the web — like a citation's, checked where it is shown (kept turns come
    /// from the workspace folder).
    public var webURL: URL? { ChatCitation(url: url, title: nil).webURL }
    /// The copy to show: the thumbnail when it is on the web, else the picture.
    public var thumbnailURL: URL? { thumbnail.flatMap { ChatCitation(url: $0, title: nil).webURL } ?? webURL }
    /// The page the picture is on, when that is on the web.
    public var sourceURL: URL? { source.flatMap { ChatCitation(url: $0, title: nil).webURL } }
}

/// What a long conversation's older turns said, written by the model: sent in their place, so a conversation can go
/// on past what a request holds. The turns themselves stay on the device and on screen.
public struct ChatSummary: Codable, Equatable, Sendable {
    public var text: String
    /// The last turn it covers.
    public var through: String
    public var createdAt: Date

    public init(text: String, through: String, createdAt: Date) {
        self.text = text
        self.through = through
        self.createdAt = createdAt
    }
}

/// A page's conversation: its turns since it was last cleared, oldest first, and the summary of the older ones.
public struct ChatConversation: Equatable, Sendable {
    public var turns: [ChatTurn]
    public var summary: ChatSummary?
    /// When it was last cleared (New chat) — undoing that puts this back.
    public var clearedAt: Date?

    public init(turns: [ChatTurn] = [], summary: ChatSummary? = nil, clearedAt: Date? = nil) {
        self.turns = turns
        self.summary = summary
        self.clearedAt = clearedAt
    }
}

/// How long AI conversations are kept (Settings → AI): turns older than this go, everywhere the workspace syncs.
public enum ChatRetention: String, CaseIterable, Sendable {
    case days30, days90, forever

    public static let `default` = ChatRetention.days90

    public var days: Int? {
        switch self {
        case .days30: 30
        case .days90: 90
        case .forever: nil
        }
    }

    /// Turns sent before this are dropped (nil: none are).
    public func cutoff(now: Date = .now) -> Date? {
        days.map { now.addingTimeInterval(-Double($0) * 86_400) }
    }
}

/// Each page's AI conversation on disk: `ai/<page id>.json` in the workspace folder, so it syncs with the page — one
/// conversation per page, no list of old ones. Changes read the file, apply themselves and write it atomically; two
/// devices' versions (iCloud keeps both) are merged — turns joined by id, the later clearing and the newer summary
/// winning. Nothing here is logged: the words are the user's.
public final class PageChats: @unchecked Sendable {
    public static let currentFormat = 1

    struct File: Codable {
        var format: Int
        var pageId: String
        /// New chat: turns sent up to here are gone, and stay gone when an older copy comes back from another device.
        var clearedAt: Date?
        var turns: [ChatTurn]
        var summary: ChatSummary?
    }

    public enum Failure: Error, Equatable { case newerFormat }

    private let folder: URL
    private let lock = NSLock()

    public init(root: URL) {
        folder = root.appending(path: "ai", directoryHint: .isDirectory)
    }

    func url(for pageId: String) throws -> URL {
        guard PageFiles.isValid(pageId) else { throw PageFiles.PageFileError.invalidID(pageId) }
        return folder.appending(path: "\(pageId).json")
    }

    /// The page's conversation (empty when it has none), without turns older than `retention` keeps.
    public func conversation(of pageId: String, retention: ChatRetention = .default, now: Date = .now) throws
        -> ChatConversation
    {
        guard let file = try lock.withLock({ try read(pageId) }) else { return ChatConversation() }
        let cutoff = retention.cutoff(now: now) ?? .distantPast
        return ChatConversation(
            turns: Self.visible(file).filter { $0.sentAt >= cutoff }, summary: file.summary, clearedAt: file.clearedAt)
    }

    /// Adds turns, or replaces ones with the same id (an answer kept again with its final words).
    public func save(_ turns: [ChatTurn], pageId: String) throws {
        guard !turns.isEmpty else { return }
        try change(pageId) { file in
            for turn in turns {
                if let index = file.turns.firstIndex(where: { $0.id == turn.id }) {
                    file.turns[index] = turn
                } else {
                    file.turns.append(turn)
                }
            }
            file.turns.sort { $0.sentAt < $1.sentAt }
        }
    }

    public func setSummary(_ summary: ChatSummary, pageId: String) throws {
        try change(pageId) { $0.summary = summary }
    }

    /// New chat: the conversation is emptied. Returns what it was, for `restore` (Undo).
    @discardableResult
    public func clear(pageId: String, now: Date = .now) throws -> ChatConversation {
        var previous = ChatConversation()
        try change(pageId) { file in
            previous = ChatConversation(turns: Self.visible(file), summary: file.summary, clearedAt: file.clearedAt)
            file.clearedAt = max(now, file.turns.map(\.sentAt).max() ?? now)
            file.turns = []
            file.summary = nil
        }
        return previous
    }

    /// Undo of `clear`: the conversation as it was, together with anything said since.
    public func restore(_ conversation: ChatConversation, pageId: String) throws {
        try change(pageId) { file in
            let newer = file.turns
            file.clearedAt = conversation.clearedAt
            file.summary = conversation.summary
            file.turns = (conversation.turns + newer.filter { turn in !conversation.turns.contains { $0.id == turn.id } })
                .sorted { $0.sentAt < $1.sentAt }
        }
    }

    /// The page is gone for good: its conversation goes too.
    public func removeAll(pageId: String) {
        guard let file = try? url(for: pageId) else { return }
        lock.withLock { _ = try? FileManager.default.removeItem(at: file) }
    }

    /// Settings → AI → Delete all conversations.
    public func removeEverything() {
        lock.withLock { _ = try? FileManager.default.removeItem(at: folder) }
    }

    /// Drops turns older than `retention` keeps from every page's file (a file left empty goes). Run at launch.
    public func prune(_ retention: ChatRetention, now: Date = .now) {
        guard let cutoff = retention.cutoff(now: now),
            let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return }
        for url in files where url.pathExtension == "json" {
            let pageId = url.deletingPathExtension().lastPathComponent
            try? lock.withLock {
                guard var file = try read(pageId) else { return }
                let kept = file.turns.filter { $0.sentAt >= cutoff }
                guard kept.count != file.turns.count else { return }
                if kept.isEmpty, file.clearedAt.map({ $0 < cutoff }) ?? true {
                    try FileManager.default.removeItem(at: url)
                    return
                }
                file.turns = kept
                if kept.isEmpty { file.summary = nil }
                try write(file)
            }
        }
    }

    // MARK: Reading, writing, merging

    private static func visible(_ file: File) -> [ChatTurn] {
        let cleared = file.clearedAt ?? .distantPast
        return file.turns.filter { $0.sentAt > cleared }.sorted { $0.sentAt < $1.sentAt }
    }

    private func change(_ pageId: String, _ apply: (inout File) throws -> Void) throws {
        try lock.withLock {
            var file = try read(pageId) ?? File(format: Self.currentFormat, pageId: pageId, turns: [])
            try apply(&file)
            try write(file)
        }
    }

    /// The file, with any conflicting versions iCloud kept merged in (and then let go); nil when there is none.
    private func read(_ pageId: String) throws -> File? {
        let url = try url(for: pageId)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        var file = try decode(Data(contentsOf: url))
        let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []
        if !conflicts.isEmpty {
            for version in conflicts {
                if let data = try? Data(contentsOf: version.url), let other = try? decode(data) {
                    file = Self.merge(file, other)
                }
            }
            try write(file)
            for version in conflicts { version.isResolved = true }
            try? NSFileVersion.removeOtherVersionsOfItem(at: url)
        }
        return file
    }

    private func decode(_ data: Data) throws -> File {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(File.self, from: data)
        guard file.format <= Self.currentFormat else { throw Failure.newerFormat }
        return file
    }

    private func write(_ file: File) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var file = file
        file.format = Self.currentFormat
        // Cleared turns aren't kept: the clearing date alone keeps them from coming back.
        file.turns = Self.visible(file)
        try encoder.encode(file).write(to: try url(for: file.pageId), options: .atomic)
    }

    /// Two devices' versions as one: every turn of either by id (the longer words for one on both — an answer kept
    /// while still arriving), the later clearing, the newer summary.
    static func merge(_ a: File, _ b: File) -> File {
        var byID: [String: ChatTurn] = [:]
        for turn in a.turns + b.turns {
            guard var known = byID[turn.id] else {
                byID[turn.id] = turn
                continue
            }
            if turn.text.count > known.text.count {
                known.text = turn.text
                known.citations = turn.citations
                known.thinking = turn.thinking ?? known.thinking
                known.images = turn.images ?? known.images
            }
            // Each card keeps the review furthest along (approved on one device, still pending on the other).
            if let changes = turn.changes {
                let mine = Dictionary((known.changes ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                known.changes = changes.map { change in mine[change.id].map { AIPageChange.merged($0, change) } ?? change }
            }
            byID[turn.id] = known
        }
        var merged = a
        merged.clearedAt = [a.clearedAt, b.clearedAt].compactMap { $0 }.max()
        merged.summary = [a.summary, b.summary].compactMap { $0 }.max { $0.createdAt < $1.createdAt }
        merged.turns = byID.values.sorted { $0.sentAt < $1.sentAt }
        return merged
    }
}
