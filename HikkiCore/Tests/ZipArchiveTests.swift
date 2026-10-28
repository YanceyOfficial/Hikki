import Foundation
import Testing

@testable import HikkiCore

struct ZipArchiveTests {
    /// `zip -r -X` on macOS: two deflated Markdown files and a directory entry, Notion-like names.
    private let deflated = """
        UEsDBBQAAAAIAOtRXF1JPHwITAAAAG4AAAAoAAAAVHJpcCAxYTJiM2M0ZDVlNmY3YThiOWMwZDFlMmYzYTRiNWM2ZC5tZFNWCCnK\
        LODiCk5NVYgOSEzOzsxLj9UAiakaGRgmGiUZJ5ukmKaapZknWiRZJhukGKYapRknmiSZJpul6EM1AJUmAgE+pXq5KZp6XABQSwME\
        CgAAAAAA61FcXQAAAAAAAAAAAAAAACYAAABUcmlwIDFhMmIzYzRkNWU2ZjdhOGI5YzBkMWUyZjNhNGI1YzZkL1BLAwQUAAAACADr\
        UVxdByS30BgAAABaAAAAUQAAAFRyaXAgMWEyYjNjNGQ1ZTZmN2E4YjljMGQxZTJmM2E0YjVjNmQvUGFja2luZyBhYWFhM2M0ZDVl\
        NmY3YThiOWMwZDFlMmYzYTRiNWM2ZC5tZFNWCEhMzs7MS+fiCs5Pzi5WKKYOqccFAFBLAQIeAxQAAAAIAOtRXF1JPHwITAAAAG4A\
        AAAoAAAAAAAAAAEAAACkgQAAAABUcmlwIDFhMmIzYzRkNWU2ZjdhOGI5YzBkMWUyZjNhNGI1YzZkLm1kUEsBAh4DCgAAAAAA61Fc\
        XQAAAAAAAAAAAAAAACYAAAAAAAAAAAAQAO1BkgAAAFRyaXAgMWEyYjNjNGQ1ZTZmN2E4YjljMGQxZTJmM2E0YjVjNmQvUEsBAh4D\
        FAAAAAgA61FcXQckt9AYAAAAWgAAAFEAAAAAAAAAAQAAAKSB1gAAAFRyaXAgMWEyYjNjNGQ1ZTZmN2E4YjljMGQxZTJmM2E0YjVj\
        NmQvUGFja2luZyBhYWFhM2M0ZDVlNmY3YThiOWMwZDFlMmYzYTRiNWM2ZC5tZFBLBQYAAAAAAwADACkBAABdAQAAAAA=
        """

    private func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "zip-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func readsADeflatedArchiveTheSystemMade() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "deflate.zip")
        try #require(Data(base64Encoded: deflated)).write(to: file)
        let zip = try ZipArchive(url: file)
        let trip = "Trip 1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d"
        #expect(zip.entries.map(\.path) == ["\(trip).md", "\(trip)/", "\(trip)/Packing aaaa3c4d5e6f7a8b9c0d1e2f3a4b5c6d.md"])
        #expect(zip.entries.map(\.isDirectory) == [false, true, false])
        #expect(zip.entries[0].uncompressedSize == 110)
        for entry in zip.entries { try zip.extract(entry, to: root.appending(path: entry.path)) }
        let tripText = try String(contentsOf: root.appending(path: "\(trip).md"), encoding: .utf8)
        #expect(tripText.hasPrefix("# Trip\n\nSee [Packing](Trip%201a2b"))
        let packing = try String(contentsOf: root.appending(path: zip.entries[2].path), encoding: .utf8)
        #expect(packing == "# Packing\n\nSocks socks socks socks socks socks socks socks socks socks socks socks socks.\n")
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: root.appending(path: trip).path, isDirectory: &isDirectory) && isDirectory.boolValue)
    }

    @Test func storedArchivesRoundTrip() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "stored.zip")
        let picture = Data((0..<1000).map { UInt8($0 % 251) })
        try ZipArchive.stored([("a/b.md", Data("# B\n".utf8)), ("a/photo.png", picture), ("über.md", Data("ü".utf8))]).write(to: file)
        let zip = try ZipArchive(url: file)
        #expect(zip.entries.map(\.path) == ["a/b.md", "a/photo.png", "über.md"])
        for entry in zip.entries { try zip.extract(entry, to: root.appending(path: entry.path)) }
        #expect(try Data(contentsOf: root.appending(path: "a/photo.png")) == picture)
        #expect(try String(contentsOf: root.appending(path: "über.md"), encoding: .utf8) == "ü")
    }

    @Test func somethingElseIsNotAZip() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "text.zip")
        try Data("just some text, no central directory at all".utf8).write(to: file)
        #expect(throws: ZipArchive.ReadError.notAZip) { try ZipArchive(url: file) }
    }

    /// A zip bomb lies about its size: the entry stops inflating where its header said, and nothing of the rest is
    /// written.
    @Test func anEntryInflatingPastItsHeaderIsRefused() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "liar.zip")
        var data = try #require(Data(base64Encoded: deflated))
        // The first entry's uncompressed size, in its central directory record (offset 24 from the record's start),
        // cut from 110 to 10.
        let record = try #require(data.range(of: Data([0x50, 0x4B, 0x01, 0x02]))?.lowerBound)
        data.replaceSubrange(record + 24..<record + 28, with: [10, 0, 0, 0])
        try data.write(to: file)
        let zip = try ZipArchive(url: file)
        #expect(zip.entries[0].uncompressedSize == 10)
        #expect(throws: ZipArchive.ReadError.corrupt) { try zip.extract(zip.entries[0], to: root.appending(path: "out.md")) }
    }

    /// Offsets past the file never read out of bounds: a directory offset beyond the end, a header offset beyond it.
    @Test func offsetsBeyondTheFileAreCorruptNotCrashes() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        var data = ZipArchive.stored([("a.md", Data("x".utf8))])
        // The end record's directory offset (offset 16 in the record) pointed far past the file.
        let eocd = try #require(data.range(of: Data([0x50, 0x4B, 0x05, 0x06]))?.lowerBound)
        var broken = data
        broken.replaceSubrange(eocd + 16..<eocd + 20, with: [0xFF, 0xFF, 0xFF, 0x7F])
        let far = root.appending(path: "far.zip")
        try broken.write(to: far)
        #expect(throws: ZipArchive.ReadError.corrupt) { try ZipArchive(url: far) }
        // A record cut short of its 22 bytes is no record.
        let short = root.appending(path: "short.zip")
        try data.dropLast(4).write(to: short)
        #expect(throws: ZipArchive.ReadError.notAZip) { try ZipArchive(url: short) }
        // The entry's local header offset pointed past the file.
        let directory = try #require(data.range(of: Data([0x50, 0x4B, 0x01, 0x02]))?.lowerBound)
        data.replaceSubrange(directory + 42..<directory + 46, with: [0xFF, 0xFF, 0x00, 0x00])
        let header = root.appending(path: "header.zip")
        try data.write(to: header)
        let zip = try ZipArchive(url: header)
        #expect(throws: ZipArchive.ReadError.corrupt) { try zip.extract(zip.entries[0], to: root.appending(path: "a.md")) }
    }

    @Test func crc32MatchesTheStandard() {
        #expect(ZipArchive.crc32(Data("123456789".utf8)) == 0xCBF4_3926)
        #expect(ZipArchive.crc32(Data()) == 0)
    }
}
