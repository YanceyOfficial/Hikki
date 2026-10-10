import Foundation
import GRDB

public struct DocumentRecord: Codable, Sendable, Equatable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "document"

    public var id: String
    public var title: String
    /// Tiptap JSON (body only — the title is its own column), nil for a never-edited document.
    public var content: String?
    public var plainText: String
    public var wordCount: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var parentId: String?
    /// An emoji, or nil.
    public var icon: String?
    /// A `PageCover` raw value, or nil.
    public var cover: String?
    public var favoritedAt: Date?
    public var deletedAt: Date?
    public var sortKey: Double
    /// Derived from `title` on every save (see `Pinyin.searchKey`).
    public var titlePinyin: String = ""

    public var isFavorite: Bool { favoritedAt != nil }

    public func contentValue() throws -> JSONValue? {
        try content.map { try JSONValue(jsonData: Data($0.utf8)) }
    }
}

/// Everything the sidebar, breadcrumbs, favorites and trash need — no content.
public struct PageSummary: Codable, Sendable, Equatable, Identifiable, FetchableRecord {
    public var id: String
    public var parentId: String?
    public var title: String
    public var icon: String?
    public var updatedAt: Date
    public var favoritedAt: Date?
    public var deletedAt: Date?
    public var sortKey: Double

    public var isFavorite: Bool { favoritedAt != nil }
}

public struct SearchHit: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var icon: String?
    /// Body excerpt around the match, empty when only the title matched.
    public var snippet: String

    public init(id: String, title: String, icon: String?, snippet: String) {
        self.id = id
        self.title = title
        self.icon = icon
        self.snippet = snippet
    }
}

/// SQLite-backed page store. Tests use the in-memory initializer, which runs the exact same
/// migrations and queries — no separate fake to drift out of sync.
///
/// Write paths are split by owner so a late debounced editor save can never revert a metadata change:
/// `saveContent` writes only editor-owned columns; icon/cover/favorite/trash have their own methods.
public final class DocumentStore: Sendable {
    private let writer: any DatabaseWriter

    public static func onDisk(at url: URL) throws -> DocumentStore {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return try DocumentStore(writer: DatabasePool(path: url.path, configuration: configuration))
    }

    public static func inMemory() throws -> DocumentStore {
        try DocumentStore(writer: DatabaseQueue(configuration: configuration))
    }

    private static var configuration: Configuration {
        var config = Configuration()
        config.foreignKeysEnabled = true
        return config
    }

