import Foundation
import GRDB
import Testing

@testable import HikkiCore

struct DocumentStoreTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private func snapshot(_ id: String, _ title: String, text: String? = nil) -> Snapshot {
        Snapshot(docId: id, content: .object(["type": .string("doc")]), title: title, text: text ?? title, wordCount: 1)
    }

    // MARK: Basics

    @Test func createsSiblingsInOrderAndChildrenUnderParents() throws {
        let store = try DocumentStore.inMemory()
        try store.create(id: "a", now: t0)
        try store.create(id: "b", now: t0)
        try store.create(id: "a1", parentId: "a", now: t0)
        try store.create(id: "a2", parentId: "a", now: t0)
        let pages = try store.pages()
        #expect(pages.filter { $0.parentId == nil }.map(\.id) == ["a", "b"])
        #expect(pages.filter { $0.parentId == "a" }.map(\.id) == ["a1", "a2"])
    }

    @Test func saveContentUpdatesEditorColumnsOnly() throws {
        let store = try DocumentStore.inMemory()
        try store.create(id: "a", now: t0)
        try store.setIcon("🌊", for: "a", now: t0)
        try store.setFavorite(true, for: "a", now: t0)
        let later = t0.addingTimeInterval(60)
        #expect(try store.saveContent(snapshot("a", "Hello"), now: later))
        let doc = try #require(try store.document(id: "a"))
        #expect(doc.title == "Hello")
        #expect(doc.updatedAt == later)
        #expect(doc.icon == "🌊")
        #expect(doc.isFavorite)
    }

    @Test func identicalSaveDoesNotBumpUpdatedAt() throws {
        let store = try DocumentStore.inMemory()
        try store.create(id: "a", now: t0)
        try store.saveContent(snapshot("a", "Hello"), now: t0.addingTimeInterval(1))
        #expect(try store.saveContent(snapshot("a", "Hello"), now: t0.addingTimeInterval(99)))
        #expect(try store.document(id: "a")?.updatedAt == t0.addingTimeInterval(1))
    }

    @Test func saveToMissingPageReportsFalse() throws {
        let store = try DocumentStore.inMemory()
        #expect(try store.saveContent(snapshot("ghost", "late autosave")) == false)
    }

    // MARK: Metadata

    @Test func favoritingDoesNotCountAsAnEdit() throws {
        let store = try DocumentStore.inMemory()
        try store.create(id: "a", now: t0)
        try store.setFavorite(true, for: "a", now: t0.addingTimeInterval(5))
        let doc = try #require(try store.document(id: "a"))
        #expect(doc.favoritedAt == t0.addingTimeInterval(5))
        #expect(doc.updatedAt == t0)
        try store.setFavorite(false, for: "a")
        #expect(try store.document(id: "a")?.isFavorite == false)
    }

    @Test func lockingIsAPagePropertyThatSurvivesAutosave() throws {
        let store = try DocumentStore.inMemory()
        try store.create(id: "a", now: t0)
        try store.setLocked(true, for: "a", now: t0.addingTimeInterval(5))
        let doc = try #require(try store.document(id: "a"))
        #expect(doc.isLocked && doc.lockedAt == t0.addingTimeInterval(5))
        // Other devices must see a lock, so unlike favoriting it counts as an update for sync.
        #expect(doc.updatedAt == t0.addingTimeInterval(5))
        #expect(try store.pages().first { $0.id == "a" }?.isLocked == true)
        // A late autosave writes editor columns only: it can't unlock the page.
        #expect(try store.saveContent(snapshot("a", "Hello"), now: t0.addingTimeInterval(60)))
        #expect(try store.document(id: "a")?.isLocked == true)
        // A copy starts unlocked, like it starts unfavorited.
        #expect(try store.duplicate(id: "a", newId: "b")?.isLocked == false)
        try store.setLocked(false, for: "a", now: t0.addingTimeInterval(90))
        #expect(try store.document(id: "a")?.isLocked == false)
    }

    @Test func iconAndCoverRoundTrip() throws {
        let store = try DocumentStore.inMemory()
        try store.create(id: "a", now: t0)
        try store.setIcon("👋", for: "a")
        try store.setCover("gradient:dusk", for: "a")
        #expect(try store.document(id: "a")?.icon == "👋")
        #expect(try store.document(id: "a")?.cover == "gradient:dusk")
        try store.setIcon(nil, for: "a")
        #expect(try store.document(id: "a")?.icon == nil)
    }

    @Test func ancestorsRunFromRootToParent() throws {
        let store = try DocumentStore.inMemory()
        try store.create(id: "root", now: t0)
        try store.create(id: "mid", parentId: "root", now: t0)
        try store.create(id: "leaf", parentId: "mid", now: t0)
        #expect(try store.ancestors(of: "leaf").map(\.id) == ["root", "mid"])
        #expect(try store.ancestors(of: "root").isEmpty)
    }

    // MARK: Trash

    @Test func trashingHidesTheWholeSubtreeButListsOnlyItsRoot() throws {
        let store = try DocumentStore.inMemory()
        try store.create(id: "a", now: t0)
        try store.create(id: "a1", parentId: "a", now: t0)
        try store.create(id: "a1x", parentId: "a1", now: t0)
        try store.create(id: "b", now: t0)
        try store.moveToTrash(id: "a", now: t0)
        #expect(try store.pages().map(\.id) == ["b"])
        #expect(try store.trash().map(\.id) == ["a"])
    }

    @Test func childTrashedEarlierStaysListedSeparately() throws {
        let store = try DocumentStore.inMemory()
        try store.create(id: "a", now: t0)
        try store.create(id: "a1", parentId: "a", now: t0)
        try store.moveToTrash(id: "a1", now: t0)
        try store.moveToTrash(id: "a", now: t0.addingTimeInterval(10))
        #expect(Set(try store.trash().map(\.id)) == ["a", "a1"])
        // Restoring the parent must not resurrect the child that was trashed on its own.
        try store.restore(id: "a")
        #expect(try store.pages().map(\.id) == ["a"])
        #expect(try store.trash().map(\.id) == ["a1"])
    }

    @Test func restoringUnderATrashedParentMovesThePageToTheTopLevel() throws {
        let store = try DocumentStore.inMemory()
        try store.create(id: "a", now: t0)
        try store.create(id: "a1", parentId: "a", now: t0)
        try store.moveToTrash(id: "a1", now: t0)
        try store.moveToTrash(id: "a", now: t0.addingTimeInterval(10))
        try store.restore(id: "a1")
        let restored = try #require(try store.pages().first { $0.id == "a1" })
        #expect(restored.parentId == nil)
    }

    @Test func deletePermanentlyRemovesTheSubtree() throws {
        let store = try DocumentStore.inMemory()
        try store.create(id: "a", now: t0)
        try store.create(id: "a1", parentId: "a", now: t0)
        try store.moveToTrash(id: "a", now: t0)
        try store.deletePermanently(id: "a")
        #expect(try store.document(id: "a1") == nil)
        #expect(try store.trash().isEmpty)
    }

    @Test func emptyTrashKeepsLivePages() throws {
        let store = try DocumentStore.inMemory()
        try store.create(id: "a", now: t0)
        try store.create(id: "b", now: t0)
        try store.moveToTrash(id: "a", now: t0)
        try store.emptyTrash()
        #expect(try store.pages().map(\.id) == ["b"])
        #expect(try store.document(id: "a") == nil)
    }

    // MARK: Migration & persistence

    @Test func v7LeavesNoSearchTablesBehindAndPagesStillSave() throws {
        let url = try makeTempDirectory().appending(path: "hikki.sqlite")
        let store = try DocumentStore.onDisk(at: url)
        try store.create(id: "a", now: t0)
        try store.saveContent(snapshot("a", "Roadmap", text: "body"))
        let queue = try DatabaseQueue(path: url.path)
        try queue.read { db in
            #expect(try !db.tableExists("documentFts"))
            let columns = try db.columns(in: "document").map { $0.name }
            #expect(!columns.contains("titlePinyin"))
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sqlite_master WHERE type = 'trigger'") == 0)
        }
    }

    @Test func onDiskStorePersistsAcrossReopen() throws {
        let url = try makeTempDirectory().appending(path: "hikki.sqlite")
        try DocumentStore.onDisk(at: url).create(id: "a", now: t0)
        #expect(try DocumentStore.onDisk(at: url).pages().map(\.id) == ["a"])
    }

    @Test func v2MigrationKeepsV1PagesAndTheirOrder() throws {
        let url = try makeTempDirectory().appending(path: "hikki.sqlite")
        // Build a v1-only database the way the first release wrote it.
        do {
            let queue = try DatabaseQueue(path: url.path)
            var v1 = DatabaseMigrator()
            v1.registerMigration("v1-documents") { db in
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
            try v1.migrate(queue)
            try queue.write { db in
                try db.execute(
                    sql:
                        "INSERT INTO document (id, title, plainText, createdAt, updatedAt) VALUES ('old', 'Older', 'legacy body text', ?, ?)",
                    arguments: [t0, t0])
                try db.execute(
                    sql: "INSERT INTO document (id, title, plainText, createdAt, updatedAt) VALUES ('new', 'Newer', '', ?, ?)",
                    arguments: [t0, t0.addingTimeInterval(9)])
            }
        }
        let store = try DocumentStore.onDisk(at: url)
        #expect(try store.pages().map(\.id) == ["new", "old"])
        #expect(try store.document(id: "old")?.plainText == "legacy body text")
    }

    @Test func observePagesEmitsAfterChanges() async throws {
        let store = try DocumentStore.inMemory()
        var iterator = store.observePages().makeAsyncIterator()
        #expect(try await iterator.next() == [])
        try store.create(id: "a", now: t0)
        #expect(try await iterator.next()?.map(\.id) == ["a"])
    }
}
