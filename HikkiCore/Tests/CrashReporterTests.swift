import Foundation
@testable import HikkiCore
import Testing

struct CrashReporterTests {
    @Test func persistsPayloadOncePerTimestamp() throws {
        let reporter = CrashReporter(directory: try makeTempDirectory())
        let end = Date(timeIntervalSince1970: 1_700_000_000)
        let json = Data(#"{"crashDiagnostics":[]}"#.utf8)
        let url = try #require(reporter.persist(json, end: end, summary: ["crashes": "1"]))
        #expect(try Data(contentsOf: url) == json)
        #expect(reporter.persist(json, end: end, summary: [:]) == nil)
        #expect(reporter.reports == [url])
    }
}
