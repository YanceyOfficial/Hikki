import Darwin
import Foundation
import MetricKit

/// The crash marker's file descriptor, opened at start so a signal handler can write it with `write(2)` alone (the
/// only kind of call that's safe in one).
nonisolated(unsafe) private var crashMarkerFD: Int32 = -1

private func markCrash(_ signal: Int32) {
    if crashMarkerFD >= 0 {
        var byte = UInt8(truncatingIfNeeded: signal)
        _ = write(crashMarkerFD, &byte, 1)
    }
}

/// Local crash collection, no third-party SDK:
/// - MetricKit diagnostic payloads (crashes, hangs, CPU/disk exceptions) are delivered on a later launch
///   and persisted as JSON under `directory` for export.
/// - Uncaught Objective-C exceptions are logged synchronously before the process dies.
/// - A crash (a fatal signal or such an exception) leaves a marker, so the next launch can say so (`pendingCrash`);
///   a plain kill (iOS ending a backgrounded app) leaves none.
public final class CrashReporter: NSObject, MXMetricManagerSubscriber, Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Fatal signals that leave the marker (Swift traps arrive as SIGTRAP / SIGILL).
    static let signals: [Int32] = [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGFPE]

    var markerURL: URL { directory.appending(path: "crash.marker") }
    /// The running app's marker file: empty unless it crashes.
    var runningMarkerURL: URL { directory.appending(path: "crash.marker.running") }

    /// A non-empty running marker is the previous run's crash: it becomes the marker `pendingCrash` reads.
    func promoteMarker() {
        let fm = FileManager.default
        let size = (try? fm.attributesOfItem(atPath: runningMarkerURL.path)[.size] as? Int) ?? 0
        guard size > 0 else { return }
        try? fm.removeItem(at: markerURL)
        try? fm.moveItem(at: runningMarkerURL, to: markerURL)
    }
    private var seenKey: String { "crashReporter.seenReports" }

    public func start() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // The run before wrote a byte into its file only if it crashed: keep that as the marker `pendingCrash` reads,
        // then give this run an empty one.
        if crashMarkerFD < 0 {
            promoteMarker()
            crashMarkerFD = open(runningMarkerURL.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        }
        for signal in Self.signals {
            var action = sigaction()
            action.__sigaction_u.__sa_handler = { signal in
                markCrash(signal)
                // Then die as the signal would have (the handler resets itself first).
                Darwin.signal(signal, SIG_DFL)
                raise(signal)
            }
            action.sa_flags = SA_RESETHAND
            sigaction(signal, &action, nil)
        }
        NSSetUncaughtExceptionHandler { exception in
            markCrash(0)
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

    /// The run before this one crashed (its marker), or a crash report arrived that wasn't seen yet — once: asking
    /// again returns false until the next crash.
    public func pendingCrash(defaults: UserDefaults = .standard) -> Bool {
        let fm = FileManager.default
        var crashed = false
        if fm.fileExists(atPath: markerURL.path) {
            crashed = true
            try? fm.removeItem(at: markerURL)
        }
        let seen = Set(defaults.stringArray(forKey: seenKey) ?? [])
        let crashReports = reports.filter { url in
            guard !seen.contains(url.lastPathComponent), let data = try? Data(contentsOf: url) else { return false }
            return Self.containsCrash(data)
        }
        if !crashReports.isEmpty { crashed = true }
        defaults.set(Array(seen.union(reports.map(\.lastPathComponent))), forKey: seenKey)
        return crashed
    }

    /// Whether a MetricKit payload holds a crash (not just hangs or resource exceptions).
    static func containsCrash(_ json: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
            let crashes = object["crashDiagnostics"] as? [Any]
        else { return false }
        return !crashes.isEmpty
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