    private init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1-documents") { db in
            try db.create(table: "document") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull().defaults(to: "")
                t.column("content", .text)
                t.column("plainText", .text).notNull().defaults(to: "")
                t.column("wordCount", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull().indexed()
            }
        }
        migrator.registerMigration("v2-pages") { db in
            try db.alter(table: "document") { t in
                t.add(column: "parentId", .text).references("document", onDelete: .cascade)
                t.add(column: "icon", .text)
                t.add(column: "cover", .text)
                t.add(column: "favoritedAt", .datetime)
                t.add(column: "deletedAt", .datetime)
                t.add(column: "sortKey", .double).notNull().defaults(to: 0)
            }
            try db.create(index: "document_parentId", on: "document", columns: ["parentId"])
            // Existing pages keep their old (newest-first) order as top-level siblings.
            try db.execute(
                sql: """
                    UPDATE document SET sortKey = (SELECT COUNT(*) FROM document d2 WHERE d2.updatedAt > document.updatedAt)
                    """)
            // Trigram handles CJK, which has no spaces for a word tokenizer to split on.
            try db.create(virtualTable: "documentFts", using: FTS5()) { t in
                t.synchronize(withTable: "document")
                t.tokenizer = FTS5TokenizerDescriptor(components: ["trigram"])
                t.column("title")
                t.column("plainText")
            }
        }
        migrator.registerMigration("v3-title-pinyin") { db in
            try db.alter(table: "document") { t in
                t.add(column: "titlePinyin", .text).notNull().defaults(to: "")
            }
            for row in try Row.fetchAll(db, sql: "SELECT id, title FROM document") {
                let title: String = row["title"]
                try db.execute(
                    sql: "UPDATE document SET titlePinyin = ? WHERE id = ?", arguments: [Pinyin.searchKey(for: title), row["id"] as String])
            }
        }
        return migrator
    }

    // MARK: - Create / read

    @discardableResult
    public func create(id: String = UUID().uuidString, parentId: String? = nil, now: Date = .now) throws -> DocumentRecord {
        try writer.write { db in
            let last = try Double.fetchOne(db, sql: "SELECT MAX(sortKey) FROM document WHERE parentId IS ?", arguments: [parentId]) ?? -1
            let record = DocumentRecord(
                id: id, title: "", content: nil, plainText: "", wordCount: 0, createdAt: now, updatedAt: now,
                parentId: parentId, icon: nil, cover: nil, favoritedAt: nil, deletedAt: nil, sortKey: last + 1, titlePinyin: ""
            )
            try record.insert(db)
            return record
        }
    }

    /// Copies a live page (title, icon, cover, body — not its subpages, favorite or trash state) and places
    /// the copy right after it among its siblings. Returns the copy, or nil when the page doesn't exist.
    @discardableResult
    public func duplicate(id: String, newId: String = UUID().uuidString, now: Date = .now) throws -> DocumentRecord? {
        try writer.write { db in
            guard var copy = try DocumentRecord.fetchOne(db, key: id), copy.deletedAt == nil else { return nil }
            var siblings = try String.fetchAll(
                db,
                sql: "SELECT id FROM document WHERE parentId IS ? AND deletedAt IS NULL ORDER BY sortKey, createdAt, id",
                arguments: [copy.parentId])
            siblings.insert(newId, at: (siblings.firstIndex(of: id) ?? siblings.count - 1) + 1)
            copy.id = newId
            copy.createdAt = now
            copy.updatedAt = now
            copy.favoritedAt = nil
            try copy.insert(db)
            for (position, sibling) in siblings.enumerated() {
                try db.execute(sql: "UPDATE document SET sortKey = ? WHERE id = ?", arguments: [Double(position), sibling])
            }
            copy.sortKey = Double(siblings.firstIndex(of: newId) ?? 0)
            return copy
        }
    }

    public func document(id: String) throws -> DocumentRecord? {
        try writer.read { try DocumentRecord.fetchOne($0, key: id) }
    }

    /// Live (not trashed) pages, in sibling order.
    public func pages() throws -> [PageSummary] {
        try writer.read { try Self.pagesRequest.fetchAll($0) }
    }

    public func observePages() -> AsyncValueObservation<[PageSummary]> {
        ValueObservation.tracking { try Self.pagesRequest.fetchAll($0) }
            .removeDuplicates()
            .values(in: writer)
    }

    /// Pages the user trashed directly (their trashed children travel with them), newest first.
    public func trash() throws -> [PageSummary] {
        try writer.read { try Self.trashRequest.fetchAll($0) }
    }

    public func observeTrash() -> AsyncValueObservation<[PageSummary]> {
        ValueObservation.tracking { try Self.trashRequest.fetchAll($0) }
            .removeDuplicates()
            .values(in: writer)
    }

    /// Ancestors from the root down to (not including) the page.
    public func ancestors(of id: String) throws -> [PageSummary] {
        try writer.read { db in
            try PageSummary.fetchAll(
                db,
                sql: """
                    WITH RECURSIVE up(id, depth) AS (
                        SELECT parentId, 1 FROM document WHERE id = ?
                        UNION ALL
                        SELECT d.parentId, up.depth + 1 FROM document d JOIN up ON d.id = up.id WHERE d.parentId IS NOT NULL
                    )
                    SELECT \(Self.summaryColumns) FROM document JOIN up ON document.id = up.id ORDER BY up.depth DESC
                    """, arguments: [id])
        }
    }

    // MARK: - Editor-owned writes

    /// Writes only the editor-owned columns. Returns false when the page no longer exists.
    @discardableResult
    public func saveContent(_ snapshot: Snapshot, now: Date = .now) throws -> Bool {
        let json = String(decoding: try snapshot.content.jsonData(), as: UTF8.self)
        return try writer.write { db in
            try db.execute(
                sql: """
                    UPDATE document SET title = ?, titlePinyin = ?, content = ?, plainText = ?, wordCount = ?, updatedAt = ?
                    WHERE id = ? AND (content IS NOT ? OR title IS NOT ?)
                    """,
                arguments: [
                    snapshot.title, Pinyin.searchKey(for: snapshot.title), json, snapshot.text, snapshot.wordCount, now,
                    snapshot.docId, json, snapshot.title,
                ]
            )
            if db.changesCount > 0 { return true }
            return try DocumentRecord.exists(db, key: snapshot.docId)
        }
    }

    // MARK: - Metadata writes

    public func setIcon(_ icon: String?, for id: String, now: Date = .now) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE document SET icon = ?, updatedAt = ? WHERE id = ?", arguments: [icon, now, id])
        }
    }

    public func setCover(_ cover: String?, for id: String, now: Date = .now) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE document SET cover = ?, updatedAt = ? WHERE id = ?", arguments: [cover, now, id])
        }
    }

    /// Favoriting isn't an edit: `updatedAt` is left alone.
    public func setFavorite(_ favorite: Bool, for id: String, now: Date = .now) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE document SET favoritedAt = ? WHERE id = ?", arguments: [favorite ? now : nil, id])
        }
    }

    // MARK: - Moving (sidebar drag and drop)

    public enum MoveError: Error, Equatable {
        case notFound(String)
        /// Moving a page into itself or one of its descendants would detach the subtree from the tree.
        case wouldCreateCycle
    }

    /// Moves a page under `parentId` (nil = top level) at `index` among its new siblings (clamped).
    /// Siblings are renumbered 0…n, so order stays exact without fractional keys drifting.
    /// Moving isn't an edit: `updatedAt` is left alone.
    public func move(id: String, toParent parentId: String?, at index: Int) throws {
        try writer.write { db in
            guard try DocumentRecord.exists(db, key: id) else { throw MoveError.notFound(id) }
            if let parentId {
                guard try DocumentRecord.exists(db, key: parentId) else { throw MoveError.notFound(parentId) }
                let isInsideItself =
                    try Bool.fetchOne(
                        db,
                        sql: """
                            \(Self.subtreeCTE) SELECT EXISTS (SELECT 1 FROM sub WHERE id = ?)
                            """, arguments: [id, parentId]) ?? false
                if isInsideItself { throw MoveError.wouldCreateCycle }
            }
            var siblings = try String.fetchAll(
                db,
                sql: """
                    SELECT id FROM document WHERE parentId IS ? AND deletedAt IS NULL AND id != ? ORDER BY sortKey, createdAt, id
                    """, arguments: [parentId, id])
            siblings.insert(id, at: min(max(index, 0), siblings.count))
            try db.execute(sql: "UPDATE document SET parentId = ? WHERE id = ?", arguments: [parentId, id])
            for (position, sibling) in siblings.enumerated() {
                try db.execute(sql: "UPDATE document SET sortKey = ? WHERE id = ?", arguments: [Double(position), sibling])
            }
        }
    }

    // MARK: - Trash

    /// Soft-deletes the page and its whole subtree with one shared timestamp.
    public func moveToTrash(id: String, now: Date = .now) throws {
        try writer.write { db in
            try db.execute(
                sql: "\(Self.subtreeCTE) UPDATE document SET deletedAt = ? WHERE id IN (SELECT id FROM sub) AND deletedAt IS NULL",
                arguments: [id, now])
        }
    }

    /// Restores the page and the descendants trashed along with it. If its parent is still in the trash,
    /// the page comes back at the top level rather than staying hidden under a deleted parent.
    public func restore(id: String) throws {
        try writer.write { db in
            guard let record = try DocumentRecord.fetchOne(db, key: id), let deletedAt = record.deletedAt else { return }
            try db.execute(
                sql: "\(Self.subtreeCTE) UPDATE document SET deletedAt = NULL WHERE id IN (SELECT id FROM sub) AND deletedAt = ?",
                arguments: [id, deletedAt])
            if let parentId = record.parentId,
                try Bool.fetchOne(db, sql: "SELECT deletedAt IS NOT NULL FROM document WHERE id = ?", arguments: [parentId]) == true
            {
                let last = try Double.fetchOne(db, sql: "SELECT MAX(sortKey) FROM document WHERE parentId IS NULL") ?? -1
                try db.execute(sql: "UPDATE document SET parentId = NULL, sortKey = ? WHERE id = ?", arguments: [last + 1, id])
            }
        }
    }

    /// Hard-deletes the page and its subtree (children go via ON DELETE CASCADE).
    public func deletePermanently(id: String) throws {
        _ = try writer.write { try DocumentRecord.deleteOne($0, key: id) }
    }

    public func emptyTrash() throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM document WHERE deletedAt IS NOT NULL")
        }
    }

    // MARK: - Search

    /// Quick-switcher search over live pages, best first:
    /// 1. fuzzy title matches (also against pinyin, so "lxt" finds 路线图),
    /// 2. body/title full-text matches (trigram FTS for 3+ characters, LIKE below that).
    public func search(_ query: String, limit: Int = 30) throws -> [SearchHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return try writer.read { db in
            var hits: [SearchHit] = []
            var seen = Set<String>()
            for hit in try Self.titleMatches(db, q) where seen.insert(hit.id).inserted { hits.append(hit) }
            for hit in try Self.textMatches(db, q, limit: limit) where seen.insert(hit.id).inserted { hits.append(hit) }
            return Array(hits.prefix(limit))
        }
    }

    private static func titleMatches(_ db: Database, _ q: String) throws -> [SearchHit] {
        let rows = try Row.fetchAll(db, sql: "SELECT id, title, icon, titlePinyin, updatedAt FROM document WHERE deletedAt IS NULL")
        let asciiQuery = q.allSatisfy { $0.isASCII }
        return
            rows
            .compactMap { row -> (SearchHit, Int, Date)? in
                let title: String = row["title"]
                var best = FuzzyMatch.score(q, in: title)
                if asciiQuery, let pinyinScore = FuzzyMatch.score(q, in: row["titlePinyin"] as String) {
                    best = max(best ?? .min, pinyinScore - 1)
                }
                guard let score = best else { return nil }
                return (SearchHit(id: row["id"], title: title, icon: row["icon"], snippet: ""), score, row["updatedAt"])
            }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 > $1.2 }
            .map(\.0)
    }

    private static func textMatches(_ db: Database, _ q: String, limit: Int) throws -> [SearchHit] {
        if q.count >= 3 {
            let phrase = "\"" + q.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT d.id, d.title, d.icon, snippet(documentFts, 1, '', '', '…', 16) AS snippet
                    FROM documentFts JOIN document d ON d.rowid = documentFts.rowid
                    WHERE documentFts MATCH ? AND d.deletedAt IS NULL
                    ORDER BY rank LIMIT ?
                    """, arguments: [phrase, limit])
            return rows.map { row in
                let snippet: String = row["snippet"] ?? ""
                return SearchHit(
                    id: row["id"], title: row["title"], icon: row["icon"],
                    snippet: snippet.localizedCaseInsensitiveContains(q) ? snippet : "")
            }
        }
        let pattern = likePattern(q)
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT id, title, icon, plainText FROM document
                WHERE deletedAt IS NULL AND (title LIKE ? ESCAPE '\\' OR plainText LIKE ? ESCAPE '\\')
                ORDER BY updatedAt DESC LIMIT ?
                """, arguments: [pattern, pattern, limit])
        return rows.map { row in
            SearchHit(id: row["id"], title: row["title"], icon: row["icon"], snippet: excerpt(of: row["plainText"], around: q))
        }
    }

    // MARK: - Helpers

    private static let summaryColumns =
        "document.id, document.parentId, document.title, document.icon, document.updatedAt, document.favoritedAt, document.deletedAt, document.sortKey"

    private static let pagesRequest = SQLRequest<PageSummary>(
        sql: "SELECT \(summaryColumns) FROM document WHERE deletedAt IS NULL ORDER BY sortKey, createdAt, id"
    )

    private static let trashRequest = SQLRequest<PageSummary>(
        sql: """
            SELECT \(summaryColumns) FROM document
            LEFT JOIN document parent ON parent.id = document.parentId
            WHERE document.deletedAt IS NOT NULL
              AND (parent.id IS NULL OR parent.deletedAt IS NULL OR parent.deletedAt != document.deletedAt)
            ORDER BY document.deletedAt DESC, document.id
            """)

    private static let subtreeCTE = """
        WITH RECURSIVE sub(id) AS (SELECT ? UNION ALL SELECT d.id FROM document d JOIN sub ON d.parentId = sub.id)
        """

    private static func likePattern(_ q: String) -> String {
        "%"
            + q.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(
                of: "_", with: "\\_") + "%"
    }

    static func excerpt(of text: String, around query: String, radius: Int = 24) -> String {
        guard let range = text.range(of: query, options: .caseInsensitive) else { return "" }
        let start = text.index(range.lowerBound, offsetBy: -radius, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: radius, limitedBy: text.endIndex) ?? text.endIndex
        let body = text[start..<end].replacingOccurrences(of: "\n", with: " ")
        return (start > text.startIndex ? "…" : "") + body + (end < text.endIndex ? "…" : "")
    }
}
