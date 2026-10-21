import Foundation
import Testing

@testable import HikkiCore

struct AssetSweepTests {
    let now = Date(timeIntervalSince1970: 2_000_000_000)

    /// A workspace folder with these assets, each last touched `age` ago.
    private func workspace(_ assets: [String: TimeInterval]) throws -> URL {
        let root = try makeTempDirectory()
        let folder = root.appending(path: "assets")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, age) in assets {
            let file = folder.appending(path: name)
            try Data([1]).write(to: file)
            let date = now.addingTimeInterval(-age)
            try FileManager.default.setAttributes([.creationDate: date, .modificationDate: date], ofItemAtPath: file.path)
        }
        return root
    }

    private func write(_ json: String, to path: String, in root: URL) throws {
        let file = root.appending(path: path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: file)
    }

    private func remaining(_ root: URL) throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "assets").path))
    }

    private let old = AssetSweep.grace + 86_400

    @Test func removesOnlyOldFilesNothingNames() throws {
        let root = try workspace(["page.png": old, "history.png": old, "row.png": old, "unused.png": old, "fresh.png": 60])
        // Page files carry content as JSON (slashes escaped, as JSONEncoder writes them); history the same.
        try write(
            #"{"id":"a","content":{"type":"doc","content":[{"type":"image","attrs":{"src":"hikki-editor:\/\/assets\/page.png"}}]}}"#,
            to: "pages/a.json", in: root)
        try write(#"{"cover":"hikki-editor://assets/history.png"}"#, to: "history/a/20261001T000000.000Z.json", in: root)
        let rows = [#"{"type":"doc","content":[{"type":"drawing","attrs":{"preview":"hikki-editor://assets/row.png"}}]}"#]
        let removed = try #require(AssetSweep.sweep(root: root, rows: rows, now: now))
        #expect(removed == ["unused.png"])
        #expect(try remaining(root) == ["page.png", "history.png", "row.png", "fresh.png"])
    }

    @Test func aNameWithSpacesCountsAsItIsOrPercentEncoded() throws {
        let root = try workspace(["My Plan.pdf": old, "Other Plan.pdf": old])
        try write(#"{"src":"hikki-editor://assets/My%20Plan.pdf"}"#, to: "pages/a.json", in: root)
        try write(#"{"src":"hikki-editor://assets/Other Plan.pdf"}"#, to: "comments/a.json", in: root)
        #expect(AssetSweep.sweep(root: root, rows: [], now: now) == [])
    }

    @Test func aFileStillDownloadingOrUnreadableStopsTheSweep() throws {
        let root = try workspace(["unused.png": old])
        try write("", to: "pages/.b.json.icloud", in: root)
        #expect(AssetSweep.sweep(root: root, rows: [], now: now) == nil)
        try FileManager.default.removeItem(at: root.appending(path: "pages/.b.json.icloud"))
        try write(#"{"id":"b","content":"#, to: "pages/b.json", in: root)
        #expect(AssetSweep.sweep(root: root, rows: [], now: now) == nil)
        #expect(try remaining(root) == ["unused.png"])
    }

    @Test func noAssetsFolderIsNothingToDo() throws {
        #expect(AssetSweep.sweep(root: try makeTempDirectory(), rows: [], now: now) == [])
    }
}
