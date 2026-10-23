import Foundation
import Testing

@testable import HikkiCore

struct CloudMirrorTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func mirror(_ root: URL) throws -> CloudMirror {
        CloudMirror(root: root, stateURL: try makeTempDirectory().appending(path: "cloud.json"), options: .init(device: "Mac"))
    }

    private func write(_ text: String, _ path: String, in root: URL) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    /// Everything the scan sees goes up, and once the cloud took it, nothing does until it changes.
    private func pushAll(_ mirror: CloudMirror) {
        for change in mirror.localChanges() {
            if case .save(let path) = change, let file = mirror.outgoing(path) { mirror.saved(file, systemFields: nil) }
            if case .delete(let path) = change { mirror.deleted(path) }
        }
    }

    @Test func newChangedAndRemovedFilesGoUp() throws {
        let root = try makeTempDirectory()
        let mirror = try mirror(root)
        try write("a", "pages/a.json", in: root)
        try write("b", "assets/b.png", in: root)
        try write("x", ".DS_Store", in: root)
        try write("x", "pages/c.json.icloud", in: root)
        #expect(Set(mirror.localChanges()) == [.save("pages/a.json"), .save("assets/b.png")])
        pushAll(mirror)
        #expect(mirror.localChanges().isEmpty)

        // The same words written again (an atomic save) aren't a change; new words are.
        try write("b", "assets/b.png", in: root)
        try write("a2", "pages/a.json", in: root)
        #expect(mirror.localChanges() == [.save("pages/a.json")])
        pushAll(mirror)

        try FileManager.default.removeItem(at: root.appending(path: "assets/b.png"))
        #expect(mirror.localChanges() == [.delete("assets/b.png")])
    }

    @Test func theAgreedStateOutlivesTheProcess() throws {
        let root = try makeTempDirectory()
        let state = try makeTempDirectory().appending(path: "cloud.json")
        try write("a", "pages/a.json", in: root)
        pushAll(CloudMirror(root: root, stateURL: state))
        #expect(CloudMirror(root: root, stateURL: state).localChanges().isEmpty)
    }

    @Test func onlyPlainPathsInsideTheFolderSync() {
        #expect(CloudMirror.isSyncable("pages/a.json"))
        #expect(CloudMirror.isSyncable("workspace.json"))
        #expect(!CloudMirror.isSyncable("../outside.json"))
        #expect(!CloudMirror.isSyncable("/etc/hosts"))
        #expect(!CloudMirror.isSyncable("pages/.hidden"))
        #expect(!CloudMirror.isSyncable("pages//a.json"))
        #expect(!CloudMirror.isSyncable("pages/.a.json.icloud"))
    }

    @Test func recordNamesHideThePathAndLeadBackToIt() throws {
        let root = try makeTempDirectory()
        let mirror = try mirror(root)
        try write("a", "pages/secret-title.json", in: root)
        pushAll(mirror)
        let name = CloudMirror.recordName(for: "pages/secret-title.json")
        #expect(name.count == 64 && !name.contains("secret"))
        #expect(mirror.path(forRecordName: name) == "pages/secret-title.json")
    }

    @Test func aFileUnchangedHereTakesTheCloudsVersion() throws {
        let root = try makeTempDirectory()
        let mirror = try mirror(root)
        try write("old", "drawings/library.json", in: root)
        pushAll(mirror)
        let received = try mirror.receive("drawings/library.json", contents: Data("new".utf8), systemFields: Data([1]))
        #expect(received == .init(touched: true, needsPush: false))
        #expect(try String(contentsOf: root.appending(path: "drawings/library.json"), encoding: .utf8) == "new")
        #expect(mirror.localChanges().isEmpty)
        #expect(mirror.systemFields("drawings/library.json") == Data([1]))

        // A file this device never had arrives whole.
        let fresh = try mirror.receive("history/p/1.json", contents: Data("v".utf8), systemFields: nil)
        #expect(fresh.touched && !fresh.needsPush)
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "history/p/1.json").path))
    }

    @Test func aPageChangedOnBothSidesKeepsTheLaterAndCopiesTheOther() throws {
        let root = try makeTempDirectory()
        let mirror = try mirror(root)
        let base = try pageFile("base", at: t0)
        try PageFiles(root: root).write(base)
        pushAll(mirror)

        // Here: edited later. There: edited earlier, with other words.
        try PageFiles(root: root).write(try pageFile("mine", at: t0.addingTimeInterval(120)))
        let theirs = try PageFiles.encoder.encode(try pageFile("theirs", at: t0.addingTimeInterval(60)))
        let received = try mirror.receive("pages/p.json", contents: theirs, systemFields: nil)
        #expect(received == .init(touched: true, needsPush: true))

        let pages = try PageFiles(root: root).readAll().pages
        #expect(pages.count == 2)
        #expect(pages.first { $0.id == "p" }?.plainText == "mine")
        let copy = try #require(pages.first { $0.id != "p" })
        #expect(copy.plainText == "theirs")
        #expect(copy.title.contains("conflicted copy"))
        // Both the winner (over the cloud's version) and the copy go up.
        #expect(Set(mirror.localChanges()) == [.save("pages/p.json"), .save("pages/\(copy.id).json")])
    }

    @Test func aPageChangedOnlyInItsDetailsMakesNoCopy() throws {
        let root = try makeTempDirectory()
        let mirror = try mirror(root)
        try PageFiles(root: root).write(try pageFile("same", at: t0))
        pushAll(mirror)
        var mine = try pageFile("same", at: t0)
        mine.icon = "📘"
        mine.changedAt = t0.addingTimeInterval(10)
        try PageFiles(root: root).write(mine)
        let theirs = try PageFiles.encoder.encode(try pageFile("same", at: t0.addingTimeInterval(5)))
        _ = try mirror.receive("pages/p.json", contents: theirs, systemFields: nil)
        #expect(try PageFiles(root: root).readAll().pages.count == 1)
        #expect(try PageFiles(root: root).read("p")?.icon == "📘")
    }

    @Test func commentsChangedOnBothSidesMerge() throws {
        let here = try makeTempDirectory()
        let there = try makeTempDirectory()
        let mirror = try mirror(here)
        let mine = PageComments(root: here, author: "A", device: "Mac")
        try mine.create(pageId: "p", threadId: "t1", quote: "q", body: "first", now: t0)
        pushAll(mirror)
        let theirs = PageComments(root: there, author: "B", device: "iPhone")
        try theirs.create(pageId: "p", threadId: "t1", quote: "q", body: "first", now: t0)
        try theirs.create(pageId: "p", threadId: "t2", quote: "r", body: "theirs", now: t0.addingTimeInterval(5))
        try mine.create(pageId: "p", threadId: "t3", quote: "s", body: "mine", now: t0.addingTimeInterval(6))

        let cloud = try Data(contentsOf: there.appending(path: "comments/p.json"))
        let received = try mirror.receive("comments/p.json", contents: cloud, systemFields: nil)
        #expect(received.needsPush)
        #expect(Set(try mine.threads(of: "p").map(\.id)) == ["t1", "t2", "t3"])
    }

    @Test func aDeletionTakesTheFileUnlessItChangedHere() throws {
        let root = try makeTempDirectory()
        let mirror = try mirror(root)
        try write("a", "pages/a.json", in: root)
        try write("b", "pages/b.json", in: root)
        pushAll(mirror)

        #expect(try mirror.receiveDeletion("pages/a.json") == .init(touched: true, needsPush: false))
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "pages/a.json").path))

        try write("b, edited", "pages/b.json", in: root)
        #expect(try mirror.receiveDeletion("pages/b.json") == .init(touched: false, needsPush: true))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "pages/b.json").path))
        #expect(mirror.localChanges() == [.save("pages/b.json")])
        #expect(mirror.systemFields("pages/b.json") == nil)
    }

    @Test func aNewAccountSendsEverythingAgain() throws {
        let root = try makeTempDirectory()
        let mirror = try mirror(root)
        try write("a", "pages/a.json", in: root)
        pushAll(mirror)
        mirror.forgetCloud()
        #expect(mirror.localChanges() == [.save("pages/a.json")])
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "pages/a.json").path))
    }

    @Test func theWorkspaceSyncsOnlyWithTheAccountItFirstMet() throws {
        let root = try makeTempDirectory()
        let state = try makeTempDirectory().appending(path: "cloud.json")
        let mirror = CloudMirror(root: root, stateURL: state)
        #expect(mirror.accountAllows("_alice"))
        #expect(mirror.accountAllows("_alice"))
        // Another account — switched to, or signed in after a sign-out — gets nothing, also after a relaunch.
        #expect(!mirror.accountAllows("_bob"))
        #expect(!CloudMirror(root: root, stateURL: state).accountAllows("_bob"))
        // A deleted zone sends everything again, still to the owner.
        mirror.forgetCloud()
        #expect(!mirror.accountAllows("_bob"))
        // Turning iCloud on again hands the workspace to the account in use.
        mirror.releaseAccount()
        #expect(mirror.accountAllows("_bob"))
        #expect(!mirror.accountAllows("_alice"))
    }

    // MARK: -

    private func pageFile(_ text: String, at date: Date) throws -> PageFile {
        let store = try DocumentStore.inMemory()
        try store.create(id: "p", now: t0)
        let body = try JSONValue(
            jsonData: Data(#"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"\#(text)"}]}]}"#.utf8))
        try store.saveContent(Snapshot(docId: "p", content: body, title: "Notes", text: text, wordCount: 1), now: date)
        return try PageFile(record: try #require(try store.document(id: "p")))
    }
}
