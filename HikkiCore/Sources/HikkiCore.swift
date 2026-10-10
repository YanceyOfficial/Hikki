import Foundation

/// Locations of everything Hikki persists locally.
public struct AppPaths: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// `HIKKI_DATA_DIR` overrides the location (UI tests use a fresh directory per run).
    public static func standard(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> AppPaths {
        if let override = environment["HIKKI_DATA_DIR"], !override.isEmpty {
            return AppPaths(root: URL(filePath: override, directoryHint: .isDirectory))
        }
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return AppPaths(root: support.appending(path: "Hikki", directoryHint: .isDirectory))
    }

    public var database: URL { root.appending(path: "hikki.sqlite") }
    public var logs: URL { root.appending(path: "logs", directoryHint: .isDirectory) }
    public var diagnostics: URL { root.appending(path: "diagnostics", directoryHint: .isDirectory) }
}
