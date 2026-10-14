import Foundation
import Synchronization
import Testing

@testable import HikkiCore

/// iCloud's conflict versions, faked: per file, the other versions, and which files were resolved.
final class FakeFileVersions: FileVersionStore {
    private let state = Mutex<(conflicts: [URL: [FileConflictVersion]], resolved: [URL])>(([:], []))
    let current: String?

    init(current: String? = "This Mac") {
        self.current = current
    }

    func add(_ version: FileConflictVersion, at url: URL) {
        state.withLock { $0.conflicts[url.standardizedFileURL, default: []].append(version) }
    }

    var resolved: [URL] { state.withLock { $0.resolved } }

    func conflicts(at url: URL) -> [FileConflictVersion] {
        state.withLock { $0.conflicts[url.standardizedFileURL] ?? [] }
    }

    func currentDevice(at url: URL) -> String? { current }

    func resolveConflicts(at url: URL) throws {
        state.withLock {
            $0.conflicts[url.standardizedFileURL] = nil
            $0.resolved.append(url.standardizedFileURL)
        }
    }
}

struct ConflictCopyTests {
    let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    func folder() throws -> PageFiles {
        PageFiles(root: try makeTempDirectory())
    }

    private func body(_ text: String) throws -> JSONValue {
        try JSONValue(
            jsonData: Data(#"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"\#(text)"}]}]}"#.utf8))
    }

    /// The page "p" saying `text`, edited at `date`, as a file another device could have written.
    private func pageFile(_ text: String, title: String = "Notes", at date: Date) throws -> PageFile {
        let store = try DocumentStore.inMemory()
        try store.create(id: "p", now: t0)
        try store.saveContent(Snapshot(docId: "p", content: try body(text), title: title, text: text, wordCount: 1), now: date)
        return try PageFile(record: try #require(try store.document(id: "p")))
    }

    private func encoded(_ page: PageFile) throws -> Data {
        try PageFiles.encoder.encode(page)
    }

    private func titles(_ store: DocumentStore) throws -> [String] {
        try store.pages().map(\.title).sorted()
    }

    @Test func theNewestVersionWinsAndEveryOtherBecomesAConflictedCopy() throws {
        let files = try folder()
        let versions = FakeFileVersions(current: "Mac")
        try files.write(try pageFile("mac words", at: t0.addingTimeInterval(10)))
        let url = try files.url(for: "p")
        versions.add(
            FileConflictVersion(
                contents: try encoded(try pageFile("ipad words", at: t0.addingTimeInterval(20))), modified: nil, device: "iPad"),
            at: url)
        versions.add(
            FileConflictVersion(
                contents: try encoded(try pageFile("phone words", at: t0.addingTimeInterval(5))), modified: nil, device: "iPhone"),
            at: url)

        let store = try DocumentStore.inMemory()
        let report = try WorkspaceSync(store: store, files: files, options: .init(fileVersions: versions)).reconcile()
        #expect(report.conflictCopies == 2)
        #expect(try store.document(id: "p")?.plainText == "ipad words")  // the newest edit is the page
        #expect(try files.read("p")?.plainText == "ipad words")  // and the file
        let copies = try store.pages().filter { $0.id != "p" }
        #expect(copies.count == 2)
        #expect(Set(try copies.map { try #require(try store.document(id: $0.id)).plainText }) == ["mac words", "phone words"])
        #expect(copies.allSatisfy { $0.title.hasPrefix("Notes (conflicted copy ") })
        #expect(copies.contains { $0.title.contains("Mac") } && copies.contains { $0.title.contains("iPhone") })
        #expect(versions.resolved == [url.standardizedFileURL])
        // Copies are pages like any other: they have files of their own.
        #expect(copies.allSatisfy { files.exists($0.id) })
    }

    @Test func versionsSayingTheSameThingMakeNoCopy() throws {
        let files = try folder()
        let versions = FakeFileVersions()
        try files.write(try pageFile("same", at: t0.addingTimeInterval(10)))
        versions.add(
            FileConflictVersion(contents: try encoded(try pageFile("same", at: t0.addingTimeInterval(20))), modified: nil, device: "iPad"),
            at: try files.url(for: "p"))
        let store = try DocumentStore.inMemory()
        let report = try WorkspaceSync(store: store, files: files, options: .init(fileVersions: versions)).reconcile()
        #expect(report.conflictCopies == 0)
        #expect(try store.pages().count == 1)
        #expect(versions.resolved.count == 1)
    }

    @Test func unreadableConflictVersionsAreResolvedWithoutACopy() throws {
        let files = try folder()
        let versions = FakeFileVersions()
        try files.write(try pageFile("kept", at: t0))
        versions.add(FileConflictVersion(contents: Data("garbage".utf8), modified: nil, device: nil), at: try files.url(for: "p"))
        let store = try DocumentStore.inMemory()
        _ = try WorkspaceSync(store: store, files: files, options: .init(fileVersions: versions)).reconcile()
        #expect(try titles(store) == ["Notes"])
    }

    @Test func aCopySitsRightAfterItsPageUnderTheSameParent() throws {
        let page = try pageFile("words", at: t0)
        var loser = page
        loser.parentId = "parent"
        loser.favoritedAt = t0
        loser.lockedAt = t0
        let copy = ConflictCopy.make(from: loser, id: "copy", source: "iPad", title: ConflictCopy.defaultTitle)
        #expect(copy.id == "copy" && copy.parentId == "parent" && copy.sortKey == loser.sortKey + 0.5)
        #expect(copy.title == "Notes (conflicted copy iPad)")
        #expect(copy.favoritedAt == nil && copy.lockedAt == nil && copy.content == page.content)
    }

    /// A store and folder in step on page "p" (saying "base" at t0).
    private func synced() throws -> (DocumentStore, PageFiles, WorkspaceSync) {
        let files = try folder()
        let store = try DocumentStore.inMemory()
        try store.create(id: "p", now: t0)
        try store.saveContent(Snapshot(docId: "p", content: try body("base"), title: "Notes", text: "base", wordCount: 1), now: t0)
        let sync = WorkspaceSync(store: store, files: files, options: .init(fileVersions: FakeFileVersions(), device: "This Mac"))
        try sync.reconcile()  // written out; both sides agree on t0
        return (store, files, sync)
    }

    @Test func aPageChangedHereAndInTheFolderSinceTheyAgreedKeepsBoth() throws {
        let (store, files, sync) = try synced()
        // Edited here without reaching the file (the app quit before write-through)…
        try store.saveContent(
            Snapshot(docId: "p", content: try body("edited here"), title: "Notes", text: "edited here", wordCount: 2),
            now: t0.addingTimeInterval(10))
        // …and on another device, later.
        try files.write(try pageFile("edited there", at: t0.addingTimeInterval(20)))
        let report = try sync.reconcile()
        #expect(report.conflictCopies == 1)
        #expect(try store.document(id: "p")?.plainText == "edited there")
        let copy = try #require(try store.pages().first { $0.id != "p" })
        #expect(try store.document(id: copy.id)?.plainText == "edited here")
        #expect(copy.title.contains("This Mac"))
    }

    @Test func whenTheEditHereIsNewerTheFoldersVersionBecomesTheCopy() throws {
        let (store, files, sync) = try synced()
        try files.write(try pageFile("edited there", at: t0.addingTimeInterval(10)))
        try store.saveContent(
            Snapshot(docId: "p", content: try body("edited here"), title: "Notes", text: "edited here", wordCount: 2),
            now: t0.addingTimeInterval(20))
        let report = try sync.reconcile()
        #expect(report.conflictCopies == 1)
        #expect(try store.document(id: "p")?.plainText == "edited here")
        #expect(try files.read("p")?.plainText == "edited here")
        let copy = try #require(try store.pages().first { $0.id != "p" })
        #expect(try store.document(id: copy.id)?.plainText == "edited there")
    }

    @Test func anOrdinaryChangeOnOneSideIsNoConflict() throws {
        let (store, files, sync) = try synced()
        try files.write(try pageFile("edited there", at: t0.addingTimeInterval(10)))
        #expect(try sync.reconcile().conflictCopies == 0)
        #expect(try store.document(id: "p")?.plainText == "edited there")
        try store.saveContent(
            Snapshot(docId: "p", content: try body("then here"), title: "Notes", text: "then here", wordCount: 2),
            now: t0.addingTimeInterval(20))
        #expect(try sync.reconcile().conflictCopies == 0)
        #expect(try files.read("p")?.plainText == "then here")
        #expect(try store.pages().count == 1)
    }

    @Test func aPageReplacedFromTheFolderIsHandedToHistoryFirst() throws {
        let files = try folder()
        let store = try DocumentStore.inMemory()
        try store.create(id: "p", now: t0)
        try store.saveContent(Snapshot(docId: "p", content: try body("old"), title: "Notes", text: "old", wordCount: 1), now: t0)
        let replaced = Mutex<[String]>([])
        let sync = WorkspaceSync(
            store: store, files: files,
            options: .init(fileVersions: FakeFileVersions(), willReplace: { row in replaced.withLock { $0.append(row.plainText) } }))
        try sync.reconcile()
        try files.write(try pageFile("new", at: t0.addingTimeInterval(10)))
        try sync.reconcile()
        #expect(replaced.withLock { $0 } == ["old"])
    }

    @Test func syncBasesFollowWritesAndImports() throws {
        let (store, files, sync) = try synced()
        #expect(try store.syncBases()["p"] == t0)
        try files.write(try pageFile("there", at: t0.addingTimeInterval(10)))
        try sync.reconcile()
        #expect(try store.syncBases()["p"] == t0.addingTimeInterval(10))
    }
}
