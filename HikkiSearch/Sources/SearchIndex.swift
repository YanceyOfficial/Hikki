import Foundation
import GRDB

/// A page as the index takes it.
public struct SearchDocument: Sendable, Equatable {
    public var id: String
    public var title: String
    public var icon: String?
    public var headings: [String]
    public var text: String
    public var updatedAt: Date

    public init(id: String, title: String, icon: String? = nil, headings: [String] = [], text: String = "", updatedAt: Date) {
        self.id = id
        self.title = title
        self.icon = icon
        self.headings = headings
        self.text = text
        self.updatedAt = updatedAt
    }
}

/// The text read out of a file attached to a page (`AttachmentText`), as the index takes it.
public struct SearchAttachment: Sendable, Equatable {
    /// The asset's file name (unique in the workspace).
    public var name: String
    public var pageId: String
    /// The file's own name as attached; nil for an inline image.
    public var label: String?
    public var text: String

    public init(name: String, pageId: String, label: String? = nil, text: String) {
        self.name = name
        self.pageId = pageId
        self.label = label
        self.text = text
    }
}

/// One result.
public struct SearchHit: Sendable, Equatable, Identifiable {
    /// The attachment a hit's excerpt came from.
    public struct Attachment: Sendable, Equatable {
        public var name: String
        /// The file's own name; nil for an inline image.
        public var label: String?

        public init(name: String, label: String?) {
            self.name = name
            self.label = label
        }
    }

    public var id: String
    public var title: String
    public var icon: String?
    /// Text around the first matching term — the page's, or an attachment's when only that matched; empty when
    /// only the title matched.
    public var snippet: String
    public var updatedAt: Date
    /// The query's terms, for emphasizing them in the title and the excerpt.
    public var terms: [String]
    /// Set when the excerpt is an attachment's text.
    public var attachment: Attachment?
    /// Found by meaning only (semantic search), not by the words typed: the excerpt is the closest passage.
    public var related: Bool

    public init(
        id: String, title: String, icon: String?, snippet: String, updatedAt: Date, terms: [String],
        attachment: Attachment? = nil, related: Bool = false
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.snippet = snippet
        self.updatedAt = updatedAt
        self.terms = terms
        self.attachment = attachment
        self.related = related
    }
}

/// The search engine: its own SQLite file holding what search needs of every page — title (with pinyin keys),
/// headings, text — under a trigram FTS5 index (BM25, headings weighed above text; CJK needs no word breaks),
/// and the text of attached files beside it. The app feeds it (`index`, `remove`) and reconciles it against the
/// store by `stamps`; nothing lives only here, so it can always be rebuilt. Titles are ranked in Swift
/// (`SearchRanker`) over every page; the index names the candidates whose headings, text or attachments hold a
/// term and orders them by BM25.
public final class SearchIndex: Sendable {
    /// Bump when what is indexed, or how, changes: an older index empties itself and the app feeds it again.
    public static let version = 2
    /// How many pages the text index offers the ranker per query.
    static let candidateLimit = 200

    let queue: DatabaseQueue

