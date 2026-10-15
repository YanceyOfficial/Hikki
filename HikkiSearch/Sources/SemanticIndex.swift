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
    static let relatedLimit = 3
    /// A page counts as related only when it stands out from the rest: this many standard deviations above the
    /// average page… Similarities sit in a band of their own for every model (e5's around 0.9, bge-m3's around 0.45),
    /// so a fixed threshold would let everything or nothing through, and a query that means nothing in particular
    /// ("be") lifts no page above the others.
    static let relatedDeviations: Float = 1.6
    /// …and this much above it at least (a pack of near-equal pages has a spread too small to mean anything).
    static let relatedMargin: Float = 0.03
    /// Below this many pages with text there is no "rest" to stand out from.
    static let relatedMinimumPages = 5

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
            let rows = try Row.fetchCursor(
                db, sql: "SELECT chunk.pageId, chunk.text, chunk.vector, page.title FROM chunk JOIN page ON page.id = chunk.pageId")
            while let row = try rows.next() {
                let vector = Self.floats(row["vector"])
                guard vector.count == query.count else { continue }
                // A passage that is only the title (an empty page) says nothing about what the page holds.
                guard !Self.body(row["text"], title: row["title"]).isEmpty else { continue }
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
    /// a model's sense of meaning shouldn't shuffle an exact title), then up to `relatedLimit` pages found only by
    /// meaning (`SearchHit.related`) — those that stand out from the rest (`standouts`) — with their closest passage
    /// as the excerpt (`SearchHit.passage` keeps all of it for `closestSentence`). Only an unfiltered search (scope
    /// `all`) adds those: a filter asks where the words are.
    public func search(
        _ query: String, queryVector: [Float]?, options: SearchOptions = .standard, limit: Int = 30, now: Date = .now
    ) throws -> [SearchHit] {
        let hits = try search(query, options: options, limit: limit, now: now)
        guard options.scope == .all, let queryVector, !queryVector.isEmpty, Self.meansSomething(query) else { return hits }
        let matches = Self.standouts(try semanticMatches(queryVector, limit: .max))
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
            var hit = SearchHit(
                id: match.pageId, title: title, icon: row["icon"], snippet: Self.excerpt(match.passage, title: title),
                updatedAt: row["updatedAt"], terms: [], related: true)
            hit.passage = Self.body(match.passage, title: title)
            return hit
        }
        return hits + extra
    }

    /// The pages that stand out from the rest, closest first: `relatedDeviations` standard deviations and
    /// `relatedMargin` above the average similarity. Nothing when there are too few pages to tell.
    static func standouts(_ matches: [SemanticMatch]) -> [SemanticMatch] {
        guard matches.count >= relatedMinimumPages else { return [] }
        let count = Float(matches.count)
        let mean = matches.reduce(0) { $0 + $1.similarity } / count
        let deviation = (matches.reduce(0) { $0 + ($1.similarity - mean) * ($1.similarity - mean) } / count).squareRoot()
        let floor = mean + max(relatedMargin, relatedDeviations * deviation)
        return matches.filter { $0.similarity >= floor }.sorted { $0.similarity > $1.similarity }
    }

    /// Whether a query is worth asking by meaning: not a word fragment of one or two letters ("be", "of" — every page
    /// is as close to them as any other). One or two CJK characters do mean something (親, 両親).
    public static func meansSomething(_ query: String) -> Bool {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        return text.count >= 3 || !text.allSatisfy(\.isASCII)
    }

    /// The sentence of a passage closest in meaning to the query, given a way to embed sentences — what a hit
    /// found by meaning shows, so it explains itself ("両親と兄が一人います。" rather than the passage's start).
    /// nil when the passage has a single sentence or embedding fails.
    public static func closestSentence(
        in passage: String, to queryVector: [Float], embed: ([String]) async throws -> [[Float]]
    ) async -> String? {
        let sentences = Chunker.sentences(of: passage)
        guard sentences.count > 1, let vectors = try? await embed(sentences), vectors.count == sentences.count else {
            return nil
        }
        var best: (similarity: Float, index: Int)?
        for (index, vector) in vectors.enumerated() where vector.count == queryVector.count {
            var similarity: Float = 0
            vDSP_dotpr(queryVector, 1, vector, 1, &similarity, vDSP_Length(vector.count))
            if similarity > best?.similarity ?? -.infinity { best = (similarity, index) }
        }
        return best.map { sentences[$0.index] }
    }

    /// A passage without the title line it was embedded with.
    static func body(_ passage: String, title: String) -> String {
        var body = Substring(passage)
        let heading = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !heading.isEmpty, body.hasPrefix(heading) { body = body.dropFirst(heading.count) }
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A passage without the title line it was embedded with, cut to an excerpt's length.
    static func excerpt(_ passage: String, title: String) -> String {
        let text = body(passage, title: title).split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return text.count > 160 ? String(text.prefix(160)) + "…" : text
    }

    static func data(_ vector: [Float]) -> Data {
        vector.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    static func floats(_ data: Data) -> [Float] {
        data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}
