import Foundation
import Testing

@testable import HikkiCore

/// A Notion export (Markdown & CSV) made importable: ids off the names, links between its pages as page links,
/// pictures' paths following, databases as tables, parts unpacked — and a zip that isn't Notion's left as it is.
struct NotionExportTests {
    private let trip = "1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d"
    private let packing = "aaaa3c4d5e6f7a8b9c0d1e2f3a4b5c6d"
    private let places = "bbbb3c4d5e6f7a8b9c0d1e2f3a4b5c6d"
    private let row = "cccc3c4d5e6f7a8b9c0d1e2f3a4b5c6d"

    private func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "notion-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Notion's layout: a page's file beside its folder, both named with its id; the database as CSVs (the view's and
    /// `_all`), its rows as pages in its folder.
    private func makeExport(in root: URL) throws -> URL {
        let source = root.appending(path: "export", directoryHint: .isDirectory)
        let tripFolder = source.appending(path: "Trip \(trip)", directoryHint: .isDirectory)
        let placesFolder = tripFolder.appending(path: "Places \(places)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: placesFolder, withIntermediateDirectories: true)
        let tripMD = """
            # Trip

            See [Packing](Trip%20\(trip)/Packing%20\(packing).md) and the [places](Trip%20\(trip)/Places%20\(places).csv).

            ![photo](Trip%20\(trip)/photo%20one.png)

            Also [on notion](https://www.notion.so/me/Packing-\(packing)?pvs=4) and [the web](https://example.com/a.md).

            """
        try tripMD.write(to: source.appending(path: "Trip \(trip).md"), atomically: true, encoding: .utf8)
        try "# Packing\n\nSocks.\n".write(to: tripFolder.appending(path: "Packing \(packing).md"), atomically: true, encoding: .utf8)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: tripFolder.appending(path: "photo one.png"))
        try "Name,Visited\nKyoto,Yes\n".write(to: tripFolder.appending(path: "Places \(places).csv"), atomically: true, encoding: .utf8)
        try "Name,Visited,Note\nKyoto,Yes,\"Rain, then sun\"\nNara,No,\"Deer\nEverywhere\"\n".write(
            to: tripFolder.appending(path: "Places \(places)_all.csv"), atomically: true, encoding: .utf8)
        try "# Kyoto\n\nTemples.\n".write(to: placesFolder.appending(path: "Kyoto \(row).md"), atomically: true, encoding: .utf8)
        let zip = root.appending(path: "Export.zip")
        try Self.zipFolder(source, to: zip)
        return zip
    }

