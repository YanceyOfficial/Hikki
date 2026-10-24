import Foundation
import GRDB
import Synchronization

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
    /// A `PageCover` raw value (`gradient:<id>` or an image URL), or nil.
    public var cover: String?
    public var favoritedAt: Date?
    public var deletedAt: Date?
    public var sortKey: Double
    /// Locked pages are read-only in the editor (title, body, icon, cover) until unlocked.
    public var lockedAt: Date? = nil
    /// When anything about the page last changed — an edit, but also a move, reorder, trash, restore or favorite,
    /// which leave `updatedAt` ("Edited") alone. Sync compares this one. nil in rows from before it existed: then
    /// `updatedAt` is the last change.
    public var changedAt: Date? = nil

    public var isFavorite: Bool { favoritedAt != nil }
    public var isLocked: Bool { lockedAt != nil }
    /// The last change of any kind: the later of `changedAt` and `updatedAt` (a writer that predates `changedAt` only
    /// moves `updatedAt`).
    public var lastChange: Date { max(changedAt ?? updatedAt, updatedAt) }

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
    public var lockedAt: Date?
    /// For Home's table (created column, word count column).
    public var createdAt: Date
    public var wordCount: Int
    /// For Home's gallery cards: the stored cover (`gradient:<id>` or an image URL, see `PageCover`), or nil.
    public var cover: String?

    public var isFavorite: Bool { favoritedAt != nil }
    public var isLocked: Bool { lockedAt != nil }

    public init(
        id: String, parentId: String?, title: String, icon: String?, updatedAt: Date, favoritedAt: Date?, deletedAt: Date?,
        sortKey: Double, lockedAt: Date? = nil, createdAt: Date? = nil, wordCount: Int = 0, cover: String? = nil
    ) {
        self.createdAt = createdAt ?? updatedAt
        self.wordCount = wordCount
        self.cover = cover
        self.id = id
        self.parentId = parentId
        self.title = title
        self.icon = icon
        self.updatedAt = updatedAt
        self.favoritedAt = favoritedAt
        self.deletedAt = deletedAt
        self.sortKey = sortKey
        self.lockedAt = lockedAt
    }
}

/// SQLite-backed page store. Tests use the in-memory initializer, which runs the exact same
/// migrations and queries — no separate fake to drift out of sync.
///
/// Write paths are split by owner so a late debounced editor save can never revert a metadata change:
/// `saveContent` writes only editor-owned columns; icon/cover/favorite/lock/trash have their own methods.
public final class DocumentStore: Sendable {
    private let writer: any DatabaseWriter

    public static func onDisk(at url: URL) throws -> DocumentStore {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return try DocumentStore(writer: DatabasePool(path: url.path, configuration: configuration))
    }

    public static func inMemory() throws -> DocumentStore {
        try DocumentStore(writer: DatabaseQueue(configuration: configuration))
    }

    /// Opens the database at `url`; one that can't be opened — corrupt, or left by a build whose schema this one
    /// can't migrate — is moved aside (`<name>.broken-<stamp>` beside it, its -wal / -shm with it) and a fresh one
    /// opened in its place: SQLite is a rebuildable cache of the workspace folder (`WorkspaceSync` fills it from
    /// `pages/` again, and a fresh database holds no sync state, so no page is taken for deleted). `recovered` is what
    /// failed when that happened, nil when the database opened as it was.
    public static func onDiskRecovering(at url: URL) throws -> (store: DocumentStore, recovered: (any Error)?) {
        do {
            return (try onDisk(at: url), nil)
        } catch {
            try setAside(url)
            return (try onDisk(at: url), error)
        }
    }

