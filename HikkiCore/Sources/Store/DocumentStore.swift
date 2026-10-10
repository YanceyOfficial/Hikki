import Foundation
import GRDB

public struct DocumentRecord: Codable, Sendable, Equatable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "document"

    public var id: String
    public var title: String
    /// Tiptap JSON, nil for a never-edited document.
    public var content: String?
    public var plainText: String
    public var wordCount: Int
    public var createdAt: Date
    public var updatedAt: Date

    public func contentValue() throws -> JSONValue? {
        try content.map { try JSONValue(jsonData: Data($0.utf8)) }
    }
}

public struct DocumentSummary: Codable, Sendable, Equatable, Identifiable, FetchableRecord {
    public var id: String
    public var title: String
    public var updatedAt: Date
}

/// SQLite-backed document store. Tests use the in-memory initializer, which runs the exact same
/// migrations and queries — no separate fake to drift out of sync.
public final class DocumentStore: Sendable {
    private let writer: any DatabaseWriter

    public static func onDisk(at url: URL) throws -> DocumentStore {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return try DocumentStore(writer: DatabasePool(path: url.path))
    }

    public static func inMemory() throws -> DocumentStore {
        try DocumentStore(writer: DatabaseQueue())
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
        return migrator
    }

    @discardableResult
    public func create(id: String = UUID().uuidString, now: Date = .now) throws -> DocumentRecord {
        let record = DocumentRecord(id: id, title: "", content: nil, plainText: "", wordCount: 0, createdAt: now, updatedAt: now)
        try writer.write { try record.insert($0) }
        return record
    }

    public func document(id: String) throws -> DocumentRecord? {
        try writer.read { try DocumentRecord.fetchOne($0, key: id) }
    }

    public func summaries() throws -> [DocumentSummary] {
        try writer.read { try Self.summaryRequest.fetchAll($0) }
    }

    /// Emits the summary list now and after every committed change.
    public func observeSummaries() -> AsyncValueObservation<[DocumentSummary]> {
        ValueObservation.tracking { try Self.summaryRequest.fetchAll($0) }
            .removeDuplicates()
            .values(in: writer)
    }

    /// Writes only the editor-owned columns. Metadata columns added later (favorite, trashed, …)
    /// must never be touched here, so a late debounced save can't revert them.
    /// Returns false when the document no longer exists (e.g. deleted in another window).
    @discardableResult
    public func saveContent(_ snapshot: Snapshot, now: Date = .now) throws -> Bool {
        let json = String(decoding: try snapshot.content.jsonData(), as: UTF8.self)
        return try writer.write { db in
            try db.execute(
                sql: """
                UPDATE document SET title = ?, content = ?, plainText = ?, wordCount = ?, updatedAt = ?
                WHERE id = ? AND (content IS NOT ? OR title IS NOT ?)
                """,
                arguments: [snapshot.title, json, snapshot.text, snapshot.wordCount, now, snapshot.docId, json, snapshot.title]
            )
            if db.changesCount > 0 { return true }
            return try DocumentRecord.exists(db, key: snapshot.docId)
        }
    }

    public func delete(id: String) throws {
        _ = try writer.write { try DocumentRecord.deleteOne($0, key: id) }
    }

    private static let summaryRequest = SQLRequest<DocumentSummary>(
        sql: "SELECT id, title, updatedAt FROM document ORDER BY updatedAt DESC, id"
    )
}