    /// A stored zip of a folder's files (paths relative to it), as Notion's export would hold them.
    static func zipFolder(_ folder: URL, to zip: URL) throws {
        var files: [(path: String, data: Data)] = []
        let base = folder.standardizedFileURL.path + "/"
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isDirectoryKey])
        while let url = enumerator?.nextObject() as? URL {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true else { continue }
            let path = String(url.standardizedFileURL.path.dropFirst(base.count))
            files.append((path, try Data(contentsOf: url)))
        }
        try ZipArchive.stored(files.sorted { $0.path < $1.path }).write(to: zip)
    }

    @Test func namesLoseTheirIdsAndDocumentsKeepThemAsStamps() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try NotionExport.unpack(try makeExport(in: root), into: root)
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: folder.appending(path: "Trip.md").path))
        #expect(fm.fileExists(atPath: folder.appending(path: "Trip/Packing.md").path))
        #expect(fm.fileExists(atPath: folder.appending(path: "Trip/photo one.png").path))
        #expect(fm.fileExists(atPath: folder.appending(path: "Trip/Places.md").path))
        #expect(fm.fileExists(atPath: folder.appending(path: "Trip/Places/Kyoto.md").path))
        #expect(!fm.fileExists(atPath: folder.appending(path: "Trip \(trip).md").path))
        #expect(try fm.contentsOfDirectory(atPath: folder.appending(path: "Trip").path).filter { $0.hasSuffix(".csv") }.isEmpty)

        let tripText = try String(contentsOf: folder.appending(path: "Trip.md"), encoding: .utf8)
        #expect(TransferStamp.read(tripText, format: .markdown).id == trip)
        // Links to the export's pages become page links under their ids; a picture's path follows the renames.
        #expect(tripText.contains("[Packing](hikki://page/\(packing))"))
        #expect(tripText.contains("[places](hikki://page/\(places))"))
        #expect(tripText.contains("![photo](Trip/photo%20one.png)"))
        #expect(tripText.contains("[on notion](hikki://page/\(packing))"))
        #expect(tripText.contains("[the web](https://example.com/a.md)"))
        #expect(
            TransferStamp.read(try String(contentsOf: folder.appending(path: "Trip/Packing.md"), encoding: .utf8), format: .markdown).id
                == packing)
    }

    @Test func aDatabaseBecomesATableWithEveryRowAndItsRowsAsSubpages() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try NotionExport.unpack(try makeExport(in: root), into: root)
        let table = try String(contentsOf: folder.appending(path: "Trip/Places.md"), encoding: .utf8)
        #expect(TransferStamp.read(table, format: .markdown).id == places)
        let body = TransferStamp.stripFrontMatter(table)
        #expect(body.hasPrefix("# Places\n\n| Name | Visited | Note |\n| --- | --- | --- |\n"))
        #expect(body.contains("| Kyoto | Yes | Rain, then sun |"))
        #expect(body.contains("| Nara | No | Deer Everywhere |"))

        // The import's plan: Trip, under it Packing and Places, under Places its row — each with Notion's id.
        let plan = WorkspaceImport.plan([root.appending(path: "Export.zip")])
        #expect(plan.skipped.isEmpty)
        #expect(plan.temporaryFolders.count == 1)
        let names = plan.items.map(\.name)
        #expect(names == ["Trip", "Packing", "Places", "Kyoto"])
        #expect(plan.items.map(\.pageID) == [trip, packing, places, row])
        #expect(plan.items.map(\.parent) == [nil, 0, 0, 2])
        try? FileManager.default.removeItem(at: plan.temporaryFolders[0])
    }

    @Test func partsInsideTheExportAreUnpackedToo() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let part = try makeExport(in: root)
        let outer = root.appending(path: "outer", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: outer, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: part, to: outer.appending(path: "Part-1.zip"))
        let zip = root.appending(path: "Big.zip")
        try Self.zipFolder(outer, to: zip)
        let folder = try NotionExport.unpack(zip, into: root)
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "Trip/Packing.md").path))
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "Part-1.zip").path))
    }

    /// The size limit counts the export and its parts together, and a refused unpack leaves no folder behind.
    @Test func theSizeLimitRunsAcrossTheParts() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let text = Data(String(repeating: "x", count: 600).utf8)
        let part1 = ZipArchive.stored([("a.md", text)])
        let part2 = ZipArchive.stored([("b.md", text)])
        let zip = root.appending(path: "parts.zip")
        try ZipArchive.stored([("Part-1.zip", part1), ("Part-2.zip", part2)]).write(to: zip)
        // Each part alone fits; together they don't.
        #expect(throws: NotionExport.UnpackError.tooLarge) { try NotionExport.unpack(zip, into: root, sizeLimit: 2000) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix("hikki-import-") }.isEmpty)
        let folder = try NotionExport.unpack(zip, into: root, sizeLimit: 10_000)
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "a.md").path))
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "b.md").path))
    }

    @Test func aPlainZipUnpacksAsItIs() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "notes", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try "# Hello\n\nThere.\n".write(to: source.appending(path: "Hello.md"), atomically: true, encoding: .utf8)
        let zip = root.appending(path: "notes.zip")
        try Self.zipFolder(source, to: zip)
        let folder = try NotionExport.unpack(zip, into: root)
        let text = try String(contentsOf: folder.appending(path: "Hello.md"), encoding: .utf8)
        #expect(text == "# Hello\n\nThere.\n")
        #expect(TransferStamp.read(text, format: .markdown).id == nil)
    }

    @Test func entriesOutsideTheFolderAreNeverWritten() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let zip = root.appending(path: "evil.zip")
        let data = Data("x".utf8)
        try ZipArchive.stored([("../escaped.md", data), ("ok.md", data), ("__MACOSX/._ok.md", data)]).write(to: zip)
        let folder = try NotionExport.unpack(zip, into: root)
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "ok.md").path))
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "escaped.md").path))
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "__MACOSX").path))
    }

    @Test func notAZipIsReported() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let fake = root.appending(path: "fake.zip")
        try Data("not a zip".utf8).write(to: fake)
        #expect(throws: NotionExport.UnpackError.unreadable) { try NotionExport.unpack(fake, into: root) }
        let plan = WorkspaceImport.plan([fake])
        #expect(plan.skipped == [.init(name: "fake.zip", reason: .badArchive)])
    }

    @Test func namesAndTablesParse() {
        #expect(NotionExport.cleanName("Trip \(trip).md").name == "Trip.md")
        #expect(NotionExport.cleanName("Trip \(trip).md").id == trip)
        #expect(NotionExport.cleanName("Trip \(trip)").name == "Trip")
        #expect(NotionExport.cleanName("Places \(places)_all.csv").name == "Places.csv")
        #expect(NotionExport.cleanName("Places \(places)_all.csv").isAllRows)
        #expect(NotionExport.cleanName("photo one.png").id == nil)
        #expect(NotionExport.cleanName("photo one.png").name == "photo one.png")
        #expect(NotionExport.parseCSV("a,b\n\"c,d\",\"e\"\"f\"\n") == [["a", "b"], ["c,d", "e\"f"]])
        #expect(NotionExport.markdownTable(csv: "a|b,c\nd,\n") == "| a\\|b | c |\n| --- | --- |\n| d |  |\n")
        #expect(NotionExport.markdownTable(csv: "") == "")
        #expect(NotionExport.resolve("../x/y.md", against: "a/b") == "a/x/y.md")
        #expect(NotionExport.relativePath("a/b/c.png", from: "a/d") == "../b/c.png")
    }
}
