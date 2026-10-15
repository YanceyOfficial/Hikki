import Foundation
import GRDB

/// A page as the index takes it: its title, its text blocks and the files it attaches.
public struct SearchDocument: Sendable, Equatable {
    public var id: String
    public var title: String
    public var icon: String?
    /// The page's text blocks with their ids, in reading order: a result names the block its match is in, and
    /// opens there.
    public var blocks: [SearchBlock]
    /// The readable files the page attaches (PDFs, images), each once.
    public var attachments: [SearchAttachment]
    public var updatedAt: Date

    public init(
        id: String, title: String, icon: String? = nil, blocks: [SearchBlock] = [], attachments: [SearchAttachment] = [],
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.blocks = blocks
        self.attachments = attachments
        self.updatedAt = updatedAt
    }

    /// The headings' text, each on one line (Spotlight's keywords).
    public var headings: [String] {
        blocks.filter(\.isHeading).map { $0.text.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
    }

    /// Every block's text, one per line (Spotlight's text).
    public var text: String { blocks.map(\.text).joined(separator: "\n") }
}

/// A block of a page as search sees it: the editor's block id ("" when it has none), whether it is a heading, its text.
public struct SearchBlock: Sendable, Equatable {
    public var id: String
    public var isHeading: Bool
    public var text: String

    public init(id: String, isHeading: Bool = false, text: String) {
        self.id = id
        self.isHeading = isHeading
        self.text = text
    }
}

/// A file a page attaches: the asset's name (unique in the workspace), the file's own name (nil for an inline
/// image) and the block showing it. Its text is read once per name (`FileTextReader`) and kept apart from pages.
public struct SearchAttachment: Sendable, Equatable {
    public var name: String
    public var label: String?
    public var blockId: String?

    public init(name: String, label: String? = nil, blockId: String? = nil) {
        self.name = name
        self.label = label
        self.blockId = blockId
    }
}

/// What the index holds of a page's identity: enough to tell whether a changed record needs indexing again.
public struct SearchStamp: Sendable, Equatable {
    public var title: String
    public var icon: String?
    public var updatedAt: Date

    public init(title: String, icon: String?, updatedAt: Date) {
        self.title = title
        self.icon = icon
        self.updatedAt = updatedAt
    }
}

/// Another block of a hit's page that holds a term: where it is and its excerpt (the palette's sub-rows).
public struct SearchMatch: Sendable, Equatable, Identifiable {
    public var blockId: String
    public var snippet: String
    public var id: String { blockId }

    public init(blockId: String, snippet: String) {
        self.blockId = blockId
        self.snippet = snippet
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
    /// Where the page opens: the block the excerpt comes from (`SearchRanker.bestBlock`), or the block showing the
    /// matching file; nil when only the title matched or the block has no id.
    public var blockId: String?
    /// The page's other blocks holding a term, in reading order (the first `SearchIndex.matchLimit`).
    public var moreMatches: [SearchMatch]
    /// How many other blocks hold a term, all of them (`moreMatches` lists the first few).
    public var moreMatchCount: Int

    public init(
        id: String, title: String, icon: String?, snippet: String, updatedAt: Date, terms: [String],
        attachment: Attachment? = nil, blockId: String? = nil, moreMatches: [SearchMatch] = [], moreMatchCount: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.snippet = snippet
        self.updatedAt = updatedAt
        self.terms = terms
        self.attachment = attachment
        self.blockId = blockId
        self.moreMatches = moreMatches
        self.moreMatchCount = moreMatchCount ?? moreMatches.count
    }
}

/// The search engine: its own SQLite file (WAL, so searches read while the app writes) holding what search needs
/// of every page — the title (with pinyin keys) and its text blocks — and the text read out of attached files. The
/// blocks and file texts are stored as written and once more folded (`SearchQuery.fold`: no case, no accents),
/// the folded copy under a trigram FTS5 index (CJK needs no word breaks). The app feeds it (`index`, `remove`) and
/// reconciles it against the store by `stamps`; nothing lives only here, so it can always be rebuilt — except the
/// file texts, which outlive a rebuild and a page's trip to the trash, so no file is read twice.
///
/// A search looks each term up on its own: the pages whose blocks (or files) hold it, summed BM25 per page.
/// Titles are ranked in Swift (`SearchRanker`) over every page, and only for the hits shown are the matching
/// blocks read — the best one opens, the others are listed.
public final class SearchIndex: Sendable {
    /// Bump when what is indexed, or how, changes: an older index empties itself and the app feeds it again
    /// (file texts are kept). 4: blocks in their own table, folded copies searched.
    public static let version = 4
    /// How many other matching blocks a hit lists.
    static let matchLimit = 50

