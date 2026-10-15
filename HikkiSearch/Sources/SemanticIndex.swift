import Accelerate
import Foundation
import GRDB

/// A page's passage closest to a query, by meaning.
public struct SemanticMatch: Sendable, Equatable {
    public var pageId: String
    /// Cosine similarity (vectors are unit length, so a dot product).
    public var similarity: Float
    public var passage: String
}

/// Semantic search: page passages (`Chunker`) and their vectors, in the same file as the text index. The vectors come
/// from one model at a time (`useEmbeddingModel`); the app's indexer embeds pages, this stores and compares them.
/// Brute force over every passage — a few thousand 384-wide vectors take well under a millisecond with vDSP.
extension SearchIndex {
    /// How many pages found only by meaning are listed after the matches.
    static let relatedLimit = 5
    /// A page counts as related only when it stands out from the rest: above the median page by this much at least,
    /// and by half the distance to the closest page. Similarities sit in a narrow band for many models (e5's are all
    /// around 0.85), so a fixed threshold would let everything or nothing through.
    static let relatedMargin: Float = 0.015

    static func createSemanticTables(_ db: Database) throws {
        try db.create(table: "embeddingInfo", ifNotExists: true) { t in
            t.primaryKey("key", .text)
            t.column("value", .text).notNull()
        }
        try db.create(table: "embeddedPage", ifNotExists: true) { t in
            t.primaryKey("pageId", .text)
            t.column("updatedAt", .datetime).notNull()
        }
        try db.create(table: "chunk", ifNotExists: true) { t in
            t.column("pageId", .text).notNull()
            t.column("ordinal", .integer).notNull()
            t.column("hash", .text).notNull()
            t.column("text", .text).notNull()
            t.column("vector", .blob).notNull()
            t.primaryKey(["pageId", "ordinal"])
        }
    }

    // MARK: - Feeding

