import Foundation
import GRDB
import Testing

@testable import HikkiCore

/// Two devices sharing one workspace folder: what one does to its pages must reach the other, and nothing either
/// writes may be lost on the way.
struct SyncSafetyTests {
    let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    func folder() throws -> PageFiles {
        PageFiles(root: try makeTempDirectory())
    }

    private func body(_ text: String) throws -> JSONValue {
        try JSONValue(
            jsonData: Data(#"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"\#(text)"}]}]}"#.utf8))
    }

    /// A device: its own store and a started sync over the shared folder.
    private func device(_ files: PageFiles, options: WorkspaceSync.Options = .init(fileVersions: NoFileVersions())) throws -> (
        DocumentStore, WorkspaceSync
    ) {
        let store = try DocumentStore.inMemory()
        let sync = WorkspaceSync(store: store, files: files, watchDelay: 60, options: options)
        _ = try sync.start()
        return (store, sync)
    }

    /// Before the app goes to the background its queued file writes are awaited without blocking the main thread:
    /// once `flushed()` returns, the page's file is written.
    @Test func awaitingQueuedWritesSeesThemWritten() async throws {
        let files = try folder()
        let (store, sync) = try device(files)
        try store.create(id: "p", now: t0)
        await sync.flushed()
        #expect(files.presentIDs().contains("p"))
    }

    // MARK: Moves, trash, favorites (metadata that isn't an edit)

    @Test func movesTrashAndFavoritesReachTheOtherDevice() throws {
        let files = try folder()
        let (a, syncA) = try device(files)
        for id in ["p", "c", "t"] { try a.create(id: id, now: t0) }
        syncA.flush()
        let (b, syncB) = try device(files)
        #expect(try b.allDocuments().count == 3)

        try a.move(id: "c", toParent: "p", at: 0)
        try a.setFavorite(true, for: "p")
        try a.moveToTrash(id: "t")
        syncA.flush()
        try syncB.reconcile()
        syncB.flush()

        #expect(try b.document(id: "c")?.parentId == "p")
        #expect(try b.document(id: "p")?.favoritedAt != nil)
        #expect(try b.document(id: "t")?.deletedAt != nil)
        // An edit on B afterwards doesn't undo any of it on A.
        _ = try b.saveContent(Snapshot(docId: "c", content: try body("x"), title: "Child", text: "x", wordCount: 1))
        syncB.flush()
        try syncA.reconcile()
        #expect(try a.document(id: "c")?.parentId == "p")
        #expect(try a.document(id: "c")?.title == "Child")
        #expect(try a.document(id: "t")?.deletedAt != nil)
        syncA.stop()
        syncB.stop()
    }

    @Test func restoringAndReorderingReachTheOtherDevice() throws {
        let files = try folder()
        let (a, syncA) = try device(files)
        for id in ["x", "y", "z"] { try a.create(id: id, now: t0) }
        try a.moveToTrash(id: "z", now: t0)
        syncA.flush()
        let (b, syncB) = try device(files)
        try a.restore(id: "z")
        try a.move(id: "y", toParent: nil, at: 0)
        syncA.flush()
        try syncB.reconcile()
        #expect(try b.document(id: "z")?.deletedAt == nil)
        #expect(try b.pages().map(\.id) == ["y", "x", "z"])
        syncA.stop()
        syncB.stop()
    }

    /// Two devices nest each page under the other at once: neither page may vanish from the tree.
    @Test func aParentCycleFromTwoDevicesIsBroken() throws {
        let files = try folder()
        let (a, syncA) = try device(files)
        for id in ["x", "y"] { try a.create(id: id, now: t0) }
        syncA.flush()
        let (b, syncB) = try device(files)
        syncB.stop()  // B is offline meanwhile
        try a.move(id: "x", toParent: "y", at: 0)
        syncA.flush()
        try b.move(id: "y", toParent: "x", at: 0)

        let reopened = WorkspaceSync(store: b, files: files, watchDelay: 60, options: .init(fileVersions: NoFileVersions()))
        _ = try reopened.start()
        reopened.flush()
        let tree = PageTree(try b.pages())
        #expect(Set(tree.all.map(\.id)) == ["x", "y"])
        syncA.stop()
        reopened.stop()
    }

    // MARK: Remote deletions

    /// A moves C out of P and deletes P. B must not delete C along with P — not even while C's new file is still
    /// on its way.
    @Test func aRemoteParentDeletionSparesAChildMovedOutOfIt() throws {
        let files = try folder()
        let (a, syncA) = try device(files)
        try a.create(id: "P", now: t0)
        try a.create(id: "C", parentId: "P", now: t0)
        syncA.flush()
        let (b, syncB) = try device(files)
        #expect(try b.document(id: "C")?.parentId == "P")

        try a.move(id: "C", toParent: nil, at: 0)
        try a.deletePermanently(id: "P")
        syncA.flush()
        syncA.stop()
        // iCloud delivered P's deletion but C's new file is still a placeholder on B.
        let moved = try Data(contentsOf: try files.url(for: "C"))
        try files.delete("C")
        try Data().write(to: files.directory.appending(path: ".C.json.icloud"))
        try syncB.reconcile()
        syncB.flush()
        #expect(try b.document(id: "C") != nil)
        #expect(try b.document(id: "P") != nil)  // held back until C arrives

        try FileManager.default.removeItem(at: files.directory.appending(path: ".C.json.icloud"))
        try moved.write(to: try files.url(for: "C"))
        try syncB.reconcile()
        syncB.flush()
        #expect(try b.document(id: "C")?.parentId == nil)
        #expect(try b.document(id: "P") == nil)
        #expect(files.exists("C"))
        syncB.stop()
    }

    @Test func aRemoteParentDeletionWithItsChildrenStillDeletesThem() throws {
        let files = try folder()
        let (a, syncA) = try device(files)
        try a.create(id: "P", now: t0)
        try a.create(id: "C", parentId: "P", now: t0)
        try a.create(id: "keep", now: t0)
        try a.create(id: "keep2", now: t0)
        syncA.flush()
        let (b, syncB) = try device(files)
        try a.deletePermanently(id: "P")
        syncA.flush()
        #expect(!files.exists("P") && !files.exists("C"))
        let report = try syncB.reconcile()
        syncB.flush()
        #expect(report.deletedHere == 2 && report.deletionsHeldBack == 0)
        #expect(try b.document(id: "P") == nil)
        #expect(try b.document(id: "C") == nil)
        syncA.stop()
        syncB.stop()
    }

    // MARK: Local saves racing remote imports

    /// The editor saves while a pass is importing the folder's version of the same page: both versions survive.
    @Test func aSaveDuringAnImportIsNotOverwritten() throws {
        let files = try folder()
        let (a, syncA) = try device(files)
        try a.create(id: "n", now: t0)
        _ = try a.saveContent(Snapshot(docId: "n", content: try body("first"), title: "First", text: "first", wordCount: 1), now: t0)
        syncA.flush()
        syncA.stop()

        let b = try DocumentStore.inMemory()
        let edited = t0.addingTimeInterval(120)
        let options = WorkspaceSync.Options(
            fileVersions: NoFileVersions(),
            willReplace: { _ in
                // The editor's debounced save lands between the pass reading the rows and writing the import.
                _ = try? b.saveContent(
                    Snapshot(docId: "n", content: try! body("local"), title: "Local", text: "local", wordCount: 1), now: edited)
            })
        let syncB = WorkspaceSync(store: b, files: files, watchDelay: 60, options: options)
        _ = try syncB.start()
        // Another device's edit arrives.
        _ = try a.saveContent(
            Snapshot(docId: "n", content: try body("remote"), title: "Remote", text: "remote", wordCount: 1),
            now: t0.addingTimeInterval(60))
        try files.write(try PageFile(record: try #require(try a.document(id: "n"))))
        try syncB.reconcile()
        syncB.flush()
        try syncB.reconcile()
        syncB.flush()

        let titles = try b.pages().map(\.title)
        #expect(titles.contains("Local"))
        #expect(titles.contains { $0.hasPrefix("Remote") })
        #expect(try files.read("n")?.title == "Local")
        syncB.stop()
    }

    /// The editor kept unsaved edits instead of reloading a page another device changed; its next save keeps that
    /// version as a conflicted copy instead of overwriting it.
    @Test func aSaveOnTopOfAVersionTheEditorNeverLoadedKeepsThatVersion() throws {
        let store = try DocumentStore.inMemory()
        try store.create(id: "n", now: t0)
        _ = try store.saveContent(Snapshot(docId: "n", content: try body("mine"), title: "Mine", text: "mine", wordCount: 1), now: t0)
        let loaded = try LoadedContent(try #require(try store.document(id: "n")))
        // Metadata changes (here: an icon) don't count — only the title and body the editor shows.
        try store.setIcon("🌸", for: "n", now: t0.addingTimeInterval(30))
        // The folder's version is imported meanwhile.
        var remote = try #require(try store.document(id: "n"))
        remote.title = "Theirs"
        remote.content = #"{"type":"doc","content":[]}"#
        remote.updatedAt = t0.addingTimeInterval(60)
        try store.importPage(remote)

        let next = Snapshot(docId: "n", content: try body("mine, more"), title: "Mine", text: "mine, more", wordCount: 2)
        let saved = try store.saveContent(next, loaded: loaded, now: t0.addingTimeInterval(120))
        #expect(saved)
        #expect(try store.document(id: "n")?.plainText == "mine, more")
        let copies = try store.pages().filter { $0.title.hasPrefix("Theirs (conflicted copy") }
        #expect(copies.count == 1)
        #expect(
            try copies.first.flatMap { try store.document(id: $0.id) }?.contentValue()
                == .object(["type": .string("doc"), "content": .array([])]))

        // Saving on top of its own last save is no conflict; nor is a save with nothing loaded to compare.
        let count = try store.pages().count
        _ = try store.saveContent(
            Snapshot(docId: "n", content: try body("mine, most"), title: "Mine", text: "mine, most", wordCount: 2),
            loaded: LoadedContent(next), now: t0.addingTimeInterval(180))
        try store.setIcon("🌿", for: "n", now: t0.addingTimeInterval(200))
        _ = try store.saveContent(
            Snapshot(docId: "n", content: try body("mine, all"), title: "Mine", text: "mine, all", wordCount: 2),
            loaded: LoadedContent(title: "Mine", content: try body("mine, most")), now: t0.addingTimeInterval(240))
        #expect(try store.pages().count == count)
    }

    // MARK: Write-through

    @Test func oneUnreadableFileDoesNotStopTheRestOfABatch() throws {
        let files = try folder()
        let (store, sync) = try device(files)
        try store.create(id: "a", now: t0)
        try store.create(id: "b", now: t0)
        sync.flush()
        // "a"'s file comes from a newer Hikki.
        var newer = try #require(try files.read("a"))
        newer.format = PageFile.currentFormat + 1
        try PageFiles.encoder.encode(newer).write(to: try files.url(for: "a"))

        try store.move(id: "b", toParent: nil, at: 0)  // renumbers a and b in one transaction
        sync.flush()
        #expect(try files.read("b")?.sortKey == 0)
        #expect(throws: PageFiles.PageFileError.self) { try files.read("a") }  // left alone, not overwritten
        sync.stop()
    }

    @Test func renumberingSiblingsTouchesOnlyRowsWhoseOrderChanged() throws {
        let store = try DocumentStore.inMemory()
        for id in ["a", "b", "c", "d"] { try store.create(id: id, now: t0) }
        let seen = SeenIDs()
        let observation = try store.observePageCommits { changed, _, _ in seen.add(changed.map(\.id)) }
        try store.move(id: "d", toParent: nil, at: 2)  // a b d c
        #expect(seen.all == ["c", "d"])
        observation.cancel()
    }

    @Test func aCancelledCommitObservationHearsNothing() throws {
        let store = try DocumentStore.inMemory()
        let seen = SeenIDs()
        let observation = try store.observePageCommits { changed, _, _ in seen.add(changed.map(\.id)) }
        try store.create(id: "a", now: t0)
        observation.cancel()
        try store.create(id: "b", now: t0)
        #expect(seen.all == ["a"])
    }

    /// Whatever deletes pages for good — emptying the trash, purging it, a parent taking its subpages along — is
    /// reported to `onDeleted`, which takes their history and comments along (AppModel).
    @Test func everyPageDeletedForGoodIsReported() throws {
        let files = try folder()
        let gone = SeenIDs()
        let (store, sync) = try device(files, options: .init(fileVersions: NoFileVersions(), onDeleted: { gone.add($0) }))
        try store.create(id: "p", now: t0)
        try store.create(id: "child", parentId: "p", now: t0)
        try store.create(id: "old", now: t0)
        try store.create(id: "live", now: t0)
        try store.moveToTrash(id: "p", now: t0)
        try store.moveToTrash(id: "old", now: t0.addingTimeInterval(-86_400 * 60))
        sync.flush()
        try store.purgeTrash(deletedBefore: t0.addingTimeInterval(-86_400 * 30))
        sync.flush()
        #expect(gone.all == ["old"])
        try store.emptyTrash()
        sync.flush()
        #expect(gone.all == ["old", "p", "child"])
        #expect(files.exists("live") && !files.exists("child"))
        sync.stop()
    }

    // MARK: Watch passes

    @Test func aPassOverAnUnchangedFolderReadsNoPages() throws {
        let files = try folder()
        let store = try DocumentStore.inMemory()
        for id in ["a", "b"] { try store.create(id: id, now: t0) }
        let sync = WorkspaceSync(store: store, files: files)
        try sync.reconcile()
        #expect(try sync.reconcile(onlyIfFolderChanged: true) == nil)
        var b = try #require(try files.read("b"))
        b.title = "Changed"
        b.updatedAt = t0.addingTimeInterval(5)
        try files.write(b)
        #expect(try sync.reconcile(onlyIfFolderChanged: true)?.imported == 1)
    }

    /// File stamps persist: a relaunch doesn't decode every page file again.
    @Test func aRelaunchReadsOnlyFilesThatChangedSince() throws {
        let files = try folder()
        let store = try DocumentStore.inMemory()
        for id in ["a", "b"] { try store.create(id: id, now: t0) }
        try WorkspaceSync(store: store, files: files).reconcile()
        #expect(Set(try store.fileStamps().keys) == ["a", "b"])
        let listing = try files.scan(known: try store.fileStamps())
        #expect(listing.pages.isEmpty)
    }
}

/// No iCloud conflicts (files outside iCloud).
struct NoFileVersions: FileVersionStore {
    func conflicts(at url: URL) -> [FileConflictVersion] { [] }
    func currentDevice(at url: URL) -> String? { nil }
    func resolveConflicts(at url: URL) throws {}
}

private final class SeenIDs: @unchecked Sendable {
    private let lock = NSLock()
    private var ids: Set<String> = []

    func add(_ new: [String]) { lock.withLock { ids.formUnion(new) } }
    var all: Set<String> { lock.withLock { ids } }
}
