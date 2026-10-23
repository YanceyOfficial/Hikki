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
    /// Pictures the answer made (absent in older files and answers without any).
    public var pictures: [ChatPicture]?
    /// Where in the page the answer's pictures go (the chat was opened for pictures from there).
    public var picturePlace: PicturePlace?
    /// The workspace file tools the answer used, in order (absent in older files and answers without any).
    public var tools: [ChatToolCall]?

    public init(
        id: String, role: Role, text: String, sentAt: Date, attachments: [String] = [], citations: [ChatCitation] = [],
        changes: [AIPageChange]? = nil, thinking: ChatThinking? = nil, images: [ChatImage]? = nil,
        pictures: [ChatPicture]? = nil, picturePlace: PicturePlace? = nil, tools: [ChatToolCall]? = nil
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
        self.pictures = pictures
        self.picturePlace = picturePlace
        self.tools = tools
    }
}

/// A workspace file tool an answer used (`WorkspaceFiles`): which, on what, how it went, and what its card shows —
/// texts capped at `maxText`, so a conversation's file stays small.
public struct ChatToolCall: Codable, Equatable, Sendable, Identifiable {
    public enum Status: String, Codable, Sendable {
        case running
        /// A write or edit waiting for the user to allow it.
        case waiting
        case done
        case failed
        /// The user didn't allow it.
        case declined
        /// Stopped before it ran or was decided.
        case stopped
    }

    public static let maxText = 4000
    public static let maxResults = 50

    public var id: String
    /// The tool's name (`list_directory`, `read_file`, `find_files`, `grep`, `write_file`, `edit_file`).
    public var name: String
    /// The file or folder, relative to the workspace folder.
    public var path: String
    /// What a find or search looked for.
    public var pattern: String?
    public var status: Status
    /// Why it failed (the tool's words).
    public var message: String?
    /// Lines read, entries listed, files found, matches.
    public var count: Int?
    public var bytes: Int?
    /// What was read or written (cut at `maxText`).
    public var text: String?
    /// An edit's replaced text and its replacement (each cut at `maxText`).
    public var before: String?
    public var after: String?
    /// A write made the file (else it replaced or appended to one).
    public var created: Bool?
    public var appended: Bool?
    public var replacements: Int?
    /// What a find or search turned up (paths, at most `maxResults`).
    public var results: [String]?

    public init(id: String, name: String, path: String, pattern: String? = nil, status: Status = .running) {
        self.id = id
        self.name = name
        self.path = path
        self.pattern = pattern
        self.status = status
    }

    /// A text as it is kept.
    public static func capped(_ text: String?) -> String? {
        guard let text else { return nil }
        return text.count > maxText ? String(text.prefix(maxText)) : text
    }

    /// As a kept turn shows it again: one still running or waiting when it was kept isn't any more.
    public var restored: ChatToolCall {
        var call = self
        if call.status == .running || call.status == .waiting { call.status = .stopped }
        return call
    }
}

/// A picture an answer made (OpenAI's image model): what it was asked to draw, and — once made — the workspace asset
/// it is. Kept with the turn, so it is there after a restart and on other devices (the asset syncs with the folder).
public struct ChatPicture: Codable, Equatable, Sendable, Identifiable {
    public enum Status: String, Codable, Sendable {
        /// Being made (on the device that asked; elsewhere, or after a restart, it reads as stopped).
        case making
        case done
        /// Stopped before it was finished.
        case stopped
        case failed
    }

    public var id: String
    public var prompt: String
    /// wide, square or tall.
    public var shape: String
    public var detailed: Bool
    /// The earlier picture it changes ("attached": the one the user attached).
    public var from: String?
    public var status: Status
    /// The picture's address in the page (a workspace asset), once made.
    public var asset: String?
    /// Why it failed (the AI error's name).
    public var error: String?
    /// It was put into the page (shown on its tile).
    public var added: Bool?

    public init(
        id: String, prompt: String, shape: String, detailed: Bool = false, from: String? = nil, status: Status = .making,
        asset: String? = nil, error: String? = nil, added: Bool? = nil
    ) {
        self.id = id
        self.prompt = prompt
        self.shape = shape
        self.detailed = detailed
        self.from = from
        self.status = status
        self.asset = asset
        self.error = error
        self.added = added
    }

    /// Two devices' versions as one: a made picture wins over one still making (or stopped, or failed), the later
    /// try over the earlier; added on either is added.
    public static func merged(_ a: ChatPicture, _ b: ChatPicture) -> ChatPicture {
        var picture = a.status != .done && b.status == .done || a.status == b.status && b.asset != nil ? b : a
        if a.added == true || b.added == true { picture.added = true }
        return picture
    }
}

extension ChatPicture {
    /// As a kept turn shows it again: one still being made when it was kept (the chat left, the app quit, another
    /// device) isn't being made here — it reads as stopped, with Try again.
    public var restored: ChatPicture {
        var picture = self
        if picture.status == .making { picture.status = .stopped }
        return picture
    }
}

/// The chat's pictures being made: queued in order, drawn `lanes` at a time (each takes up to a minute). It only
/// says which to start; the chat runs them.
public struct PictureQueue: Sendable {
    public let lanes: Int
    public private(set) var waiting: [String] = []
    public private(set) var drawing: Set<String> = []

    public init(lanes: Int = 2) {
        self.lanes = max(1, lanes)
    }

    /// Nothing waiting or being drawn.
    public var isEmpty: Bool { waiting.isEmpty && drawing.isEmpty }

    public func contains(_ id: String) -> Bool { drawing.contains(id) || waiting.contains(id) }

    /// Queues pictures (one already queued or drawing stays where it is); returns those to start now.
    public mutating func add(_ ids: [String]) -> [String] {
        for id in ids where !contains(id) { waiting.append(id) }
        return next()
    }

    /// One is done with (made, failed or stopped); returns the next to start.
    public mutating func finished(_ id: String) -> [String] {
        waiting.removeAll { $0 == id }
        drawing.remove(id)
        return next()
    }

    /// Everything stops: returns what was waiting or drawing.
    public mutating func stopAll() -> [String] {
        let stopped = waiting + drawing.sorted()
        waiting = []
        drawing = []
        return stopped
    }

    private mutating func next() -> [String] {
        var started: [String] = []
        while drawing.count < lanes, !waiting.isEmpty {
            let id = waiting.removeFirst()
            drawing.insert(id)
            started.append(id)
        }
        return started
    }
}

/// Where an answer's pictures go in its page: after `blockId` (in place of it while it is an empty line), or in place
/// of it (`replace`: the picture being changed). No block: at the caret.
public struct PicturePlace: Codable, Equatable, Sendable {
    public var blockId: String?
    public var replace: Bool

    public init(blockId: String?, replace: Bool = false) {
        self.blockId = blockId
        self.replace = replace
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

    /// Two copies of a page's conversation file as one — both sides of a CloudKit conflict; nil when either can't be
    /// read (or is a newer format's), which leaves the conflict to the later write.
    public static func mergeFiles(_ a: Data, _ b: Data) -> Data? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let one = try? decoder.decode(File.self, from: a), let other = try? decoder.decode(File.self, from: b),
            one.format <= currentFormat, other.format <= currentFormat
        else { return nil }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var merged = merge(one, other)
        merged.format = currentFormat
        merged.turns = visible(merged)
        return try? encoder.encode(merged)
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
            if let pictures = turn.pictures {
                let mine = Dictionary((known.pictures ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                known.pictures = pictures.map { picture in mine[picture.id].map { ChatPicture.merged($0, picture) } ?? picture }
                known.picturePlace = known.picturePlace ?? turn.picturePlace
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
