import Foundation
import Testing

@testable import HikkiCore

struct WorkspaceSyncTests {
    let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    func folder() throws -> PageFiles {
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
        #expect(try store.document(id: "remote")?.plainText.contains("afar") == true)  // stored like any page
        #expect(try store.activity(since: t0.addingTimeInterval(-86_400)).allSatisfy { $0.edits == 0 })  // imports aren't edits
    }

    @Test func importsChildrenAfterTheirParentsWhateverTheFileOrder() throws {
        let files = try folder()
        let other = try DocumentStore.inMemory()
        try other.create(id: "zzz-parent", now: t0)
        try other.create(id: "aaa-child", parentId: "zzz-parent", now: t0)  // sorts before its parent
        try other.create(id: "mmm-grandchild", parentId: "aaa-child", now: t0)
        for id in ["zzz-parent", "aaa-child", "mmm-grandchild"] {
            try files.write(try PageFile(record: try #require(try other.document(id: id))))
        }
        let store = try DocumentStore.inMemory()  // a phone's empty store (foreign keys on)
        let report = try WorkspaceSync(store: store, files: files).reconcile()
        #expect(report.imported == 3)
        #expect(try store.document(id: "aaa-child")?.parentId == "zzz-parent")
        #expect(try store.document(id: "mmm-grandchild")?.parentId == "aaa-child")
    }

    @Test func aChildWaitsForAParentStillDownloadingButAnOrphanLandsAtTheTop() throws {
        let files = try folder()
        let other = try DocumentStore.inMemory()
        try other.create(id: "parent", now: t0)
        try other.create(id: "child", parentId: "parent", now: t0)
        try other.create(id: "orphan", now: t0)
        try files.write(try PageFile(record: try #require(try other.document(id: "child"))))
        // Written by a device whose parent page "gone" never reached this folder.
        var orphan = try PageFile(record: try #require(try other.document(id: "orphan")))
        orphan.parentId = "gone"
        try files.write(orphan)
        try Data().write(to: files.directory.appending(path: ".parent.json.icloud"))  // iCloud hasn't delivered it

        let store = try DocumentStore.inMemory()
        let sync = WorkspaceSync(store: store, files: files)
        let first = try sync.reconcile()
        #expect(first.imported == 1 && first.waitingForDownload == 2)  // the placeholder, and the child behind it
        #expect(try store.document(id: "orphan")?.parentId == nil)
        #expect(try store.document(id: "child") == nil)

        try FileManager.default.removeItem(at: files.directory.appending(path: ".parent.json.icloud"))
        try files.write(try PageFile(record: try #require(try other.document(id: "parent"))))
        let second = try sync.reconcile()
        #expect(second.imported == 2)
        #expect(try store.document(id: "child")?.parentId == "parent")
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

    // MARK: Data-loss guards (security review)

    private func syncedStore(_ ids: [String], files: PageFiles) throws -> (DocumentStore, WorkspaceSync) {
        let store = try DocumentStore.inMemory()
        for id in ids { try store.create(id: id, now: t0) }
        let sync = WorkspaceSync(store: store, files: files)
        try sync.reconcile()
        return (store, sync)
    }

    @Test func iCloudPlaceholdersAreNotDeletions() throws {
        let files = try folder()
        let (store, sync) = try syncedStore(["a", "b", "c", "d"], files: files)
        // iCloud evicted every file ("Optimize Mac Storage"): only placeholders remain.
        for id in ["a", "b", "c", "d"] {
            try files.delete(id)
            try Data().write(to: files.directory.appending(path: ".\(id).json.icloud"))
        }
        let report = try sync.reconcile()
        #expect(report.deletedHere == 0 && report.waitingForDownload == 4)
        #expect(try store.allDocuments().count == 4)
    }

    @Test func unreadableFilesAreNotDeletions() throws {
        let files = try folder()
        let (store, sync) = try syncedStore(["a", "b"], files: files)
        try Data("{ half-downloaded".utf8).write(to: try files.url(for: "a"))  // corrupt / mid-write
        let report = try sync.reconcile()
        #expect(report.deletedHere == 0 && report.skippedFiles == 1)
        #expect(try store.document(id: "a") != nil)
    }

    @Test func aMissingFolderDeletesNothing() throws {
        let files = try folder()
        let (store, sync) = try syncedStore(["a", "b"], files: files)
        try FileManager.default.removeItem(at: files.directory)  // folder gone / not populated yet
        let report = try sync.reconcile()
        #expect(report.deletedHere == 0 && report.deletionsHeldBack == 2)
        #expect(try store.allDocuments().count == 2)
    }

    @Test func massDeletionIsHeldBackButOrdinaryDeletesComeThrough() throws {
        let files = try folder()
        let ids = (1...12).map { "p\($0)" }
        let (store, sync) = try syncedStore(ids, files: files)
        // One page deleted elsewhere: applied.
        try files.delete("p1")
        #expect(try sync.reconcile().deletedHere == 1)
        // Most files vanish at once: held back, nothing lost.
        for id in ids.dropFirst().prefix(8) { try files.delete(id) }
        let report = try sync.reconcile()
        #expect(report.deletedHere == 0 && report.deletionsHeldBack == 8)
        #expect(try store.allDocuments().count == 11)
    }

    @Test func deletingHereKeepsFilesAnotherDeviceJustAdded() throws {
        let files = try folder()
        let store = try DocumentStore.inMemory()
        let sync = WorkspaceSync(store: store, files: files)
        _ = try sync.start()
        try store.create(id: "mine", now: t0)
        sync.flush()
        // Another device adds a page; this store hasn't imported it yet.
        let other = try DocumentStore.inMemory()
        try other.create(id: "theirs", now: t0)
        try files.write(try PageFile(record: try #require(try other.document(id: "theirs"))))

        try store.deletePermanently(id: "mine")
        sync.flush()
        #expect(!files.exists("mine"))
        #expect(files.exists("theirs"))  // not ours to delete
    }

    // MARK: Watching (step 3)

    @Test func aRescanReadsOnlyFilesThatChanged() throws {
        let files = try folder()
        let store = try DocumentStore.inMemory()
        try store.create(id: "a", now: t0)
        try store.create(id: "b", now: t0)
        try WorkspaceSync(store: store, files: files).reconcile()

        let first = try files.scan()
        #expect(first.pages.map(\.id) == ["a", "b"])
        var b = try #require(try files.read("b"))
        b.title = "Changed"
        try files.write(b)
        let second = try files.scan(known: first.stamps)
        #expect(second.pages.map(\.id) == ["b"])  // "a" reused from its stamp
        #expect(second.present == ["a", "b"] && Set(second.stamps.keys) == ["a", "b"])
    }

    @Test func aNewerRowIsWrittenEvenWhenItsFileWasNotReadAgain() throws {
        let files = try folder()
        let store = try DocumentStore.inMemory()
        try store.create(id: "a", now: t0)
        let sync = WorkspaceSync(store: store, files: files)
        try sync.reconcile()
        // Edited here with no write-through running (as if it had failed).
        _ = try store.saveContent(
            Snapshot(docId: "a", content: try body("x"), title: "Later", text: "x", wordCount: 1), now: t0.addingTimeInterval(60))
        #expect(try sync.reconcile().exported == 1)
        #expect(try files.read("a")?.title == "Later")
    }

    @Test func aPassBeforeTheFileIsRemovedDoesNotBringALocalDeleteBack() throws {
        let files = try folder()
        let store = try DocumentStore.inMemory()
        try store.create(id: "gone", now: t0)
        let sync = WorkspaceSync(store: store, files: files)
        try sync.reconcile()
        try store.deletePermanently(id: "gone")  // its file removal hasn't run (no write-through here)

        let report = try sync.reconcile()
        #expect(report.imported == 0)
        #expect(try store.document(id: "gone") == nil)
        #expect(!files.exists("gone"))
    }

    @Test func theWatchedFolderBringsInAnotherDevicesChangeOnItsOwn() async throws {
        let files = try folder()
        let store = try DocumentStore.inMemory()
        try store.create(id: "mine", now: t0)
        let seen = ImportedIDs()
        let sync = WorkspaceSync(store: store, files: files, watchDelay: 0.05) { seen.add($0.importedIDs) }
        _ = try sync.start()

        // Another device edits "mine" and adds "theirs" — nobody calls reconcile().
        var mine = try #require(try files.read("mine"))
        mine.title = "Edited elsewhere"
        mine.updatedAt = t0.addingTimeInterval(60)
        try files.write(mine)
        let other = try DocumentStore.inMemory()
        try other.create(id: "theirs", now: t0)
        try files.write(try PageFile(record: try #require(try other.document(id: "theirs"))))

        for _ in 0..<100 where seen.all.isSuperset(of: ["mine", "theirs"]) == false {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(seen.all.isSuperset(of: ["mine", "theirs"]))
        #expect(try store.document(id: "mine")?.title == "Edited elsewhere")
        #expect(try store.document(id: "theirs") != nil)
        withExtendedLifetime(sync) {}
    }
}

extension WorkspaceSyncTests {
    @Test func watchingStartsOnceTheFirstPageCreatesTheFolder() async throws {
        let files = try folder()  // no pages/ yet: a brand-new workspace
        let store = try DocumentStore.inMemory()
        let seen = ImportedIDs()
        let sync = WorkspaceSync(store: store, files: files, watchDelay: 0.05) { seen.add($0.importedIDs) }
        _ = try sync.start()
        try store.create(id: "first", now: t0)  // write-through creates pages/
        sync.flush()

        let other = try DocumentStore.inMemory()
        try other.create(id: "theirs", now: t0)
        try files.write(try PageFile(record: try #require(try other.document(id: "theirs"))))
        for _ in 0..<100 where !seen.all.contains("theirs") {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(seen.all.contains("theirs"))
        withExtendedLifetime(sync) {}
    }
}

extension WorkspaceSyncTests {
    /// A file still downloading reads as corrupt (skipped); it must be imported once whole, without anyone
    /// calling reconcile() — and without a directory event (the content is overwritten in place).
    @Test func filesStillDownloadingAreImportedOnALaterPassOnTheirOwn() async throws {
        let files = try folder()
        try FileManager.default.createDirectory(at: files.directory, withIntermediateDirectories: true)
        let late = files.directory.appending(path: "late.json")
        try Data("{\"half".utf8).write(to: late, options: [])

        let store = try DocumentStore.inMemory()
        let seen = ImportedIDs()
        let sync = WorkspaceSync(store: store, files: files, watchDelay: 10, retryDelays: [0.05]) { seen.add($0.importedIDs) }
        let first = try sync.start()
        #expect(first.skippedFiles == 1 && first.imported == 0)

        let other = try DocumentStore.inMemory()
        try other.create(id: "late", now: t0)
        let page = try PageFile(record: try #require(try other.document(id: "late")))
        try PageFiles.encoder.encode(page).write(to: late, options: [])  // in place: no directory event
        for _ in 0..<100 where !seen.all.contains("late") {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(seen.all.contains("late"))
        #expect(try store.document(id: "late") != nil)
        withExtendedLifetime(sync) {}
    }

    @Test func stopEndsWatchingAndWriteThrough() async throws {
        let files = try folder()
        let store = try DocumentStore.inMemory()
        let seen = ImportedIDs()
        let sync = WorkspaceSync(store: store, files: files, watchDelay: 0.05) { seen.add($0.importedIDs) }
        _ = try sync.start()
        try store.create(id: "before", now: t0)
        sync.flush()
        #expect(files.exists("before"))

        sync.stop()
        try store.create(id: "after", now: t0)
        sync.flush()
        #expect(!files.exists("after"))
        let other = try DocumentStore.inMemory()
        try other.create(id: "theirs", now: t0)
        try files.write(try PageFile(record: try #require(try other.document(id: "theirs"))))
        try await Task.sleep(for: .milliseconds(300))
        #expect(!seen.all.contains("theirs"))
        withExtendedLifetime(sync) {}
    }

    /// Moving the workspace to another folder: forgetting the synced marks makes the next pass write every
    /// local page out and import the folder's, instead of taking the folder's missing files for deletions.
    @Test func forgettingSyncedMarksJoinsAnotherFolderWithoutLosingPages() throws {
        let oldFolder = try folder()
        let store = try DocumentStore.inMemory()
        try store.create(id: "local", now: t0)
        try WorkspaceSync(store: store, files: oldFolder).reconcile()

        let newFolder = try folder()
        let other = try DocumentStore.inMemory()
        try other.create(id: "remote", now: t0)
        try newFolder.write(try PageFile(record: try #require(try other.document(id: "remote"))))

        try store.unmarkAllSynced()
        let report = try WorkspaceSync(store: store, files: newFolder).reconcile()
        #expect(report.deletedHere == 0 && report.deletionsHeldBack == 0)
        #expect(report.exported == 1 && report.imported == 1)
        #expect(newFolder.exists("local"))
        #expect(try store.document(id: "remote") != nil)
        #expect(try store.document(id: "local") != nil)
    }
}

/// Collects `importedIDs` from the sync queue's callbacks.
private final class ImportedIDs: @unchecked Sendable {
    private let lock = NSLock()
    private var ids: Set<String> = []

    func add(_ new: [String]) { lock.withLock { ids.formUnion(new) } }
    var all: Set<String> { lock.withLock { ids } }
}
