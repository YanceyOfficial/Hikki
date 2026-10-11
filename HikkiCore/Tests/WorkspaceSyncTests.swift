import Foundation
import Testing

@testable import HikkiCore

struct WorkspaceSyncTests {
    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    private func folder() throws -> PageFiles {
        let url = FileManager.default.temporaryDirectory.appending(path: "hikki-sync-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return PageFiles(root: url)
    }

    private func body(_ text: String) throws -> JSONValue {
        try JSONValue(
            jsonData: Data(#"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"\#(text)"}]}]}"#.utf8))
    }

    @Test func importsFilesTheStoreDoesNotHave() throws {
        let files = try folder()
        let other = try DocumentStore.inMemory()  // "another device"
        try other.create(id: "remote", now: t0)
        _ = try other.saveContent(
            Snapshot(docId: "remote", content: try body("from afar"), title: "Remote", text: "from afar", wordCount: 2), now: t0)
        try files.write(try PageFile(record: try #require(try other.document(id: "remote"))))

        let store = try DocumentStore.inMemory()
        let report = try WorkspaceSync(store: store, files: files).reconcile()
        #expect(report.imported == 1)
        #expect(try store.document(id: "remote")?.title == "Remote")
        #expect(try store.search("afar").map(\.id) == ["remote"])  // indexed like any page
        #expect(try store.activity(since: t0.addingTimeInterval(-86_400)).allSatisfy { $0.edits == 0 })  // imports aren't edits
    }

    @Test func newerSideWinsBothWays() throws {
        let files = try folder()
        let store = try DocumentStore.inMemory()
        try store.create(id: "a", now: t0)
        try store.create(id: "b", now: t0)
        let sync = WorkspaceSync(store: store, files: files)
        try sync.reconcile()  // both written out

        // A newer file for "a" (edited elsewhere), a newer row for "b" (edited here while the folder was away).
        var a = try #require(try files.read("a"))
        a.title = "Edited elsewhere"
        a.updatedAt = t0.addingTimeInterval(60)
        try files.write(a)
        _ = try store.saveContent(
            Snapshot(docId: "b", content: try body("x"), title: "Edited here", text: "x", wordCount: 1), now: t0.addingTimeInterval(60))

        let report = try sync.reconcile()
        #expect(report.imported == 1 && report.exported == 1)
        #expect(try store.document(id: "a")?.title == "Edited elsewhere")
        #expect(try files.read("b")?.title == "Edited here")
    }

    @Test func aMissingFileMeansDeletedElsewhereOnlyIfItWasSynced() throws {
        let files = try folder()
        let store = try DocumentStore.inMemory()
        try store.create(id: "synced", now: t0)
        let sync = WorkspaceSync(store: store, files: files)
        try sync.reconcile()
        try store.create(id: "fresh", now: t0)  // never written (no observer running here)

        try files.delete("synced")  // another device deleted it
        let report = try sync.reconcile()
        #expect(report.deletedHere == 1 && report.exported == 1)
        #expect(try store.document(id: "synced") == nil)
        #expect(files.exists("fresh"))
    }

    @Test func changesAreWrittenThroughAfterStart() throws {
        let files = try folder()
        let store = try DocumentStore.inMemory()
        let sync = WorkspaceSync(store: store, files: files)
        _ = try sync.start()

        try store.create(id: "p", now: t0)
        try store.create(id: "child", parentId: "p", now: t0)
        _ = try store.saveContent(Snapshot(docId: "p", content: try body("hello"), title: "Parent", text: "hello", wordCount: 1), now: t0)
        try store.setIcon("🌸", for: "p", now: t0)
        try store.create(id: "q", now: t0)
        try store.move(id: "q", toParent: nil, at: 0)  // renumbers siblings: several files
        sync.flush()
        #expect(try files.read("p")?.title == "Parent")
        #expect(try files.read("p")?.icon == "🌸")
        #expect(try files.read("q")?.sortKey == 0)
        #expect(try files.read("p")?.sortKey == 1)
        #expect(try files.read("child")?.parentId == "p")

        // Trash is a timestamp in the file; deleting for good removes the files (children cascade too).
        try store.moveToTrash(id: "p", now: t0)
        sync.flush()
        #expect(try files.read("child")?.deletedAt != nil)
        try store.deletePermanently(id: "p")
        sync.flush()
        #expect(!files.exists("p") && !files.exists("child"))
        #expect(files.exists("q"))
    }

    @Test func unchangedPagesAreNotRewritten() throws {
        let files = try folder()
        let store = try DocumentStore.inMemory()
        try store.create(id: "same", now: t0)
        let sync = WorkspaceSync(store: store, files: files)
        try sync.reconcile()
        let url = try files.url(for: "same")
        let before = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        Thread.sleep(forTimeInterval: 1.1)
        try sync.reconcile()
        let after = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        #expect(before == after)
    }
}
