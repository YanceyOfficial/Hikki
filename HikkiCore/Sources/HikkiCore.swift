import Foundation

/// Locations of everything Hikki persists locally.
public struct AppPaths: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public static func standard() throws -> AppPaths {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return AppPaths(root: support.appending(path: "Hikki", directoryHint: .isDirectory))
    }

    public var database: URL { root.appending(path: "hikki.sqlite") }
    public var logs: URL { root.appending(path: "logs", directoryHint: .isDirectory) }
    public var diagnostics: URL { root.appending(path: "diagnostics", directoryHint: .isDirectory) }
}
