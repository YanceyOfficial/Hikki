import Foundation
import Testing

@testable import HikkiCore

struct PageHistoryTests {
    let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    private func body(_ text: String) throws -> JSONValue {
        try JSONValue(
            jsonData: Data(#"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"\#(text)"}]}]}"#.utf8))
    }

    /// A store with one page saying `text`, and a history in a fresh folder.
    private func setUp(_ text: String = "first") throws -> (DocumentStore, PageHistory) {
        let store = try DocumentStore.inMemory()
        try store.create(id: "p", now: t0)
        try store.saveContent(Snapshot(docId: "p", content: try body(text), title: "Page", text: text, wordCount: 1), now: t0)
        return (store, PageHistory(root: try makeTempDirectory(), device: "Test Mac"))
    }

    /// What the editor does on every save: offer the page as it was, then save the edit.
    private func edit(_ store: DocumentStore, _ history: PageHistory, to text: String, at date: Date) throws -> Bool {
        let content = try body(text)
        let kept = try history.recordBeforeEdit(pageID: "p", newTitle: "Page", newContent: content, now: date) {
            try store.document(id: "p")
        }
        try store.saveContent(Snapshot(docId: "p", content: content, title: "Page", text: text, wordCount: 1), now: date)
        return kept
    }

    @Test func oneVersionPerEditingSessionHoldingThePageAsItWas() throws {
        let (store, history) = try setUp()
        #expect(try edit(store, history, to: "second", at: t0.addingTimeInterval(60)))  // a session starts: "first" kept
        #expect(try !edit(store, history, to: "third", at: t0.addingTimeInterval(120)))  // same session
        #expect(try !edit(store, history, to: "fourth", at: t0.addingTimeInterval(500)))
        #expect(try edit(store, history, to: "fifth", at: t0.addingTimeInterval(60 + 600)))  // ten minutes on: "fourth" kept
        let versions = try history.versions(of: "p")
        #expect(versions.map(\.plainText) == ["fourth", "first"])  // newest first
        #expect(versions.allSatisfy { $0.device == "Test Mac" && $0.reason == .edit && $0.title == "Page" })
        #expect(versions.first?.content == (try body("fourth")))
    }

    @Test func savingWithoutAChangeKeepsNothing() throws {
        let (store, history) = try setUp("same")
        #expect(try !edit(store, history, to: "same", at: t0.addingTimeInterval(60)))
        #expect(try history.versions(of: "p").isEmpty)
    }

    @Test func aNewEmptyPageKeepsNothingButStartsItsSession() throws {
        let store = try DocumentStore.inMemory()
        try store.create(id: "p", now: t0)
        let history = PageHistory(root: try makeTempDirectory())
        #expect(try !edit(store, history, to: "typed", at: t0.addingTimeInterval(1)))
        #expect(try !edit(store, history, to: "typed more", at: t0.addingTimeInterval(3)))  // still the first session
        #expect(try history.versions(of: "p").isEmpty)
    }

    @Test func theRecordIsOnlyReadWhenASessionStarts() throws {
        let (store, history) = try setUp()
        _ = try edit(store, history, to: "second", at: t0.addingTimeInterval(60))
        var reads = 0
        try history.recordBeforeEdit(pageID: "p", newTitle: "Page", newContent: try body("x"), now: t0.addingTimeInterval(90)) {
            reads += 1
            return try store.document(id: "p")
        }
        #expect(reads == 0)
    }

    @Test func versionsKeptOnAnotherDeviceCountForTheSession() throws {
        let (store, history) = try setUp()
        let folder = history.files.root
        // Another device kept a version a minute ago (it arrived through the folder).
        let other = PageHistory(root: folder, device: "iPad")
        try other.snapshot(try #require(try store.document(id: "p")), reason: .edit, now: t0.addingTimeInterval(30))
        #expect(try !edit(store, history, to: "second", at: t0.addingTimeInterval(60)))
        #expect(try history.versions(of: "p").map(\.device) == ["iPad"])
    }

    @Test func aSnapshotBeforeRestoreIsKeptAtOnceButNotTwiceForTheSamePage() throws {
        let (store, history) = try setUp()
        let record = try #require(try store.document(id: "p"))
        #expect(try history.snapshot(record, reason: .restore, now: t0.addingTimeInterval(1)))
        #expect(try !history.snapshot(record, reason: .restore, now: t0.addingTimeInterval(2)))
        #expect(try history.versions(of: "p").map(\.reason) == [.restore])
    }

    @Test func versionFilesRoundTripAndSkipWhatTheyCannotRead() throws {
        let (store, history) = try setUp()
        let record = try #require(try store.document(id: "p"))
        try history.snapshot(record, reason: .edit, now: t0)
        let folder = try history.files.directory(for: "p")
        try Data("not json".utf8).write(to: folder.appending(path: "junk.json"))
        var newer = try PageVersion(record: record, savedAt: t0.addingTimeInterval(5), device: nil, reason: .edit)
        newer.format = PageVersion.currentFormat + 1
        try history.files.write(newer)
        let versions = try history.versions(of: "p")
        #expect(versions.count == 1)
        #expect(versions.first?.matches(record) == true)
        #expect(versions.first?.savedAt == t0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).contains("20251009T085320.000Z.json"))
    }

    @Test func pruningKeepsTheLastDayThenOnePerDayForAMonth() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let policy = PageHistoryPolicy()
        let now = t0
        let hour: TimeInterval = 3600
        let recent = [now.addingTimeInterval(-hour), now.addingTimeInterval(-2 * hour), now.addingTimeInterval(-20 * hour)]
        // Three days ago, three times on one day; forty days ago, once.
        let threeDaysAgo = calendar.startOfDay(for: now.addingTimeInterval(-3 * 24 * hour)).addingTimeInterval(10 * hour)
        let thatDay = [threeDaysAgo, threeDaysAgo.addingTimeInterval(hour), threeDaysAgo.addingTimeInterval(2 * hour)]
        let ancient = now.addingTimeInterval(-40 * 24 * hour)
        let expired = Set(policy.expired(recent + thatDay + [ancient], now: now, calendar: calendar))
        #expect(expired == [thatDay[0], thatDay[1], ancient])  // the day's newest stays
    }

    @Test func keepingAVersionPrunesTheOldOnes() throws {
        let (store, history) = try setUp()
        var record = try #require(try store.document(id: "p"))
        let old = t0.addingTimeInterval(-60 * 24 * 3600)
        try history.files.write(try PageVersion(record: record, savedAt: old, device: nil, reason: .edit))
        record.title = "Renamed"
        try history.snapshot(record, reason: .edit, now: t0)
        #expect(try history.files.dates(of: "p") == [t0])
    }

    @Test func aPageReplacedFromAnotherDeviceIsKeptOncePerSession() throws {
        let (store, history) = try setUp()
        let record = try #require(try store.document(id: "p"))
        #expect(try history.recordBeforeReplace(record, now: t0.addingTimeInterval(1)))
        #expect(try !history.recordBeforeReplace(record, now: t0.addingTimeInterval(60)))
        #expect(try history.versions(of: "p").map(\.reason) == [.sync])
    }

    @Test func forgettingAPageRemovesItsHistory() throws {
        let (store, history) = try setUp()
        try history.snapshot(try #require(try store.document(id: "p")), reason: .edit, now: t0)
        try history.forget(pageID: "p")
        #expect(try history.versions(of: "p").isEmpty)
    }

    @Test func pageIDsThatCouldEscapeTheFolderAreRefused() throws {
        let history = PageHistory(root: try makeTempDirectory())
        #expect(throws: PageFiles.PageFileError.self) { try history.versions(of: "../pages") }
    }
}