    let writer: any DatabaseWriter

    public convenience init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try self.init(writer: DatabasePool(path: url.path))
    }

    public static func inMemory() throws -> SearchIndex {
        try SearchIndex(writer: DatabaseQueue())
    }

    private init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try writer.write { db in
            let version = try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0
            // File texts are worth keeping across layouts: reading them again means OCR over every picture.
            try db.create(table: "fileText", ifNotExists: true) { t in
                t.primaryKey("name", .text)
                t.column("text", .text).notNull().defaults(to: "")
                t.column("folded", .text).notNull().defaults(to: "")
                // Couldn't be read (damaged, not a PDF after all): not tried again.
                t.column("failed", .boolean).notNull().defaults(to: false)
            }
            if try !db.tableExists("fileTextFts") {
                try db.create(virtualTable: "fileTextFts", using: FTS5()) { t in
                    t.synchronize(withTable: "fileText")
                    t.tokenizer = FTS5TokenizerDescriptor(components: ["trigram"])
                    t.column("folded")
                }
            }
            if version != Self.version {
                // Version 3 kept file texts per page: they move over before the old tables go.
                if try db.tableExists("attachment"), try db.columns(in: "attachment").contains(where: { $0.name == "text" }) {
                    for row in try Row.fetchAll(db, sql: "SELECT name, text FROM attachment GROUP BY name") {
                        try Self.storeFileText(db, name: row["name"], text: row["text"])
                    }
                }
                // Older layouts go whole: the app refills the index from the store.
                for table in ["pageFts", "attachmentFts", "blockFts", "page", "attachment", "block", "pageFile"] {
                    try db.execute(sql: "DROP TABLE IF EXISTS \(table)")
                }
            }
            try db.create(table: "page", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull().defaults(to: "")
                t.column("titleFolded", .text).notNull().defaults(to: "")
                t.column("titlePinyin", .text).notNull().defaults(to: "")
                t.column("icon", .text)
                // Seconds since 1970, exactly as given (a datetime column keeps milliseconds only).
                t.column("updatedAt", .double).notNull()
            }
            try db.create(table: "block", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("pageId", .text).notNull()
                t.column("position", .integer).notNull()
                t.column("blockId", .text).notNull()
                t.column("isHeading", .boolean).notNull()
                t.column("text", .text).notNull()
                t.column("folded", .text).notNull()
            }
            try db.create(index: "block_page", on: "block", columns: ["pageId", "position"], ifNotExists: true)
            if try !db.tableExists("blockFts") {
                try db.create(virtualTable: "blockFts", using: FTS5()) { t in
                    t.synchronize(withTable: "block")
                    t.tokenizer = FTS5TokenizerDescriptor(components: ["trigram"])
                    t.column("folded")
                }
            }
            try db.create(table: "pageFile", ifNotExists: true) { t in
                t.column("pageId", .text).notNull()
                t.column("name", .text).notNull().indexed()
                t.column("label", .text)
                t.column("blockId", .text)
                t.column("position", .integer).notNull()
                t.primaryKey(["pageId", "name"])
            }
            // Semantic search's tables (removed 2026-10-15) go wherever they are left.
            for table in ["embeddingInfo", "embeddedPage", "chunk"] { try db.execute(sql: "DROP TABLE IF EXISTS \(table)") }
            if version != Self.version {
                try db.execute(sql: "PRAGMA user_version = \(Self.version)")
            }
        }
    }

