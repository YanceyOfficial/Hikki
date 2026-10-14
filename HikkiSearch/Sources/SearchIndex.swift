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

/// One result.
public struct SearchHit: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var icon: String?
    /// The page text around the first matching term; empty when only the title matched.
    public var snippet: String
    public var updatedAt: Date
    /// The query's terms, for emphasizing them in the title and the excerpt.
    public var terms: [String]

    public init(id: String, title: String, icon: String?, snippet: String, updatedAt: Date, terms: [String]) {
        self.id = id
        self.title = title
        self.icon = icon
        self.snippet = snippet
        self.updatedAt = updatedAt
        self.terms = terms
    }
}

/// The search engine: its own SQLite file holding what search needs of every page — title (with pinyin keys),
/// headings, text — under a trigram FTS5 index (BM25, headings weighed above text; CJK needs no word breaks).
/// The app feeds it (`index`, `remove`) and reconciles it against the store by `stamps`; nothing lives only here,
/// so it can always be rebuilt. Titles are ranked in Swift (`SearchRanker`) over every page; the index names the
/// candidates whose headings or text hold a term and orders them by BM25.
public final class SearchIndex: Sendable {
    /// Bump when what is indexed, or how, changes: an older index empties itself and the app feeds it again.
    public static let version = 1
    /// How many pages the text index offers the ranker per query.
    static let candidateLimit = 200

    private let queue: DatabaseQueue

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
            let version = try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0
            if version != Self.version {
                try db.execute(sql: "DELETE FROM page")
                try db.execute(sql: "PRAGMA user_version = \(Self.version)")
            }
        }
    }

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

    /// Forgets these pages (trashed, deleted).
    public func remove(_ ids: some Sequence<String>) throws {
        let ids = Array(ids)
        guard !ids.isEmpty else { return }
        try queue.write { db in
            for id in ids { try db.execute(sql: "DELETE FROM page WHERE id = ?", arguments: [id]) }
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

    /// Best first. Every title is ranked; headings and text come through the index — the trigram FTS (BM25,
    /// headings weighed 3×) for terms of three characters or more, LIKE for shorter ones — and the BM25 order
    /// among those candidates feeds the ranker. A hit carries an excerpt around the first matching term.
    public func search(_ query: String, limit: Int = 30, now: Date = .now) throws -> [SearchHit] {
        let parsed = SearchQuery(query)
        guard !parsed.isEmpty else { return [] }
        return try queue.read { db in
            let candidates = try Self.candidates(db, parsed)
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
            let pages = try Row.fetchAll(db, sql: "SELECT id, title, titlePinyin, icon, updatedAt FROM page")
            let scored: [(row: Row, text: String, score: Int)] = pages.compactMap { row in
                let id: String = row["id"]
                let body = bodies[id]
                let page = SearchRanker.Page(
                    title: row["title"], titlePinyin: row["titlePinyin"], headings: body?.headings ?? "",
                    text: body?.text ?? "", updatedAt: row["updatedAt"], textRank: ranks[id] ?? 0)
                guard let score = SearchRanker.score(parsed, page, now: now) else { return nil }
                return (row, body?.text ?? "", score)
            }
            return
                scored
                .sorted {
                    $0.score != $1.score ? $0.score > $1.score : ($0.row["updatedAt"] as Date) > ($1.row["updatedAt"] as Date)
                }
                .prefix(limit)
                .map { hit in
                    SearchHit(
                        id: hit.row["id"], title: hit.row["title"], icon: hit.row["icon"],
                        snippet: SearchRanker.snippet(of: hit.text, terms: parsed.terms), updatedAt: hit.row["updatedAt"],
                        terms: parsed.terms)
                }
        }
    }

    /// Pages whose headings or text hold a term, best BM25 first (the LIKE ones after, newest first, as they
    /// have no BM25 value).
    private static func candidates(_ db: Database, _ query: SearchQuery) throws -> [(id: String, rank: Double)] {
        var out: [(id: String, rank: Double)] = []
        var seen = Set<String>()
        let long = query.terms.filter { $0.count >= 3 }
        if !long.isEmpty {
            let match = long.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: " OR ")
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
