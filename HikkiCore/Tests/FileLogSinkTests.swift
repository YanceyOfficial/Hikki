import Foundation
import Testing

@testable import HikkiCore

struct FileLogSinkTests {
    private func lines(_ url: URL) throws -> [LogEntry] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n")
            .map { try decoder.decode(LogEntry.self, from: Data($0.utf8)) }
    }

    private func entry(_ message: String) -> LogEntry {
        LogEntry(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000), level: .info, category: "test", message: message, context: ["k": "v"])
    }

    @Test func writesJSONLines() throws {
        let sink = try FileLogSink(directory: try makeTempDirectory())
        sink.write(entry("one"))
        sink.write(entry("two"))
        #expect(try lines(sink.currentFile).map(\.message) == ["one", "two"])
        #expect(try lines(sink.currentFile).first == entry("one"))
    }

    @Test func appendsAcrossInstances() throws {
        let dir = try makeTempDirectory()
        try FileLogSink(directory: dir).write(entry("before relaunch"))
        try FileLogSink(directory: dir).write(entry("after relaunch"))
        #expect(try lines(dir.appending(path: "hikki.log")).map(\.message) == ["before relaunch", "after relaunch"])
    }

    @Test func rotatesAndKeepsAtMostMaxFiles() throws {
        let one = try JSONEncoder.iso.encode(entry("x0")).count + 1
        let sink = try FileLogSink(directory: try makeTempDirectory(), maxBytes: UInt64(one * 2), maxFiles: 3)
        for i in 0..<10 { sink.write(entry("x\(i)")) }
        let files = sink.files
        #expect(files.map(\.lastPathComponent) == ["hikki.log", "hikki.1.log", "hikki.2.log"])
        #expect(try lines(files[0]).map(\.message) == ["x8", "x9"])
        #expect(try lines(files[2]).map(\.message) == ["x4", "x5"])
    }
}

extension JSONEncoder {
    static var iso: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
