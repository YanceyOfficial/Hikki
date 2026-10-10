import Foundation
import MetricKit

/// Local crash collection, no third-party SDK:
/// - MetricKit diagnostic payloads (crashes, hangs, CPU/disk exceptions) are delivered on a later launch
///   and persisted as JSON under `directory` for export.
/// - Uncaught Objective-C exceptions are logged synchronously before the process dies.
public final class CrashReporter: NSObject, MXMetricManagerSubscriber, Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func start() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSSetUncaughtExceptionHandler { exception in
            Log.error(
                "uncaught exception: \(exception.name.rawValue): \(exception.reason ?? "")", category: "crash",
                context: [
                    "stack": exception.callStackSymbols.prefix(40).joined(separator: "\n")
                ])
        }
        MXMetricManager.shared.add(self)
        // Payloads delivered while we weren't subscribed yet (e.g. the crash right before this launch).
        didReceive(MXMetricManager.shared.pastDiagnosticPayloads)
    }

    public var reports: [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    public func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            persist(
                payload.jsonRepresentation(),
                end: payload.timeStampEnd,
                summary: [
                    "crashes": String(payload.crashDiagnostics?.count ?? 0),
                    "hangs": String(payload.hangDiagnostics?.count ?? 0),
                    "cpuExceptions": String(payload.cpuExceptionDiagnostics?.count ?? 0),
                    "diskWriteExceptions": String(payload.diskWriteExceptionDiagnostics?.count ?? 0),
                ]
            )
        }
    }

    /// Idempotent per payload end time, so `pastDiagnosticPayloads` re-delivery doesn't duplicate reports.
    @discardableResult
    func persist(_ json: Data, end: Date, summary: [String: String]) -> URL? {
        let stamp = end.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).timeSeparator(.omitted))
        let url = directory.appending(path: "diagnostic-\(stamp).json")
        guard !FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            try json.write(to: url, options: .atomic)
            Log.error("diagnostic payload received", category: "crash", context: summary.merging(["file": url.lastPathComponent]) { $1 })
            return url
        } catch {
            Log.error("failed to persist diagnostic payload: \(error)", category: "crash")
            return nil
        }
    }
}
