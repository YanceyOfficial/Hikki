import Foundation
import Testing

@testable import HikkiCore

struct PageFileTests {
    private let t0 = Date(timeIntervalSince1970: 1_760_000_000.123)

    private func tempFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "hikki-pages-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func sampleRecord(id: String = "b6c1f3a0-1111-4c2e-9d55-000000000001") throws -> DocumentRecord {
        let body = #"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"日本語 and 😀"}]}]}"#
        return DocumentRecord(
            id: id, title: "旅行計画 · Trip", content: body, plainText: "日本語 and 😀", wordCount: 4, createdAt: t0,
            updatedAt: t0.addingTimeInterval(90), parentId: "parent-1", icon: "🗻", cover: "gradient:ocean",
            favoritedAt: t0.addingTimeInterval(5), deletedAt: nil, sortKey: 2.5, titlePinyin: "")
    }

    @Test func recordRoundTripsThroughAFile() throws {
        let files = PageFiles(root: try tempFolder())
        let record = try sampleRecord()
        try files.write(try PageFile(record: record))
        let back = try #require(try files.read(record.id)).record()
        #expect(back.id == record.id && back.title == record.title && back.icon == record.icon && back.cover == record.cover)
        #expect(back.parentId == record.parentId && back.sortKey == record.sortKey && back.wordCount == 4)
        #expect(back.plainText == record.plainText)
        #expect(abs(back.createdAt.timeIntervalSince(record.createdAt)) < 0.001)  // milliseconds kept
        #expect(back.favoritedAt != nil && back.deletedAt == nil)
        #expect(try back.contentValue() == (try record.contentValue()))
        #expect(back.titlePinyin == Pinyin.searchKey(for: record.title))
    }

    @Test func lockStateRoundTripsAndOlderFilesReadAsUnlocked() throws {
        let files = PageFiles(root: try tempFolder())
        var record = try sampleRecord()
        record.lockedAt = t0.addingTimeInterval(7)
        try files.write(try PageFile(record: record))
        let back = try #require(try files.read(record.id))
        #expect(abs(try #require(back.record().lockedAt).timeIntervalSince(t0.addingTimeInterval(7))) < 0.001)
        // A file written before locking existed has no such key: it reads as unlocked.
        let url = try files.url(for: record.id)
        let older = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").filter { !$0.contains("\"lockedAt\"") }
        try older.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        let legacy = try #require(try files.read(record.id))
        #expect(legacy.lockedAt == nil && legacy.title == record.title)
    }

    @Test func placeholdersAreReportedByThePageTheyStandFor() throws {
        let files = PageFiles(root: try tempFolder())
        try FileManager.default.createDirectory(at: files.directory, withIntermediateDirectories: true)
        try Data().write(to: files.directory.appending(path: ".page-1.json.icloud"))
        let listing = try files.scan()
        // iCloud downloads the page's own URL; the ".icloud" file is only how the folder lists it.
        #expect(listing.placeholders == [files.directory.appending(path: "page-1.json")])
        #expect(listing.present == ["page-1"] && listing.pages.isEmpty)
    }

    @Test func contentIsRealJSONAndOutputIsStable() throws {
        let files = PageFiles(root: try tempFolder())
        let page = try PageFile(record: try sampleRecord())
        try files.write(page)
        let first = try Data(contentsOf: try files.url(for: page.id))
        try files.write(page)
        #expect(try Data(contentsOf: try files.url(for: page.id)) == first)  // same page, same bytes
        let text = String(decoding: first, as: UTF8.self)
        #expect(text.contains(#""content" : {"#))  // an object, not an escaped string
        #expect(text.contains(#""format" : 1"#))
    }

    @Test func neverEditedPagesHaveNoContent() throws {
        var record = try sampleRecord()
        record.content = nil
        let page = try PageFile(record: record)
        #expect(page.content == nil)
        #expect(try page.record().content == nil)
    }

    @Test func listsPagesAndSkipsStrayOrNewerFiles() throws {
        let folder = try tempFolder()
        let files = PageFiles(root: folder)
        try files.write(try PageFile(record: try sampleRecord(id: "a")))
        try files.write(try PageFile(record: try sampleRecord(id: "b")))
        try Data("not json".utf8).write(to: files.directory.appending(path: "stray.json"))
        var future = try PageFile(record: try sampleRecord(id: "c"))
        future.format = PageFile.currentFormat + 1
        try PageFiles.encoder.encode(future).write(to: files.directory.appending(path: "c.json"))
        let (pages, skipped) = try files.readAll()
        #expect(pages.map(\.id) == ["a", "b"])
        #expect(Set(skipped.map(\.lastPathComponent)) == ["stray.json", "c.json"])
        #expect(throws: PageFiles.PageFileError.unsupportedFormat(id: "c", format: PageFile.currentFormat + 1)) { try files.read("c") }
    }

    @Test func ignoresFieldsItDoesNotKnow() throws {
        let files = PageFiles(root: try tempFolder())
        try files.write(try PageFile(record: try sampleRecord(id: "x")))
        let url = try files.url(for: "x")
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        json["addedLater"] = ["anything": true]
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        #expect(try files.read("x")?.title == "旅行計画 · Trip")
    }

    @Test func rejectsIDsThatCouldEscapeTheFolder() {
        let files = PageFiles(root: URL(filePath: "/tmp"))
        for bad in ["", "../x", "a/b", ".hidden"] {
            #expect(throws: PageFiles.PageFileError.invalidID(bad)) { try files.url(for: bad) }
        }
    }
}