    /// Renames the database file and the write-ahead log beside it to `<name>.broken-<stamp>`; a missing file is skipped.
    static func setAside(_ url: URL) throws {
        let stamp = Int(Date.now.timeIntervalSince1970)
        for suffix in ["", "-wal", "-shm"] {
            let file = URL(filePath: url.path + suffix)
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            try FileManager.default.moveItem(at: file, to: URL(filePath: url.path + ".broken-\(stamp)" + suffix))
        }
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
            // The pinyin key column of the in-store search; v7 drops it again (the search index derives its own).
            try db.alter(table: "document") { t in
                t.add(column: "titlePinyin", .text).notNull().defaults(to: "")
            }
        }
        migrator.registerMigration("v4-activity") { db in
            // Per-day writing activity on this device (Home's heatmap and chart). Local only, like the index.
            try db.create(table: "activity") { t in
                t.primaryKey("day", .text)  // yyyy-MM-dd, local calendar
                t.column("edits", .integer).notNull().defaults(to: 0)
                t.column("wordsAdded", .integer).notNull().defaults(to: 0)
            }
            // Backfill from what pages remember: a creation and a last edit each count once, and the page's
            // words land on its last-edit day — so Home isn't empty on the first launch after the update.
            for row in try Row.fetchAll(db, sql: "SELECT createdAt, updatedAt, wordCount FROM document WHERE deletedAt IS NULL") {
                let created: Date = row["createdAt"]
                let updated: Date = row["updatedAt"]
                try Self.bumpActivity(db, day: created, edits: 1, words: 0)
                if ActivityDay.key(updated) != ActivityDay.key(created) || (row["wordCount"] as Int) > 0 {
                    try Self.bumpActivity(
                        db, day: updated, edits: ActivityDay.key(updated) == ActivityDay.key(created) ? 0 : 1, words: row["wordCount"])
                }
            }
        }
        migrator.registerMigration("v5-page-file-state") { db in
            // Pages known to have a file in the workspace folder (written or imported). A page in here whose file
            // has gone was deleted on another device; one not in here has simply never been written.
            try db.create(table: "pageFileState") { t in
                t.primaryKey("id", .text)
            }
        }
        migrator.registerMigration("v6-locked") { db in
            try db.alter(table: "document") { t in
                t.add(column: "lockedAt", .datetime)
            }
        }
        migrator.registerMigration("v7-search-index-moved") { db in
            // Search lives in its own index now (HikkiSearch): the FTS table, the triggers that fed it and the
            // pinyin key column go.
            let triggers = try String.fetchAll(
                db, sql: "SELECT name FROM sqlite_master WHERE type = 'trigger' AND sql LIKE '%documentFts%'")
            for trigger in triggers { try db.execute(sql: "DROP TRIGGER IF EXISTS \"\(trigger)\"") }
            try db.execute(sql: "DROP TABLE IF EXISTS documentFts")
            try db.alter(table: "document") { t in
                t.drop(column: "titlePinyin")
            }
        }
        migrator.registerMigration("v8-sync-base") { db in
            // The `updatedAt` row and file last agreed on: a page changed on both sides since then is a conflict
            // (WorkspaceSync keeps the loser as a conflicted copy), not a plain "newer wins".
            try db.alter(table: "pageFileState") { t in
                t.add(column: "baseUpdatedAt", .datetime)
            }
        }
        migrator.registerMigration("v9-changed-at") { db in
            // Moves, reorders, trash and favorites aren't edits (`updatedAt` stays), but other devices must see them:
            // `changedAt` is the time of the last change of any kind, and what sync compares. NULL = `updatedAt`.
            try db.alter(table: "document") { t in
                t.add(column: "changedAt", .datetime)
            }
        }
        migrator.registerMigration("v10-file-stamps") { db in
            // The page file as last seen (modification date, size, the change time it holds), so a launch doesn't
            // decode every file again to find the few that changed. `baseUpdatedAt` now holds the last change
            // (`changedAt`) both sides agreed on; before v9 that was `updatedAt`, which `changedAt` defaults to.
            try db.alter(table: "pageFileState") { t in
                t.add(column: "fileModified", .double)  // seconds since 1970: finer than a stored date
                t.add(column: "fileSize", .integer)
                t.add(column: "fileChangedAt", .datetime)
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
                parentId: parentId, icon: nil, cover: nil, favoritedAt: nil, deletedAt: nil, sortKey: last + 1, changedAt: now
            )
            try record.insert(db)
            return record
        }
    }

    /// Copies a live page (title, icon, cover, body — not its subpages, favorite, lock or trash state) and places
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
            copy.lockedAt = nil
            copy.sortKey = Double(siblings.firstIndex(of: newId) ?? 0)
            copy.changedAt = now
            try copy.insert(db)
            try Self.renumber(db, siblings, now: now)
            return copy
        }
    }

    /// Every page, trashed ones included (exporting the workspace to its folder).
    public func allDocuments() throws -> [DocumentRecord] {
        try writer.read { try DocumentRecord.order(Column("createdAt")).fetchAll($0) }
    }

    /// Live pages whose content holds a date (`dateMention`): what reminders and Home's Upcoming read at launch,
    /// without parsing every page.
    public func pagesWithDates() throws -> [DocumentRecord] {
        try writer.read {
            try DocumentRecord.filter(Column("deletedAt") == nil && Column("content").like("%\"dateMention\"%")).fetchAll($0)
        }
    }

    public func document(id: String) throws -> DocumentRecord? {
        try writer.read { try DocumentRecord.fetchOne($0, key: id) }
    }

    /// Whether a page (live or in the trash) has this id, ignoring case: page files are named by id, and the file
    /// system ignores case, so `ABC` and `abc` would be the same file.
    public func hasDocument(matching id: String) throws -> Bool {
        try writer.read { db in
            try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM document WHERE id = ? COLLATE NOCASE)", arguments: [id]) ?? false
        }
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
    ///
    /// `loaded`: the title and body the editor last loaded or saved. When the page's own have changed since (another
    /// device's version was imported while the editor held unsaved edits), that version is kept as a conflicted copy
    /// beside the page before the editor's replaces it — nothing either side wrote is lost. nil skips the check.
    @discardableResult
    public func saveContent(
        _ snapshot: Snapshot, loaded: LoadedContent? = nil, conflictTitle: ConflictCopy.Title = ConflictCopy.defaultTitle,
        now: Date = .now
    ) throws -> Bool {
        let json = String(decoding: try snapshot.content.jsonData(), as: UTF8.self)
        return try writer.write { db in
            guard let row = try DocumentRecord.fetchOne(db, key: snapshot.docId) else { return false }
            guard row.content != json || row.title != snapshot.title else { return true }
            if let loaded, try !loaded.matches(row) {
                let copy = ConflictCopy.make(
                    from: try PageFile(record: row), source: ConflictCopy.source(device: nil, date: row.updatedAt), title: conflictTitle)
                var record = try copy.record()
                record.changedAt = now
                try record.insert(db)
                Log.warn("page changed under unsaved edits; conflicted copy kept", category: "store", context: ["id": row.id])
            }
            try db.execute(
                sql: """
                    UPDATE document SET title = ?, content = ?, plainText = ?, wordCount = ?, updatedAt = ?, changedAt = ?
                    WHERE id = ?
                    """,
                arguments: [snapshot.title, json, snapshot.text, snapshot.wordCount, now, now, snapshot.docId]
            )
            try Self.bumpActivity(db, day: now, edits: 1, words: max(0, snapshot.wordCount - row.wordCount))
            return true
        }
    }

    // MARK: - Metadata writes

    public func setIcon(_ icon: String?, for id: String, now: Date = .now) throws {
        try writer.write { db in
            try db.execute(
                sql: "UPDATE document SET icon = ?, updatedAt = ?, changedAt = ? WHERE id = ?", arguments: [icon, now, now, id])
        }
    }

    public func setCover(_ cover: String?, for id: String, now: Date = .now) throws {
        try writer.write { db in
            try db.execute(
                sql: "UPDATE document SET cover = ?, updatedAt = ?, changedAt = ? WHERE id = ?", arguments: [cover, now, now, id])
        }
    }

    /// Favoriting isn't an edit: `updatedAt` is left alone (`changedAt` carries it to other devices).
    public func setFavorite(_ favorite: Bool, for id: String, now: Date = .now) throws {
        try writer.write { db in
            try db.execute(
                sql: "UPDATE document SET favoritedAt = ?, changedAt = ? WHERE id = ? AND (favoritedAt IS NULL) = ?",
                arguments: [favorite ? now : nil, now, id, favorite])
        }
    }

    /// Locking is a page property every device must see, so like icon and cover it bumps `updatedAt`
    /// (the workspace folder syncs the newer side).
    public func setLocked(_ locked: Bool, for id: String, now: Date = .now) throws {
        try writer.write { db in
            try db.execute(
                sql: "UPDATE document SET lockedAt = ?, updatedAt = ?, changedAt = ? WHERE id = ?",
                arguments: [locked ? now : nil, now, now, id])
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
    /// Moving isn't an edit: `updatedAt` is left alone (`changedAt` carries it to other devices). Only rows whose
    /// place actually changed are written.
    public func move(id: String, toParent parentId: String?, at index: Int, now: Date = .now) throws {
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
            try db.execute(
                sql: "UPDATE document SET parentId = ?, changedAt = ? WHERE id = ? AND parentId IS NOT ?",
                arguments: [parentId, now, id, parentId])
            try Self.renumber(db, siblings, now: now)
        }
    }

    /// Gives `siblings` the sort keys 0…n, writing only rows whose key changes.
    private static func renumber(_ db: Database, _ siblings: [String], now: Date) throws {
        for (position, sibling) in siblings.enumerated() {
            try db.execute(
                sql: "UPDATE document SET sortKey = ?, changedAt = ? WHERE id = ? AND sortKey IS NOT ?",
                arguments: [Double(position), now, sibling, Double(position)])
        }
    }

    // MARK: - Workspace folder sync (storage option C)

    /// What a committed page change reports: the rows inserted or updated, and whether any row was deleted (the
    /// caller then reconciles by id — foreign-key cascades aren't reported row by row — against `liveIDs`).
    public typealias PageCommitHandler = @Sendable (_ changed: [DocumentRecord], _ deletions: Bool, _ liveIDs: Set<String>?) -> Void

    /// Calls `onCommit` after every committed transaction that changed pages. Every observation shares one
    /// transaction observer, which reads the changed rows once per commit (inside the write, on the writer's thread —
    /// three observers each read the full records, body included, on every autosave) and hands the same records to
    /// each handler. Runs on the database's queue; keep it short and hand real work elsewhere. A commit whose rows
    /// couldn't be read is logged, told to `onError`, and its rows go out with the next commit — the write-through
    /// and the search index never miss a change for good. The observation lasts as long as the database unless cancelled.
    @discardableResult
    public func observePageCommits(
        onError: (@Sendable (any Error) -> Void)? = nil, _ onCommit: @escaping PageCommitHandler
    ) throws -> PageCommitObservation {
        let observer = commitObserver.withLock { slot -> PageCommitObserver in
            if let observer = slot { return observer }
            let observer = PageCommitObserver()
            writer.add(transactionObserver: observer, extent: .databaseLifetime)
            slot = observer
            return observer
        }
        let id = observer.add(onCommit, onError: onError)
        return PageCommitObservation { observer.remove(id) }
    }

    /// The one transaction observer every `observePageCommits` shares (made on the first).
    private let commitObserver = Mutex<PageCommitObserver?>(nil)

    /// Writes a page as it came from its file: no activity bump, no edited-time change.
    public func importPage(_ record: DocumentRecord) throws {
        try writer.write { db in
            try record.save(db)
            try Self.setSyncBase(db, record.id, record.lastChange)
        }
    }

    /// Writes a page as it came from its file, but only while the row is still as the caller saw it: `expected` is
    /// its `lastChange` then (nil: there was no row). A save that landed meanwhile is never overwritten — returns
    /// false, and the next pass finds both sides changed since they agreed (a conflicted copy, nothing lost).
    @discardableResult
    public func importPage(_ record: DocumentRecord, expecting expected: Date?, stamp: PageFiles.Stamp? = nil) throws -> Bool {
        try writer.write { db in
            let row = try Row.fetchOne(
                db, sql: "SELECT updatedAt, changedAt, wordCount FROM document WHERE id = ?", arguments: [record.id])
            let current = row.map { Self.lastChange(updatedAt: $0["updatedAt"], changedAt: $0["changedAt"]) }
            switch (current, expected) {
            case (nil, nil): break
            case (let now?, let then?) where abs(now.timeIntervalSince(then)) < 0.0005: break
            default: return false
            }
            // Writing done on another device counts on the day it was done: Home's "This week" is the workspace's
            // writing, not only this device's (a page from the folder is an edit when its edited time moved on).
            let previous: Date? = row?["updatedAt"]
            if previous.map({ record.updatedAt > $0 }) ?? true {
                let words: Int = row?["wordCount"] ?? 0
                try Self.bumpActivity(db, day: record.updatedAt, edits: 1, words: max(0, record.wordCount - words))
            }
            try record.save(db)
            try Self.setSyncBase(db, record.id, record.lastChange, stamp: stamp)
            return true
        }
    }

    /// A page from an imported page file (Settings → Import), as it was: dates, favorite, lock and body kept, no
    /// activity counted. It goes last among `parentId`'s children.
    public func insertImported(_ page: PageFile, id: String, parentId: String?, now: Date = .now) throws {
        try writer.write { db in
            var record = try page.record()
            record.id = id
            record.parentId = parentId
            record.deletedAt = nil
            record.changedAt = now
            let last =
                try Double.fetchOne(db, sql: "SELECT MAX(sortKey) FROM document WHERE parentId IS ?", arguments: [parentId]) ?? -1
            record.sortKey = last + 1
            try record.insert(db)
        }
    }

    private static func lastChange(updatedAt: Date, changedAt: Date?) -> Date {
        max(changedAt ?? updatedAt, updatedAt)
    }

    /// Every page's parent and last change — what a sync pass compares, without the bodies.
    public func syncHeads() throws -> [String: SyncHead] {
        try writer.read { db in
            var heads: [String: SyncHead] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT id, parentId, updatedAt, changedAt FROM document") {
                heads[row["id"]] = SyncHead(
                    parentId: row["parentId"], lastChange: Self.lastChange(updatedAt: row["updatedAt"], changedAt: row["changedAt"]))
            }
            return heads
        }
    }

    /// Parent loops (two devices nesting pages under each other at once) hide every page in them: each loop is
    /// broken by moving its smallest id to the top level — the same choice on every device. Returns the pages moved.
    @discardableResult
    public func breakParentCycles(now: Date = .now) throws -> [String] {
        try writer.write { db in
            var parent: [String: String] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT id, parentId FROM document WHERE parentId IS NOT NULL") {
                parent[row["id"]] = row["parentId"]
            }
            var moved: [String] = []
            var settled = Set<String>()
            for start in parent.keys.sorted() where !settled.contains(start) {
                var path: [String] = []
                var onPath = Set<String>()
                var cursor: String? = start
                while let id = cursor, !settled.contains(id), onPath.insert(id).inserted {
                    path.append(id)
                    cursor = parent[id]
                }
                if let id = cursor, onPath.contains(id), let index = path.firstIndex(of: id), let breaker = path[index...].min() {
                    let last = try Double.fetchOne(db, sql: "SELECT MAX(sortKey) FROM document WHERE parentId IS NULL") ?? -1
                    try db.execute(
                        sql: "UPDATE document SET parentId = NULL, sortKey = ?, changedAt = ? WHERE id = ?",
                        arguments: [last + 1, now, breaker])
                    parent[breaker] = nil
                    moved.append(breaker)
                }
                settled.formUnion(path)
            }
            if !moved.isEmpty { Log.warn("parent loop broken", category: "store", context: ["count": "\(moved.count)"]) }
            return moved
        }
    }

    public func deletePage(id: String) throws {
        try writer.write { db in
            _ = try DocumentRecord.deleteOne(db, key: id)
            try db.execute(sql: "DELETE FROM pageFileState WHERE id = ?", arguments: [id])
        }
    }

    public func markSynced(_ ids: some Sequence<String>) throws {
        try writer.write { db in
            for id in ids { try db.execute(sql: "INSERT OR IGNORE INTO pageFileState (id) VALUES (?)", arguments: [id]) }
        }
    }

    /// Marks the page synced with its file holding exactly the row as of `changedAt` (its `lastChange`; written or
    /// read just now), and remembers the file's stamp.
    public func markSynced(_ id: String, at changedAt: Date, stamp: PageFiles.Stamp? = nil) throws {
        try writer.write { try Self.setSyncBase($0, id, changedAt, stamp: stamp) }
    }

    /// The page files as last seen, for pages synced with them (a launch reads only files that changed since).
    public func fileStamps() throws -> [String: PageFiles.Stamp] {
        try writer.read { db in
            var stamps: [String: PageFiles.Stamp] = [:]
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT id, fileModified, fileSize, fileChangedAt FROM pageFileState
                    WHERE fileModified IS NOT NULL AND fileSize IS NOT NULL AND fileChangedAt IS NOT NULL
                    """)
            for row in rows {
                stamps[row["id"]] = PageFiles.Stamp(
                    modified: Date(timeIntervalSince1970: row["fileModified"]), size: row["fileSize"], changedAt: row["fileChangedAt"])
            }
            return stamps
        }
    }

    /// Per synced page, the last change (`lastChange`) the row and its file agreed on (absent until a page is next
    /// synced).
    public func syncBases() throws -> [String: Date] {
        try writer.read { db in
            var bases: [String: Date] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT id, baseUpdatedAt FROM pageFileState WHERE baseUpdatedAt IS NOT NULL") {
                bases[row["id"]] = row["baseUpdatedAt"]
            }
            return bases
        }
    }

    private static func setSyncBase(_ db: Database, _ id: String, _ changedAt: Date, stamp: PageFiles.Stamp? = nil) throws {
        try db.execute(
            sql: """
                INSERT INTO pageFileState (id, baseUpdatedAt, fileModified, fileSize, fileChangedAt) VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET baseUpdatedAt = excluded.baseUpdatedAt, fileModified = excluded.fileModified,
                    fileSize = excluded.fileSize, fileChangedAt = excluded.fileChangedAt
                """, arguments: [id, changedAt, stamp?.modified.timeIntervalSince1970, stamp?.size, stamp?.changedAt])
    }

    public func unmarkSynced(_ ids: some Sequence<String>) throws {
        try writer.write { db in
            for id in ids { try db.execute(sql: "DELETE FROM pageFileState WHERE id = ?", arguments: [id]) }
        }
    }

    /// Forgets which pages have files (the workspace moved to another folder): the next reconcile writes every
    /// page out and imports the folder's, instead of taking the new folder's missing files for deletions.
    public func unmarkAllSynced() throws {
        try writer.write { try $0.execute(sql: "DELETE FROM pageFileState") }
    }

    public func syncedIDs() throws -> Set<String> {
        try writer.read { Set(try String.fetchAll($0, sql: "SELECT id FROM pageFileState")) }
    }

    // MARK: - Activity (Home)

    static func bumpActivity(_ db: Database, day: Date, edits: Int, words: Int) throws {
        try db.execute(
            sql: """
                INSERT INTO activity (day, edits, wordsAdded) VALUES (?, ?, ?)
                ON CONFLICT(day) DO UPDATE SET edits = edits + excluded.edits, wordsAdded = wordsAdded + excluded.wordsAdded
                """, arguments: [ActivityDay.key(day), edits, words])
    }

    /// Days with any activity since `start` (inclusive), oldest first.
    public func activity(since start: Date) throws -> [DailyActivity] {
        try writer.read { db in
            try Row.fetchAll(
                db, sql: "SELECT day, edits, wordsAdded FROM activity WHERE day >= ? ORDER BY day",
                arguments: [ActivityDay.key(start)]
            ).compactMap { row in
                ActivityDay.date(row["day"]).map { DailyActivity(day: $0, edits: row["edits"], wordsAdded: row["wordsAdded"]) }
            }
        }
    }

    /// Live pages and the words in them.
    public func stats() throws -> WorkspaceStats {
        try writer.read { db in
            let row = try Row.fetchOne(
                db, sql: "SELECT COUNT(*) AS pages, COALESCE(SUM(wordCount), 0) AS words FROM document WHERE deletedAt IS NULL")
            return WorkspaceStats(pages: row?["pages"] ?? 0, words: row?["words"] ?? 0)
        }
    }

    // MARK: - Trash

    /// Soft-deletes the page and its whole subtree with one shared timestamp.
    public func moveToTrash(id: String, now: Date = .now) throws {
        try writer.write { db in
            try db.execute(
                sql: """
                    \(Self.subtreeCTE) UPDATE document SET deletedAt = ?, changedAt = ? WHERE id IN (SELECT id FROM sub) AND deletedAt IS NULL
                    """,
                arguments: [id, now, now])
        }
    }

    /// Restores the page and the descendants trashed along with it. If its parent is still in the trash,
    /// the page comes back at the top level rather than staying hidden under a deleted parent.
    public func restore(id: String, now: Date = .now) throws {
        try writer.write { db in
            guard let record = try DocumentRecord.fetchOne(db, key: id), let deletedAt = record.deletedAt else { return }
            try db.execute(
                sql: """
                    \(Self.subtreeCTE) UPDATE document SET deletedAt = NULL, changedAt = ? WHERE id IN (SELECT id FROM sub) AND deletedAt = ?
                    """,
                arguments: [id, now, deletedAt])
            if let parentId = record.parentId,
                try Bool.fetchOne(db, sql: "SELECT deletedAt IS NOT NULL FROM document WHERE id = ?", arguments: [parentId]) == true
            {
                let last = try Double.fetchOne(db, sql: "SELECT MAX(sortKey) FROM document WHERE parentId IS NULL") ?? -1
                try db.execute(
                    sql: "UPDATE document SET parentId = NULL, sortKey = ?, changedAt = ? WHERE id = ?", arguments: [last + 1, now, id])
            }
        }
    }

    /// Hard-deletes the page and its subtree (children go via ON DELETE CASCADE).
    public func deletePermanently(id: String) throws {
        _ = try writer.write { try DocumentRecord.deleteOne($0, key: id) }
    }

    /// Deletes for good what has been in the trash since before `cutoff` (Settings → Keep deleted pages); returns how
    /// many pages went. A trashed page's subtree shares its timestamp, so it goes with it.
    @discardableResult
    public func purgeTrash(deletedBefore cutoff: Date) throws -> Int {
        try writer.write { db in
            // Counted first: SQLite's change count leaves out the rows a cascade removes.
            let count =
                try Int.fetchOne(
                    db, sql: "SELECT COUNT(*) FROM document WHERE deletedAt IS NOT NULL AND deletedAt < ?", arguments: [cutoff])
                ?? 0
            try db.execute(sql: "DELETE FROM document WHERE deletedAt IS NOT NULL AND deletedAt < ?", arguments: [cutoff])
            return count
        }
    }

    public func emptyTrash() throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM document WHERE deletedAt IS NOT NULL")
        }
    }

    private static let summaryColumns =
        "document.id, document.parentId, document.title, document.icon, document.updatedAt, document.favoritedAt, document.deletedAt, document.sortKey, document.lockedAt, document.createdAt, document.wordCount, document.cover"

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
}

/// A page's place and last change, as a sync pass compares them.
public struct SyncHead: Equatable, Sendable {
    public var parentId: String?
    public var lastChange: Date
}

/// What the editor last loaded or saved of a page (title and body): a save checks the page still holds it.
public struct LoadedContent: Equatable, Sendable {
    public var title: String
    public var content: JSONValue?

    public init(title: String, content: JSONValue?) {
        self.title = title
        self.content = content
    }

    public init(_ record: DocumentRecord) throws {
        self.init(title: record.title, content: try record.contentValue())
    }

    public init(_ snapshot: Snapshot) {
        self.init(title: snapshot.title, content: snapshot.content)
    }

    func matches(_ record: DocumentRecord) throws -> Bool {
        guard record.title == title else { return false }
        guard let stored = record.content else { return content == nil }
        guard let content else { return false }
        if String(decoding: try content.jsonData(), as: UTF8.self) == stored { return true }
        return try record.contentValue() == content
    }
}

/// A commit observation (`DocumentStore.observePageCommits`); `cancel()` ends it.
public final class PageCommitObservation: Sendable {
    private let onCancel: @Sendable () -> Void

    fileprivate init(onCancel: @escaping @Sendable () -> Void) {
        self.onCancel = onCancel
    }

    public func cancel() { onCancel() }
}

/// Collects page row changes in a transaction and, once it commits, reads the rows once and reports them to every
/// handler (see `observePageCommits`). Rows a commit couldn't read stay noted for the next one.
private final class PageCommitObserver: TransactionObserver, @unchecked Sendable {
    private struct Handler: Sendable {
        let id: UUID
        let onCommit: DocumentStore.PageCommitHandler
        let onError: (@Sendable (any Error) -> Void)?
    }

    private let handlers = Mutex<[Handler]>([])
    // The transaction in progress (the writer's thread only).
    private var changed = Set<Int64>()
    private var deletions = false
    // What an earlier commit couldn't read, reported with the next.
    private var pending = Set<Int64>()
    private var pendingDeletions = false

    func add(_ onCommit: @escaping DocumentStore.PageCommitHandler, onError: (@Sendable (any Error) -> Void)?) -> UUID {
        let id = UUID()
        handlers.withLock { $0.append(Handler(id: id, onCommit: onCommit, onError: onError)) }
        return id
    }

    func remove(_ id: UUID) {
        handlers.withLock { $0.removeAll { $0.id == id } }
    }

    func observes(eventsOfKind eventKind: DatabaseEventKind) -> Bool {
        eventKind.tableName == DocumentRecord.databaseTableName
    }

    func databaseDidChange(with event: DatabaseEvent) {
        if event.kind == .delete { deletions = true } else { changed.insert(event.rowID) }
    }

    func databaseDidCommit(_ db: Database) {
        let rowIDs = changed.union(pending)
        let anyDeletions = deletions || pendingDeletions
        changed = []
        deletions = false
        guard !rowIDs.isEmpty || anyDeletions else { return }
        let current = handlers.withLock { $0 }
        guard !current.isEmpty else {
            pending = []
            pendingDeletions = false
            return
        }
        do {
            let records = try DocumentRecord.filter(Array(rowIDs).contains(Column.rowID)).fetchAll(db)
            let live = anyDeletions ? try Set(String.fetchAll(db, sql: "SELECT id FROM document")) : nil
            pending = []
            pendingDeletions = false
            for handler in current { handler.onCommit(records, anyDeletions, live) }
        } catch {
            pending = rowIDs
            pendingDeletions = anyDeletions
            Log.error(
                "page commit unread: \(error)", category: "store",
                context: ["rows": "\(rowIDs.count)", "deletions": "\(anyDeletions)"])
            for handler in current { handler.onError?(error) }
        }
    }

    func databaseDidRollback(_ db: Database) {
        changed = []
        deletions = false
    }
}
