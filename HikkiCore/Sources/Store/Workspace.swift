import Foundation
import ImageIO

/// The user's workspace: a name and where it lives. Created by onboarding on first launch.
/// (Page data still lives in the app's own store; moving it into `location` is a later step.)
public struct Workspace: Codable, Equatable, Sendable {
    public enum Location: Codable, Equatable, Sendable {
        /// Kept on this device only.
        case device
        /// Kept on this device and in the user's iCloud (CloudKit, `CloudSync`): the same folder as `device`, carried
        /// to their other devices.
        case cloud
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
        case .device, .cloud: appRoot.appending(path: "Workspace", directoryHint: .isDirectory)
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

    public enum CopyError: Error, Equatable {
        /// iCloud Drive still has this many of the folder's files to download (asked for now).
        case stillDownloading(Int)
    }

    /// Whether iCloud Drive has the file's contents on this device. A file not in iCloud Drive always has. On a
    /// File Provider iCloud Drive (macOS 14 and later) a file not downloaded keeps its real name and is still a regular
    /// file — only its downloading status tells; copying it would download it then and there, or fail offline.
    public static func isDownloaded(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
            values.isUbiquitousItem == true, let status = values.ubiquitousItemDownloadingStatus
        else { return true }
        return status == .current || status == .downloaded
    }

    /// Copies every file of a workspace folder (pages, history, comments, chats, assets, workspace.json) into
    /// `destination`, keeping their places; a file already there is replaced only by a newer one. Hidden files are
    /// left out. Throws `stillDownloading` — copying nothing, and asking iCloud Drive for the missing files — while
    /// any file is an iCloud placeholder or not downloaded (`downloaded`, `isDownloaded` but for tests). Returns how
    /// many files it copied. Reads and copies the whole folder: call it off the main thread.
    @discardableResult
    public static func copyContents(
        of source: URL, into destination: URL, downloaded: (URL) -> Bool = WorkspaceFolder.isDownloaded
    ) throws -> Int {
        let manager = FileManager.default
        let keys: [URLResourceKey] = [
            .isRegularFileKey, .contentModificationDateKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
        ]
        guard let enumerator = manager.enumerator(at: source, includingPropertiesForKeys: keys, options: []) else { return 0 }
        let base = source.standardizedFileURL.path
        var files: [(URL, String)] = []
        var placeholders: [URL] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if name.hasPrefix("."), name.hasSuffix(".icloud") {
                placeholders.append(url.deletingLastPathComponent().appending(path: String(name.dropFirst().dropLast(7))))
                continue
            }
            guard !name.hasPrefix("."), (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else {
                continue
            }
            let full = url.standardizedFileURL.path
            guard full.hasPrefix(base + "/") else { continue }
            guard downloaded(url) else {
                placeholders.append(url)
                continue
            }
            files.append((url, String(full.dropFirst(base.count + 1))))
        }
        if !placeholders.isEmpty {
            for file in placeholders { try? manager.startDownloadingUbiquitousItem(at: file) }
            throw CopyError.stillDownloading(placeholders.count)
        }
        var copied = 0
        for (url, path) in files {
            let target = destination.appending(path: path)
            if let existing = try? target.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                let incoming = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                existing >= incoming
            {
                continue
            }
            try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if manager.fileExists(atPath: target.path) { try manager.removeItem(at: target) }
            try manager.copyItem(at: url, to: target)
            copied += 1
        }
        return copied
    }

    /// The folder is there but this process may not read it: a Mac app in its sandbox holding a bookmark it can't
    /// open (one made before the sandbox, or whose grant was revoked). The user then has to pick the folder again —
    /// nothing else gives the access back. A folder that is simply gone is not this. Call with access to the folder.
    public static func accessDenied(at url: URL) -> Bool {
        do {
            _ = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            return false
        } catch let error as CocoaError where error.code == .fileReadNoPermission {
            return true
        } catch let error as NSError where error.domain == NSPOSIXErrorDomain {
            return error.code == Int(EPERM) || error.code == Int(EACCES)
        } catch {
            return false
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