    // MARK: - Feeding

    /// Adds or replaces these pages: title, blocks and which files they attach.
    public func index(_ documents: [SearchDocument]) throws {
        guard !documents.isEmpty else { return }
        try writer.write { db in
            let upsertPage = try db.cachedStatement(
                sql: """
                    INSERT INTO page (id, title, titleFolded, titlePinyin, icon, updatedAt) VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET title = excluded.title, titleFolded = excluded.titleFolded,
                        titlePinyin = excluded.titlePinyin, icon = excluded.icon, updatedAt = excluded.updatedAt
                    """)
            let insertBlock = try db.cachedStatement(
                sql: "INSERT INTO block (pageId, position, blockId, isHeading, text, folded) VALUES (?, ?, ?, ?, ?, ?)")
            let insertFile = try db.cachedStatement(
                sql: "INSERT OR IGNORE INTO pageFile (pageId, name, label, blockId, position) VALUES (?, ?, ?, ?, ?)")
            for document in documents {
                try upsertPage.execute(arguments: [
                    document.id, document.title, SearchQuery.fold(document.title), Pinyin.searchKey(for: document.title),
                    document.icon, document.updatedAt.timeIntervalSince1970,
                ])
                try db.execute(sql: "DELETE FROM block WHERE pageId = ?", arguments: [document.id])
                for (position, block) in document.blocks.enumerated() {
                    try insertBlock.execute(arguments: [
                        document.id, position, block.id, block.isHeading, block.text, SearchQuery.fold(block.text),
                    ])
                }
                try db.execute(sql: "DELETE FROM pageFile WHERE pageId = ?", arguments: [document.id])
                for (position, file) in document.attachments.enumerated() {
                    try insertFile.execute(arguments: [document.id, file.name, file.label, file.blockId, position])
                }
            }
        }
    }

    /// Forgets these pages (trashed, deleted). The text of their files stays: a restored page needs no reading.
    public func remove(_ ids: some Sequence<String>) throws {
        let ids = Array(ids)
        guard !ids.isEmpty else { return }
        try writer.write { db in
            for id in ids {
                try db.execute(sql: "DELETE FROM block WHERE pageId = ?", arguments: [id])
                try db.execute(sql: "DELETE FROM pageFile WHERE pageId = ?", arguments: [id])
                try db.execute(sql: "DELETE FROM page WHERE id = ?", arguments: [id])
            }
        }
    }

    /// Keeps a file's text, or — nil — that it can't be read (it isn't tried again).
    public func setFileText(_ text: String?, named name: String) throws {
        try writer.write { db in try Self.storeFileText(db, name: name, text: text) }
    }

    private static func storeFileText(_ db: Database, name: String, text: String?) throws {
        try db.execute(
            sql: """
                INSERT INTO fileText (name, text, folded, failed) VALUES (?, ?, ?, ?)
                ON CONFLICT(name) DO UPDATE SET text = excluded.text, folded = excluded.folded, failed = excluded.failed
                """, arguments: [name, text ?? "", SearchQuery.fold(text ?? ""), text == nil])
    }

    /// Files attached to an indexed page (among `names`, or anywhere) that have never been read, nor failed.
    public func unreadFiles(among names: [String]? = nil) throws -> [String] {
        if let names, names.isEmpty { return [] }
        return try writer.read { db in
            var sql = "SELECT DISTINCT p.name FROM pageFile p LEFT JOIN fileText f ON f.name = p.name WHERE f.name IS NULL"
            var arguments = StatementArguments()
            if let names {
                sql += " AND p.name IN (\(Array(repeating: "?", count: names.count).joined(separator: ",")))"
                arguments = StatementArguments(names)
            }
            return try String.fetchAll(db, sql: sql + " ORDER BY p.name", arguments: arguments)
        }
    }

    /// Whether a file's text has been read (or found unreadable).
    public func hasFileText(named name: String) throws -> Bool {
        try writer.read { db in try Bool.fetchOne(db, sql: "SELECT 1 FROM fileText WHERE name = ?", arguments: [name]) ?? false }
    }

