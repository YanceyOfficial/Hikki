import Foundation
import ImageIO

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
    /// Shown in the sidebar instead of the name's initial. Older workspace files have none.
    public var icon: WorkspaceIcon?

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

/// A workspace's own icon (Settings → General): an emoji, or a small image kept inside the workspace file so
/// it travels with it.
public enum WorkspaceIcon: Codable, Equatable, Sendable {
    case emoji(String)
    /// PNG, at most `maxPixels` on its longer side (see `thumbnail(of:)`).
    case image(Data)

    public static let maxPixels = 256

    /// Downscales any image ImageIO can read to a PNG of at most `maxPixels`; nil if it isn't an image.
    public static func thumbnail(of data: Data, maxPixels: Int = maxPixels) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                ] as CFDictionary)
        else { return nil }
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? out as Data : nil
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

/// Where a workspace's files live (`pages/`, later `assets/`): the folder picked at onboarding, or — for
/// "this device only" — `Workspace/` next to the app's database.
public enum WorkspaceFolder {
    public static func url(for workspace: Workspace, appRoot: URL) throws -> URL {
        switch workspace.location {
        case .device: appRoot.appending(path: "Workspace", directoryHint: .isDirectory)
        case .folder(let bookmark, _): try FolderBookmark.resolve(bookmark)
        }
    }

    /// Runs `body` with the folder's page files, holding security-scoped access to a picked folder meanwhile.
    public static func withPages<T>(of workspace: Workspace, appRoot: URL, _ body: (PageFiles) throws -> T) throws -> T {
        let folder = try url(for: workspace, appRoot: appRoot)
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        return try body(PageFiles(root: folder))
    }
}
