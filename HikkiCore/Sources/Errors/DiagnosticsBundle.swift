import Foundation

/// What a bug report carries (Settings → About → Export diagnostics): the log files, crash and hang reports, and an
/// `about.json` — app info (`AppInfo`) plus counts and non-sensitive settings. Never page content, titles or keys: the
/// logs hold ids and counts only, and `facts` is whatever the app chooses to describe itself with.
public enum DiagnosticsBundle {
    public struct About: Codable, Sendable, Equatable {
        public var app: AppInfo
        public var createdAt: Date
        /// Counts and settings ("pages": "412", "spotlight": "on", "ai.openAI": "key set"…).
        public var facts: [String: String]
    }

    /// The bundle's folder, ready to zip: `logs/`, `reports/`, `about.json`.
    public static func assemble(
        logs: [URL], reports: [URL], app: AppInfo, facts: [String: String], in parent: URL, now: Date = .now
    ) throws -> URL {
        let fm = FileManager.default
        let stamp = now.formatted(
            .iso8601.year().month().day().dateSeparator(.dash).time(includingFractionalSeconds: false).timeSeparator(.omitted))
        let folder = parent.appending(path: "Hikki-diagnostics-\(stamp)", directoryHint: .isDirectory)
        try? fm.removeItem(at: folder)
        for (name, files) in [("logs", logs), ("reports", reports)] {
            let dir = folder.appending(path: name, directoryHint: .isDirectory)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            for file in files where fm.fileExists(atPath: file.path) {
                try fm.copyItem(at: file, to: dir.appending(path: file.lastPathComponent))
            }
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(About(app: app, createdAt: now, facts: facts)).write(to: folder.appending(path: "about.json"))
        return folder
    }

    /// The folder as a .zip next to it (the system's own zipping, through a coordinated read "for uploading").
    public static func zip(_ folder: URL) throws -> URL {
        let target = folder.deletingLastPathComponent().appending(path: folder.lastPathComponent + ".zip")
        try? FileManager.default.removeItem(at: target)
        var coordinationError: NSError?
        var copyError: (any Error)?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinationError) { zipped in
            do {
                try FileManager.default.copyItem(at: zipped, to: target)
            } catch {
                copyError = error
            }
        }
        if let error = coordinationError ?? copyError { throw error }
        return target
    }

    /// Assembled and zipped in a fresh temporary folder.
    public static func make(logs: [URL], reports: [URL], app: AppInfo, facts: [String: String]) throws -> URL {
        let parent = FileManager.default.temporaryDirectory.appending(
            path: "diagnostics-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        return try zip(assemble(logs: logs, reports: reports, app: app, facts: facts, in: parent))
    }
}