    /// The edited time of every indexed page, by id — what a reconcile compares against the store.
    public func stamps() throws -> [String: Date] {
        try writer.read { db in
            Dictionary(
                uniqueKeysWithValues: try Row.fetchAll(db, sql: "SELECT id, updatedAt FROM page").map {
                    ($0["id"] as String, Date(timeIntervalSince1970: $0["updatedAt"]))
                })
        }
    }

    /// Title, icon and edited time of these pages as indexed; a record that still has them needs no indexing.
    public func stamps(of ids: [String]) throws -> [String: SearchStamp] {
        guard !ids.isEmpty else { return [:] }
        return try writer.read { db in
            let marks = Array(repeating: "?", count: ids.count).joined(separator: ",")
            var out: [String: SearchStamp] = [:]
            for row in try Row.fetchAll(
                db, sql: "SELECT id, title, icon, updatedAt FROM page WHERE id IN (\(marks))", arguments: StatementArguments(ids))
            {
                out[row["id"]] = SearchStamp(
                    title: row["title"], icon: row["icon"], updatedAt: Date(timeIntervalSince1970: row["updatedAt"]))
            }
            return out
        }
    }

    public var count: Int {
        (try? writer.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM page") }) ?? 0
    }

    // MARK: - Searching

    /// Best first. Every title is ranked; each term is looked up in the folded blocks and file texts — the trigram
    /// FTS (BM25, headings weighed 3×) for terms of three characters or more, a scan for shorter ones — so every
    /// page holding a term is a candidate, however many there are. A hit carries an excerpt from its best block
    /// (or an attached file's, when only that matched; always the file's when searching files) and the other
    /// matching blocks. `options` narrows where the terms may match (`SearchScope`) and orders by match or by
    /// edited time. Off the caller's actor; a cancelled task stops between the steps (and GRDB interrupts a read).
    @concurrent
    public func search(
        _ query: String, options: SearchOptions = .standard, limit: Int = 30, now: Date = .now
    ) async throws -> [SearchHit] {
        let parsed = SearchQuery(query)
        guard !parsed.isEmpty else { return [] }
        try Task.checkCancellation()
        let scope = options.scope
        let found = try await writer.read { db in try Self.gather(db, parsed, scope: scope) }
        try Task.checkCancellation()
        let ranks = Self.textRanks(found.text)
        let scored: [(page: PageRow, score: Int)] = found.pages.compactMap { page in
            let text = found.text[page.id]
            let file = found.files[page.id]
            let rankerPage = SearchRanker.Page(
                foldedTitle: page.titleFolded, titlePinyin: page.titlePinyin, headingTerms: text?.headingTerms ?? 0,
                textTerms: text?.terms.count ?? 0, fileTerms: file?.terms ?? 0, updatedAt: page.updatedAt,
                textRank: ranks[page.id] ?? 0)
            return SearchRanker.score(parsed, rankerPage, scope: scope, now: now).map { (page, $0) }
        }
        let top = scored.sorted { a, b in
            switch options.sort {
            case .relevance: a.score != b.score ? a.score > b.score : a.page.updatedAt > b.page.updatedAt
            case .edited: a.page.updatedAt != b.page.updatedAt ? a.page.updatedAt > b.page.updatedAt : a.score > b.score
            }
        }
        .prefix(limit).map(\.page)
        try Task.checkCancellation()
        let files = found.files
        let textPages = Set(found.text.keys)
        return try await writer.read { db in
            try top.map { page in
                try Self.hit(
                    db, page, parsed, scope: scope, textMatched: textPages.contains(page.id), file: files[page.id])
            }
        }
    }

    struct PageRow: Sendable {
        var id: String
        var title: String
        var titleFolded: String
        var titlePinyin: String
        var icon: String?
        var updatedAt: Date
    }

    /// The terms found in a page's blocks: which, how many in a heading, the summed BM25 (lower is better).
    struct TextMatch: Sendable {
        var terms: Set<String> = []
        var headingTerms = 0
        var bm25 = 0.0
    }

    /// The attached file holding the most terms, per page.
    struct FileMatch: Sendable {
        var name: String
        var label: String?
        var blockId: String?
        var position: Int
        var terms: Int
    }

    private struct FileKey: Hashable {
        var pageId: String
        var name: String
    }

    struct Gathered: Sendable {
        var pages: [PageRow]
        var text: [String: TextMatch]
        var files: [String: FileMatch]
    }

    private static func gather(_ db: Database, _ query: SearchQuery, scope: SearchScope) throws -> Gathered {
        let pages = try Row.fetchAll(db, sql: "SELECT id, title, titleFolded, titlePinyin, icon, updatedAt FROM page").map {
            PageRow(
                id: $0["id"], title: $0["title"], titleFolded: $0["titleFolded"], titlePinyin: $0["titlePinyin"],
                icon: $0["icon"], updatedAt: Date(timeIntervalSince1970: $0["updatedAt"]))
        }
        var text: [String: TextMatch] = [:]
        if scope == .all || scope == .text {
            for term in query.terms {
                let rows =
                    usesFTS(term)
                    ? try Row.fetchAll(
                        db,
                        sql: """
                            WITH hits AS MATERIALIZED (SELECT rowid AS r, rank AS score FROM blockFts WHERE blockFts MATCH ?)
                            SELECT b.pageId AS pageId, MAX(b.isHeading) AS heading,
                                SUM(hits.score * CASE WHEN b.isHeading THEN 3 ELSE 1 END) AS score
                            FROM hits JOIN block b ON b.id = hits.r GROUP BY b.pageId
                            """, arguments: [phrase(term)])
                    : try Row.fetchAll(
                        db,
                        sql: """
                            SELECT pageId, MAX(isHeading) AS heading, 0.0 AS score FROM block
                            WHERE instr(folded, ?) > 0 GROUP BY pageId
                            """, arguments: [term])
                for row in rows {
                    let id: String = row["pageId"]
                    text[id, default: TextMatch()].terms.insert(term)
                    if row["heading"] as Bool { text[id]!.headingTerms += 1 }
                    text[id]!.bm25 += row["score"] as Double
                }
            }
        }
        var files: [String: FileMatch] = [:]
        if scope == .all || scope == .files {
            var counts: [FileKey: FileMatch] = [:]
            for term in query.terms {
                let rows =
                    usesFTS(term)
                    ? try Row.fetchAll(
                        db,
                        sql: """
                            WITH hits AS MATERIALIZED (SELECT rowid AS r FROM fileTextFts WHERE fileTextFts MATCH ?)
                            SELECT p.pageId, p.name, p.label, p.blockId, p.position
                            FROM hits JOIN fileText f ON f.rowid = hits.r JOIN pageFile p ON p.name = f.name
                            """, arguments: [phrase(term)])
                    : try Row.fetchAll(
                        db,
                        sql: """
                            SELECT p.pageId, p.name, p.label, p.blockId, p.position
                            FROM fileText f JOIN pageFile p ON p.name = f.name WHERE instr(f.folded, ?) > 0
                            """, arguments: [term])
                for row in rows {
                    let key = FileKey(pageId: row["pageId"], name: row["name"])
                    var match =
                        counts[key]
                        ?? FileMatch(name: key.name, label: row["label"], blockId: row["blockId"], position: row["position"], terms: 0)
                    match.terms += 1
                    counts[key] = match
                }
            }
            // Per page, the file holding the most terms; the first attached on a tie.
            for (key, match) in counts {
                if let best = files[key.pageId],
                    best.terms > match.terms || best.terms == match.terms && best.position < match.position
                {
                    continue
                }
                files[key.pageId] = match
            }
        }
        return Gathered(pages: pages, text: text, files: files)
    }

    /// A hit as the palette shows it. Titles show no excerpt (the title is the match); files show the file's. The
    /// page's own excerpt comes from its best block (a heading ahead of body text), running on into the next ones.
    private static func hit(
        _ db: Database, _ page: PageRow, _ query: SearchQuery, scope: SearchScope, textMatched: Bool, file: FileMatch?
    ) throws -> SearchHit {
        var snippet = ""
        var blockId: String?
        var moreMatches: [SearchMatch] = []
        var moreMatchCount = 0
        if textMatched, scope == .all || scope == .text {
            let clauses = query.terms.map { _ in "instr(folded, ?) > 0" }.joined(separator: " OR ")
            let blocks = try Row.fetchAll(
                db,
                sql: """
                    SELECT position, blockId, isHeading, text, folded FROM block
                    WHERE pageId = ? AND (\(clauses)) ORDER BY position
                    """, arguments: StatementArguments([page.id] + query.terms)
            ).map {
                (
                    position: $0["position"] as Int, id: $0["blockId"] as String, isHeading: $0["isHeading"] as Bool,
                    text: $0["text"] as String, folded: $0["folded"] as String
                )
            }
            if let best = SearchRanker.bestBlock(query.terms, in: blocks.map { ($0.folded, $0.isHeading) }) {
                let chosen = blocks[best]
                blockId = chosen.id.isEmpty ? nil : chosen.id
                let following = try String.fetchAll(
                    db, sql: "SELECT text FROM block WHERE pageId = ? AND position > ? ORDER BY position LIMIT 3",
                    arguments: [page.id, chosen.position])
                snippet = SearchRanker.snippet(of: ([chosen.text] + following).joined(separator: " "), terms: query.terms)
                // Only blocks with an id can be landed on.
                let others = blocks.indices.filter { $0 != best && !blocks[$0].id.isEmpty }
                moreMatchCount = others.count
                moreMatches = others.prefix(matchLimit).map { index in
                    SearchMatch(
                        blockId: blocks[index].id, snippet: SearchRanker.snippet(of: blocks[index].text, terms: query.terms))
                }
            }
        }
        var attachment: SearchHit.Attachment?
        if snippet.isEmpty, scope != .titles, let file,
            let text = try String.fetchOne(db, sql: "SELECT text FROM fileText WHERE name = ?", arguments: [file.name])
        {
            snippet = SearchRanker.snippet(of: text, terms: query.terms)
            attachment = SearchHit.Attachment(name: file.name, label: file.label)
            blockId = file.blockId
        }
        return SearchHit(
            id: page.id, title: page.title, icon: page.icon, snippet: snippet, updatedAt: page.updatedAt, terms: query.terms,
            attachment: attachment, blockId: blockId, moreMatches: moreMatches, moreMatchCount: moreMatchCount)
    }

    /// Trigram FTS needs three characters (code points) to look a term up; shorter ones are scanned for.
    private static func usesFTS(_ term: String) -> Bool { term.unicodeScalars.count >= 3 }

    /// The term as one FTS5 phrase, quotes doubled.
    private static func phrase(_ term: String) -> String {
        "\"" + term.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// 40 for the best text match down to 0 for the last, by position (BM25 values aren't comparable across
    /// queries): more of the terms first, then the summed BM25; equals (short terms have no BM25) rank the same.
    private static func textRanks(_ matches: [String: TextMatch]) -> [String: Int] {
        let ordered = matches.map { (id: $0.key, terms: $0.value.terms.count, bm25: $0.value.bm25) }.sorted {
            $0.terms != $1.terms ? $0.terms > $1.terms : $0.bm25 < $1.bm25
        }
        guard ordered.count > 1 else { return Dictionary(uniqueKeysWithValues: ordered.map { ($0.id, 40) }) }
        let last = ordered.count - 1
        var out: [String: Int] = [:]
        var groupStart = 0
        for (index, match) in ordered.enumerated() {
            if index > 0, match.terms != ordered[index - 1].terms || match.bm25 != ordered[index - 1].bm25 { groupStart = index }
            out[match.id] = 40 * (last - groupStart) / last
        }
        return out
    }
}
