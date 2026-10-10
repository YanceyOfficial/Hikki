import Foundation
@testable import HikkiCore
import Testing

struct DocumentStoreTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private func snapshot(_ id: String, _ title: String) -> Snapshot {
        Snapshot(docId: id, content: .object(["type": .string("doc"), "title": .string(title)]), title: title, text: title, wordCount: 1)
    }

    @Test func createsAndListsNewestFirst() throws {
        let store = try DocumentStore.inMemory()
        try store.create(id: "old", now: t0)
        try store.create(id: "new", now: t0.addingTimeInterval(10))
        #expect(try store.summaries().map(\.id) == ["new", "old"])
        #expect(try store.document(id: "old")?.content == nil)
    }

    @Test func saveContentUpdatesEditorColumnsOnly() throws {
        let store = try DocumentStore.inMemory()
        try store.create(id: "a", now: t0)
        let later = t0.addingTimeInterval(60)
        #expect(try store.saveContent(snapshot("a", "Hello"), now: later))
        let doc = try #require(try store.document(id: "a"))
        #expect(doc.title == "Hello")
        #expect(doc.createdAt == t0)
        #expect(doc.updatedAt == later)
        #expect(try doc.contentValue() == snapshot("a", "Hello").content)
    }

    @Test func identicalSaveDoesNotBumpUpdatedAt() throws {
        let store = try DocumentStore.inMemory()
        try store.create(id: "a", now: t0)
        try store.saveContent(snapshot("a", "Hello"), now: t0.addingTimeInterval(1))
        #expect(try store.saveContent(snapshot("a", "Hello"), now: t0.addingTimeInterval(99)))
        #expect(try store.document(id: "a")?.updatedAt == t0.addingTimeInterval(1))
    }

    @Test func saveToDeletedDocumentReportsFalseAndDoesNotResurrect() throws {
        let store = try DocumentStore.inMemory()
        try store.create(id: "a", now: t0)
        try store.delete(id: "a")
        #expect(try store.saveContent(snapshot("a", "late autosave")) == false)
        #expect(try store.document(id: "a") == nil)
    }

    @Test func onDiskStorePersistsAcrossReopen() throws {
        let url = try makeTempDirectory().appending(path: "hikki.sqlite")
        try DocumentStore.onDisk(at: url).create(id: "a", now: t0)
        #expect(try DocumentStore.onDisk(at: url).summaries().map(\.id) == ["a"])
    }

    @Test func observeSummariesEmitsAfterChanges() async throws {
        let store = try DocumentStore.inMemory()
        var iterator = store.observeSummaries().makeAsyncIterator()
        #expect(try await iterator.next() == [])
        try store.create(id: "a", now: t0)
        #expect(try await iterator.next()?.map(\.id) == ["a"])
    }
}
