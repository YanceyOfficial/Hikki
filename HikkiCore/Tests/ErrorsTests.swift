import Foundation
import Testing

@testable import HikkiCore

struct ErrorCodeTests {
    @Test func everyCodeHasAUniqueNumberInItsArea() {
        let numbers = ErrorCode.allCases.map(\.number)
        #expect(Set(numbers).count == numbers.count)
        #expect(ErrorCode.pageSaveFailed.display == "HK-2001")
        #expect(ErrorCode.pageSaveFailed.area == "pages")
        #expect(ErrorCode.aiRateLimited.area == "ai")
        #expect(ErrorCode(number: 7101) == .unsplashNotConfigured)
        #expect(ErrorCode(number: 42) == nil)
    }

    @Test func anIncidentHasAShortReadableIDAndAReference() {
        let incident = Incident(code: .exportFailed, id: "K3F9QX")
        #expect(incident.reference == "HK-4003 · K3F9QX")
        let id = Incident.newID()
        #expect(id.count == 6)
        #expect(id.allSatisfy { Incident.alphabet.contains($0) })
        #expect(!id.contains("0") && !id.contains("O") && !id.contains("1") && !id.contains("I"))
    }

    @Test func describingAnErrorNamesItsTypeOrDomain() {
        struct Broken: Error {}
        #expect(Incident.describe(Broken()).contains("Broken"))
        let ns = NSError(domain: NSCocoaErrorDomain, code: 4, userInfo: [NSLocalizedDescriptionKey: "gone"])
        #expect(Incident.describe(ns).contains("4"))
    }
}

struct CrashMarkerTests {
    private func reporter() -> (CrashReporter, URL, UserDefaults) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "crash-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: "crash-\(UUID().uuidString)")!
        return (CrashReporter(directory: dir), dir, defaults)
    }

    @Test func aCrashedRunIsReportedOnceOnTheNextLaunch() throws {
        let (reporter, dir, defaults) = reporter()
        defer { try? FileManager.default.removeItem(at: dir) }
        // A run that ended without crashing leaves its running marker empty.
        try Data().write(to: reporter.runningMarkerURL)
        reporter.promoteMarker()
        #expect(!reporter.pendingCrash(defaults: defaults))
        // One that crashed wrote a byte (the signal) into it.
        try Data([6]).write(to: reporter.runningMarkerURL)
        reporter.promoteMarker()
        #expect(reporter.pendingCrash(defaults: defaults))
        #expect(!reporter.pendingCrash(defaults: defaults))
    }

    @Test func aNewMetricKitCrashReportCountsHangsDoNot() throws {
        let (reporter, dir, defaults) = reporter()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(#"{"hangDiagnostics":[{}]}"#.utf8).write(to: dir.appending(path: "diagnostic-1.json"))
        #expect(!reporter.pendingCrash(defaults: defaults))
        try Data(#"{"crashDiagnostics":[{}]}"#.utf8).write(to: dir.appending(path: "diagnostic-2.json"))
        #expect(reporter.pendingCrash(defaults: defaults))
        // Seen: not again.
        #expect(!reporter.pendingCrash(defaults: defaults))
    }
}

struct LogSessionTests {
    @Test func entriesCarryTheSessionAndReadBackNewestFirst() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "log-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try Log.bootstrap(directory: dir)
        Log.info("first", category: "test")
        let incident = Incident.report(.exportFailed, CocoaError(.fileWriteNoPermission), category: "test", context: ["docId": "p"])
        let recent = Log.recent(limit: 2)
        #expect(recent.count == 2)
        #expect(recent[0].message == "exportFailed")
        #expect(recent[0].context?["code"] == "HK-4003")
        #expect(recent[0].context?["incident"] == incident.id)
        #expect(recent[0].context?["docId"] == "p")
        #expect(recent[0].level == .error)
        #expect(recent[1].message == "first")
        #expect(recent.allSatisfy { $0.session == Log.session })
    }
}