    public convenience init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try self.init(queue: DatabaseQueue(path: url.path))
    }

    public static func inMemory() throws -> SearchIndex {
        try SearchIndex(queue: DatabaseQueue())
    }

    private init(queue: DatabaseQueue) throws {
        self.queue = queue
        try queue.write { db in
            let version = try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0
            if version != Self.version {
                // Older layouts go whole: the app refills the index from the store.
                for table in [
                    "pageFts", "attachmentFts", "page", "attachment", "embeddingInfo", "embeddedPage", "chunk",
                ] {
                    try db.execute(sql: "DROP TABLE IF EXISTS \(table)")
                }
            }
            try db.create(table: "page", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull().defaults(to: "")
                t.column("titlePinyin", .text).notNull().defaults(to: "")
                t.column("icon", .text)
                t.column("headings", .text).notNull().defaults(to: "")
                t.column("text", .text).notNull().defaults(to: "")
                t.column("updatedAt", .datetime).notNull()
            }
            if try !db.tableExists("pageFts") {
                try db.create(virtualTable: "pageFts", using: FTS5()) { t in
                    t.synchronize(withTable: "page")
                    t.tokenizer = FTS5TokenizerDescriptor(components: ["trigram"])
                    t.column("title")
                    t.column("headings")
                    t.column("text")
                }
            }
            try db.create(table: "attachment", ifNotExists: true) { t in
                t.column("name", .text).notNull()
                t.column("pageId", .text).notNull().indexed()
                t.column("label", .text)
                t.column("text", .text).notNull().defaults(to: "")
                t.primaryKey(["name", "pageId"])
            }
            if try !db.tableExists("attachmentFts") {
                try db.create(virtualTable: "attachmentFts", using: FTS5()) { t in
                    t.synchronize(withTable: "attachment")
                    t.tokenizer = FTS5TokenizerDescriptor(components: ["trigram"])
                    t.column("text")
                }
            }
            try Self.createSemanticTables(db)
            if version != Self.version {
                try db.execute(sql: "PRAGMA user_version = \(Self.version)")
            }
        }
    }

    // MARK: - Feeding

    /// Adds or replaces these pages.
    public func index(_ documents: [SearchDocument]) throws {
        guard !documents.isEmpty else { return }
        try queue.write { db in
            for document in documents {
                try db.execute(
                    sql: """
                        INSERT INTO page (id, title, titlePinyin, icon, headings, text, updatedAt) VALUES (?, ?, ?, ?, ?, ?, ?)
                        ON CONFLICT(id) DO UPDATE SET title = excluded.title, titlePinyin = excluded.titlePinyin,
                            icon = excluded.icon, headings = excluded.headings, text = excluded.text, updatedAt = excluded.updatedAt
                        """,
                    arguments: [
                        document.id, document.title, Pinyin.searchKey(for: document.title), document.icon,
                        document.headings.joined(separator: "\n"), document.text, document.updatedAt,
                    ])
            }
        }
    }

    /// Forgets these pages (trashed, deleted), their attachments and passages with them.
    public func remove(_ ids: some Sequence<String>) throws {
        let ids = Array(ids)
        guard !ids.isEmpty else { return }
        try queue.write { db in
            for id in ids {
                try db.execute(sql: "DELETE FROM attachment WHERE pageId = ?", arguments: [id])
                try db.execute(sql: "DELETE FROM page WHERE id = ?", arguments: [id])
                try db.execute(sql: "DELETE FROM chunk WHERE pageId = ?", arguments: [id])
                try db.execute(sql: "DELETE FROM embeddedPage WHERE pageId = ?", arguments: [id])
            }
        }
    }

    /// Adds or replaces the text of these attachments.
    public func index(attachments: [SearchAttachment]) throws {
        guard !attachments.isEmpty else { return }
        try queue.write { db in
            for attachment in attachments {
                try db.execute(
                    sql: """
                        INSERT INTO attachment (name, pageId, label, text) VALUES (?, ?, ?, ?)
                        ON CONFLICT(name, pageId) DO UPDATE SET label = excluded.label, text = excluded.text
                        """, arguments: [attachment.name, attachment.pageId, attachment.label, attachment.text])
            }
        }
    }

    /// Forgets these attachments of a page (no longer in it).
    public func removeAttachments(_ names: some Sequence<String>, of pageId: String) throws {
        let names = Array(names)
        guard !names.isEmpty else { return }
        try queue.write { db in
            for name in names {
                try db.execute(sql: "DELETE FROM attachment WHERE name = ? AND pageId = ?", arguments: [name, pageId])
            }
        }
    }

    /// The attachments indexed for a page, by asset name.
    public func attachmentNames(of pageId: String) throws -> Set<String> {
        try queue.read { db in
            Set(try String.fetchAll(db, sql: "SELECT name FROM attachment WHERE pageId = ?", arguments: [pageId]))
        }
    }

    /// Text already read for this asset (attached to another page too), so it isn't read twice.
    public func attachmentText(named name: String) throws -> String? {
        try queue.read { db in
            try String.fetchOne(db, sql: "SELECT text FROM attachment WHERE name = ? LIMIT 1", arguments: [name])
        }
    }

    /// The edited time of every indexed page, by id — what a reconcile compares against the store.
    public func stamps() throws -> [String: Date] {
        try queue.read { db in
            Dictionary(
                uniqueKeysWithValues: try Row.fetchAll(db, sql: "SELECT id, updatedAt FROM page").map {
                    ($0["id"] as String, $0["updatedAt"] as Date)
                })
        }
    }

    public var count: Int {
        (try? queue.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM page") }) ?? 0
    }

    // MARK: - Searching

    /// Best first. Every title is ranked; headings, text and attachments come through the index — the trigram
    /// FTS (BM25, headings weighed 3×) for terms of three characters or more, LIKE for shorter ones — and the
    /// BM25 order among those candidates feeds the ranker. A hit carries an excerpt around the first matching
    /// term: the page's, or an attachment's when only that matched (always an attachment's when searching files).
    /// `options` narrows where the terms may match (`SearchScope`) and orders by match or by edited time.
    public func search(
        _ query: String, options: SearchOptions = .standard, limit: Int = 30, now: Date = .now
    ) throws -> [SearchHit] {
        let parsed = SearchQuery(query)
        guard !parsed.isEmpty else { return [] }
        let scope = options.scope
        return try queue.read { db in
            let candidates = scope == .all || scope == .text ? try Self.candidates(db, parsed) : []
            let ranks = Self.textRanks(candidates)
            var bodies: [String: (headings: String, text: String)] = [:]
            if !candidates.isEmpty {
                let marks = Array(repeating: "?", count: candidates.count).joined(separator: ",")
                for row in try Row.fetchAll(
                    db, sql: "SELECT id, headings, text FROM page WHERE id IN (\(marks))",
                    arguments: StatementArguments(candidates.map(\.id)))
                {
                    bodies[row["id"]] = (row["headings"], row["text"])
                }
            }
            let attachments = scope == .all || scope == .files ? try Self.attachmentCandidates(db, parsed) : [:]
            let pages = try Row.fetchAll(db, sql: "SELECT id, title, titlePinyin, icon, updatedAt FROM page")
            let scored: [(row: Row, text: String, attachment: AttachmentRow?, score: Int)] = pages.compactMap { row in
                let id: String = row["id"]
                let body = bodies[id]
                let attachment = attachments[id]
                let page = SearchRanker.Page(
                    title: row["title"], titlePinyin: row["titlePinyin"], headings: body?.headings ?? "",
                    text: body?.text ?? "", attachmentText: attachment?.text ?? "", updatedAt: row["updatedAt"],
                    textRank: ranks[id] ?? 0)
                guard let score = SearchRanker.score(parsed, page, scope: scope, now: now) else { return nil }
                return (row, body?.text ?? "", attachment, score)
            }
            return
                scored
                .sorted {
                    let (a, b) = ($0.row["updatedAt"] as Date, $1.row["updatedAt"] as Date)
                    switch options.sort {
                    case .relevance: return $0.score != $1.score ? $0.score > $1.score : a > b
                    case .edited: return a != b ? a > b : $0.score > $1.score
                    }
                }
                .prefix(limit)
                .map { hit in
                    // Titles show no excerpt (the title is the match); files show the file's.
                    var snippet = scope == .titles || scope == .files ? "" : SearchRanker.snippet(of: hit.text, terms: parsed.terms)
                    var attachment: SearchHit.Attachment?
                    if snippet.isEmpty, scope != .titles, let found = hit.attachment {
                        snippet = SearchRanker.snippet(of: found.text, terms: parsed.terms)
                        attachment = SearchHit.Attachment(name: found.name, label: found.label)
                    }
                    return SearchHit(
                        id: hit.row["id"], title: hit.row["title"], icon: hit.row["icon"], snippet: snippet,
                        updatedAt: hit.row["updatedAt"], terms: parsed.terms, attachment: attachment)
                }
        }
    }

    private struct AttachmentRow {
        var name: String
        var label: String?
        var text: String
    }

    /// The FTS MATCH expression for the terms of three characters or more: each one a phrase, any of them.
    private static func matchExpression(_ query: SearchQuery) -> String? {
        let long = query.terms.filter { $0.count >= 3 }
        guard !long.isEmpty else { return nil }
        return long.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: " OR ")
    }

    /// Pages whose headings or text hold a term, best BM25 first (the LIKE ones after, newest first, as they
    /// have no BM25 value).
    private static func candidates(_ db: Database, _ query: SearchQuery) throws -> [(id: String, rank: Double)] {
        var out: [(id: String, rank: Double)] = []
        var seen = Set<String>()
        if let match = matchExpression(query) {
            for row in try Row.fetchAll(
                db,
                sql: """
                    SELECT p.id AS id, bm25(pageFts, 0.0, 3.0, 1.0) AS rank
                    FROM pageFts JOIN page p ON p.rowid = pageFts.rowid
                    WHERE pageFts MATCH ? ORDER BY rank LIMIT ?
                    """, arguments: [match, candidateLimit])
            where seen.insert(row["id"]).inserted {
                out.append((row["id"], row["rank"]))
            }
        }
        let short = query.terms.filter { $0.count < 3 }
        if !short.isEmpty {
            let clauses = short.map { _ in "(text LIKE ? ESCAPE '\\' OR headings LIKE ? ESCAPE '\\')" }.joined(separator: " OR ")
            var arguments: [DatabaseValueConvertible] = []
            for term in short {
                let pattern = likePattern(term)
                arguments += [pattern, pattern]
            }
            arguments.append(candidateLimit)
            for id in try String.fetchAll(
                db, sql: "SELECT id FROM page WHERE \(clauses) ORDER BY updatedAt DESC LIMIT ?",
                arguments: StatementArguments(arguments))
            where seen.insert(id).inserted {
                out.append((id, 0))
            }
        }
        return out
    }

    /// The best-ranked attachment holding a term, per page.
    private static func attachmentCandidates(_ db: Database, _ query: SearchQuery) throws -> [String: AttachmentRow] {
        var out: [String: AttachmentRow] = [:]
        if let match = matchExpression(query) {
            for row in try Row.fetchAll(
                db,
                sql: """
                    SELECT a.name AS name, a.pageId AS pageId, a.label AS label, a.text AS text
                    FROM attachmentFts JOIN attachment a ON a.rowid = attachmentFts.rowid
                    WHERE attachmentFts MATCH ? ORDER BY rank LIMIT ?
                    """, arguments: [match, candidateLimit])
            where out[row["pageId"]] == nil {
                out[row["pageId"]] = AttachmentRow(name: row["name"], label: row["label"], text: row["text"])
            }
        }
        let short = query.terms.filter { $0.count < 3 }
        if !short.isEmpty {
            let clauses = short.map { _ in "text LIKE ? ESCAPE '\\'" }.joined(separator: " OR ")
            var arguments: [DatabaseValueConvertible] = short.map(likePattern)
            arguments.append(candidateLimit)
            for row in try Row.fetchAll(
                db, sql: "SELECT name, pageId, label, text FROM attachment WHERE \(clauses) LIMIT ?",
                arguments: StatementArguments(arguments))
            where out[row["pageId"]] == nil {
                out[row["pageId"]] = AttachmentRow(name: row["name"], label: row["label"], text: row["text"])
            }
        }
        return out
    }

    /// 40 for the best candidate down to 0 for the last, by position (BM25 values aren't comparable across queries).
    private static func textRanks(_ candidates: [(id: String, rank: Double)]) -> [String: Int] {
        guard candidates.count > 1 else { return Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, 40) }) }
        let last = candidates.count - 1
        return Dictionary(uniqueKeysWithValues: candidates.enumerated().map { ($1.id, 40 * (last - $0) / last) })
    }

    private static func likePattern(_ term: String) -> String {
        "%"
            + term.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_") + "%"
    }
}