    /// The model the stored vectors come from.
    public func embeddingModel() throws -> String? {
        try queue.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM embeddingInfo WHERE key = 'model'")
        }
    }

    /// Makes `identity` the model of record; another model's vectors are dropped (they can't be compared). Returns
    /// whether it changed.
    @discardableResult
    public func useEmbeddingModel(_ identity: String) throws -> Bool {
        try queue.write { db in
            let current = try String.fetchOne(db, sql: "SELECT value FROM embeddingInfo WHERE key = 'model'")
            guard current != identity else { return false }
            try db.execute(sql: "DELETE FROM chunk")
            try db.execute(sql: "DELETE FROM embeddedPage")
            try db.execute(
                sql: "INSERT INTO embeddingInfo (key, value) VALUES ('model', ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                arguments: [identity])
            return true
        }
    }

    /// The edited time each page had when it was embedded, by id — what the indexer compares against the store.
    public func embeddingStamps() throws -> [String: Date] {
        try queue.read { db in
            Dictionary(
                uniqueKeysWithValues: try Row.fetchAll(db, sql: "SELECT pageId, updatedAt FROM embeddedPage").map {
                    ($0["pageId"] as String, $0["updatedAt"] as Date)
                })
        }
    }

    /// A page's stored vectors by passage hash: unchanged passages keep theirs.
    public func passageVectors(of pageId: String) throws -> [String: [Float]] {
        try queue.read { db in
            var out: [String: [Float]] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT hash, vector FROM chunk WHERE pageId = ?", arguments: [pageId]) {
                out[row["hash"]] = Self.floats(row["vector"])
            }
            return out
        }
    }

    /// Replaces a page's passages and stamps it with the edited time they were cut from.
    public func storeEmbeddings(pageId: String, updatedAt: Date, passages: [(Chunker.Chunk, [Float])]) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM chunk WHERE pageId = ?", arguments: [pageId])
            for (chunk, vector) in passages {
                try db.execute(
                    sql: "INSERT INTO chunk (pageId, ordinal, hash, text, vector) VALUES (?, ?, ?, ?, ?)",
                    arguments: [pageId, chunk.ordinal, chunk.hash, chunk.text, Self.data(vector)])
            }
            try db.execute(
                sql:
                    "INSERT INTO embeddedPage (pageId, updatedAt) VALUES (?, ?) ON CONFLICT(pageId) DO UPDATE SET updatedAt = excluded.updatedAt",
                arguments: [pageId, updatedAt])
        }
    }

    public var embeddedCount: Int {
        (try? queue.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM embeddedPage") }) ?? 0
    }

    // MARK: - Searching

    /// The closest passage of each page, closest pages first.
    public func semanticMatches(_ query: [Float], limit: Int) throws -> [SemanticMatch] {
        guard !query.isEmpty else { return [] }
        return try queue.read { db in
            var best: [String: SemanticMatch] = [:]
            let rows = try Row.fetchCursor(db, sql: "SELECT pageId, text, vector FROM chunk")
            while let row = try rows.next() {
                let vector = Self.floats(row["vector"])
                guard vector.count == query.count else { continue }
                var similarity: Float = 0
                vDSP_dotpr(query, 1, vector, 1, &similarity, vDSP_Length(query.count))
                let pageId: String = row["pageId"]
                if similarity > best[pageId]?.similarity ?? -.infinity {
                    best[pageId] = SemanticMatch(pageId: pageId, similarity: similarity, passage: row["text"])
                }
            }
            return Array(best.values.sorted { $0.similarity > $1.similarity }.prefix(limit))
        }
    }

    /// Search by words and, given the query's vector, by meaning: the word matches as they rank (what was typed wins;
    /// a small model's sense of meaning shouldn't shuffle an exact title), then up to `relatedLimit` pages found only
    /// by meaning (`SearchHit.related`) — those that stand out from the rest — with their closest passage as the
    /// excerpt. Only an unfiltered search (scope `all`) adds those: a filter asks where the words are.
    public func search(
        _ query: String, queryVector: [Float]?, options: SearchOptions = .standard, limit: Int = 30, now: Date = .now
    ) throws -> [SearchHit] {
        let hits = try search(query, options: options, limit: limit, now: now)
        guard options.scope == .all, let queryVector, !queryVector.isEmpty else { return hits }
        let all = try semanticMatches(queryVector, limit: .max)
        guard let closest = all.first?.similarity else { return hits }
        let median = all[all.count / 2].similarity
        let floor = median + max(Self.relatedMargin, (closest - median) / 2)
        let matches = Array(all.filter { $0.similarity >= floor }.prefix(limit))
        let matched = Set(hits.map(\.id))
        let related = matches.filter { !matched.contains($0.pageId) }.prefix(Self.relatedLimit)
        guard !related.isEmpty else { return hits }
        let pages = try queue.read { db in
            let marks = Array(repeating: "?", count: related.count).joined(separator: ",")
            return Dictionary(
                uniqueKeysWithValues: try Row.fetchAll(
                    db, sql: "SELECT id, title, icon, updatedAt FROM page WHERE id IN (\(marks))",
                    arguments: StatementArguments(related.map(\.pageId))
                ).map { ($0["id"] as String, $0) })
        }
        let extra: [SearchHit] = related.compactMap { match in
            guard let row = pages[match.pageId] else { return nil }
            let title: String = row["title"]
            return SearchHit(
                id: match.pageId, title: title, icon: row["icon"], snippet: Self.excerpt(match.passage, title: title),
                updatedAt: row["updatedAt"], terms: [], related: true)
        }
        return hits + extra
    }

    /// A passage without the title line it was embedded with, cut to an excerpt's length.
    static func excerpt(_ passage: String, title: String) -> String {
        var body = Substring(passage)
        let heading = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !heading.isEmpty, body.hasPrefix(heading) { body = body.dropFirst(heading.count) }
        let text = body.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return text.count > 160 ? String(text.prefix(160)) + "…" : text
    }

    static func data(_ vector: [Float]) -> Data {
        vector.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    static func floats(_ data: Data) -> [Float] {
        data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}
