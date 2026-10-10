import Foundation

/// The user's workspace: a name and where it lives. Created by onboarding on first launch.
/// (Page data still lives in the app's own store; moving it into `location` is a later step.)
public struct Workspace: Codable, Equatable, Sendable {
    public enum Location: Codable, Equatable, Sendable {
        /// Kept on this device only.
        case device
        /// A user-chosen folder (typically in iCloud Drive), remembered as a security-scoped bookmark.
        case folder(bookmark: Data, displayName: String)
    }

    public var id: UUID
    public var name: String
    public var location: Location
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, location: Location, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.location = location
        self.createdAt = createdAt
    }

    /// Trimmed, single-line, at most 60 characters; nil when nothing is left.
    public static func normalizedName(_ raw: String) -> String? {
        let name = raw.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : String(name.prefix(60))
    }

    /// The badge letter shown next to the workspace name.
    public var initial: String {
        name.first.map { String($0).uppercased() } ?? "H"
    }
}

/// Persists the workspace as JSON next to the database (`workspace.json`). Missing file = first launch.
public struct WorkspaceStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func load() throws -> Workspace? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Workspace.self, from: Data(contentsOf: url))
    }

    public func save(_ workspace: Workspace) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(workspace).write(to: url, options: .atomic)
    }
}
