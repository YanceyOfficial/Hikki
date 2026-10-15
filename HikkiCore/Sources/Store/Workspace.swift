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

/// The workspace as every device sees it inside its folder (`workspace.json` next to `pages/`): the shared
/// identity. The per-device `Workspace` (its location, the bookmark) stays in app data, so a second device
/// picking the folder *opens* this workspace — same name, icon and id — instead of creating another.
public struct WorkspaceIdentity: Codable, Equatable, Sendable {
    public static let currentFormat = 1

    public var format: Int
    public var id: UUID
    public var name: String
    public var icon: WorkspaceIcon?
    public var createdAt: Date
    public var updatedAt: Date

    public init(_ workspace: Workspace, updatedAt: Date = .now) {
        format = Self.currentFormat
        id = workspace.id
        name = workspace.name
        icon = workspace.icon
        createdAt = workspace.createdAt
        self.updatedAt = updatedAt
    }

    /// The device's workspace record with this identity (its location is untouched).
    public func applied(to workspace: Workspace) -> Workspace {
        var result = workspace
        result.id = id
        result.name = name
        result.icon = icon
        result.createdAt = createdAt
        return result
    }
}

/// Where a workspace's files live (`pages/`, `assets/`, `workspace.json`): the folder picked at onboarding, or —
/// for "this device only" — `Workspace/` next to the app's database.
public enum WorkspaceFolder {
    public static func url(for workspace: Workspace, appRoot: URL) throws -> URL {
        switch workspace.location {
        case .device: appRoot.appending(path: "Workspace", directoryHint: .isDirectory)
        case .folder(let bookmark, _): try FolderBookmark.resolve(bookmark)
        }
    }

    public static func identityURL(in root: URL) -> URL { root.appending(path: "workspace.json") }

    /// The identity a folder carries, nil for a folder no Hikki has used yet. Call with access to the folder.
    public static func readIdentity(in root: URL) throws -> WorkspaceIdentity? {
        let url = identityURL(in: root)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let identity = try decoder.decode(WorkspaceIdentity.self, from: Data(contentsOf: url))
        guard identity.format <= WorkspaceIdentity.currentFormat else { return nil }  // a newer Hikki's: leave it
        return identity
    }

    public static func writeIdentity(_ identity: WorkspaceIdentity, in root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(identity).write(to: identityURL(in: root), options: .atomic)
    }

    /// True while iCloud still has to deliver the folder's `workspace.json` (a `.workspace.json.icloud`
    /// placeholder): asks for the download. Nothing may be written over it meanwhile.
    public static func identityIsDownloading(in root: URL) -> Bool {
        let placeholder = root.appending(path: ".workspace.json.icloud")
        guard FileManager.default.fileExists(atPath: placeholder.path) else { return false }
        // The item to download is the file itself, not its stand-in.
        try? FileManager.default.startDownloadingUbiquitousItem(at: identityURL(in: root))
        return true
    }

    /// Runs `body` with security-scoped access to a picked folder (a no-op for other folders).
    public static func withAccess<T>(to url: URL, _ body: (URL) throws -> T) rethrows -> T {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try body(url)
    }

    /// What a picked folder already holds, for onboarding's "Opens ‘Yancey’s Space’ (12 pages)"; nil for an
    /// unused folder (or one whose identity is still downloading — then it reads as new; joining still
    /// adopts the identity once it arrives).
    public static func existingWorkspace(at url: URL) -> (name: String, pages: Int)? {
        withAccess(to: url) { root in
            guard let identity = try? readIdentity(in: root) else { return nil }
            return (identity.name, pageCount(in: root))
        }
    }

    /// How many pages a folder holds (downloaded or not) — "Open ‘Yancey’s Space’ (12 pages)".
    public static func pageCount(in root: URL) -> Int {
        PageFiles(root: root).presentIDs().count  // names only: no file is read
    }

    /// Runs `body` with the folder's page files, holding security-scoped access to a picked folder meanwhile.
    public static func withPages<T>(of workspace: Workspace, appRoot: URL, _ body: (PageFiles) throws -> T) throws -> T {
        let folder = try url(for: workspace, appRoot: appRoot)
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        return try body(PageFiles(root: folder))
    }
}
