import Foundation

/// User files — covers, images, video, audio, attachments — stored by unique name and served to the editor
/// through the custom scheme as `hikki-editor://assets/<name>`. Once a workspace is open they live in its
/// folder (`assets/`), so they sync with the pages; the app-data directory used before stays readable.
public final class AssetStore: @unchecked Sendable {
    public static let urlPrefix = "hikki-editor://assets/"

    public enum Kind: String, Sendable, Equatable {
        case image, video, audio, file
    }

    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "avif"]
    static let videoExtensions: Set<String> = ["mp4", "m4v", "mov", "webm"]
    static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "ogg", "oga", "flac", "opus"]
    /// Images the cover / inline image paths accept.
    public static let allowedExtensions = imageExtensions

    /// Attachments may have any short alphanumeric extension; they're served inert (see the scheme handler).
    public static func kind(ofExtension raw: String) -> Kind? {
        let ext = raw.lowercased()
        guard (1...10).contains(ext.count), ext.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
            return nil
        }
        if imageExtensions.contains(ext) { return .image }
        if videoExtensions.contains(ext) { return .video }
        if audioExtensions.contains(ext) { return .audio }
        return .file
    }

    public static func maxBytes(for kind: Kind) -> Int {
        switch kind {
        case .image: 50 * 1024 * 1024
        case .video, .audio, .file: 1024 * 1024 * 1024
        }
    }

    public enum AssetError: Error, Equatable {
        case unsupportedType(String)
        case tooLarge(Int)
    }

    private let lock = NSLock()
    /// Where assets were kept before the workspace folder (app data): still read, never written once a
    /// workspace folder is set.
    private let legacy: URL
    private var workspaceAssets: URL?
    /// Workspace folders used earlier in this session (the workspace moved): still read, copied from.
    private var previous: [URL] = []

    public init(directory: URL) {
        self.legacy = directory
    }

    /// Where new assets go.
    public var directory: URL {
        lock.withLock { workspaceAssets ?? legacy }
    }

    /// From now on, assets live in `<workspace>/assets`.
    public func useWorkspaceFolder(_ root: URL) {
        lock.withLock {
            if let current = workspaceAssets { previous.append(current) }
            workspaceAssets = root.appending(path: "assets", directoryHint: .isDirectory)
        }
    }

    /// Copies files only in earlier directories (app data, a previous workspace folder) into the workspace
    /// folder — not moved: nothing is deleted — so pages referencing them work on other devices too. Run off
    /// the main thread.
    public func copyLegacyAssets() {
        let (assets, sources): (URL?, [URL]) = lock.withLock { (workspaceAssets, [legacy] + previous) }
        guard let assets else { return }
        let fm = FileManager.default
        for source in sources where source.standardizedFileURL != assets.standardizedFileURL {
            guard let names = try? fm.contentsOfDirectory(atPath: source.path), !names.isEmpty else { continue }
            try? fm.createDirectory(at: assets, withIntermediateDirectories: true)
            for name in names where Self.isValidName(name) {
                let target = assets.appending(path: name)
                if !fm.fileExists(atPath: target.path) { try? fm.copyItem(at: source.appending(path: name), to: target) }
            }
        }
    }

    /// Saves bytes under a fresh unique name and returns the editor URL (covers, small images).
    public func save(_ data: Data, fileExtension: String, maxBytes: Int = 20 * 1024 * 1024) throws -> String {
        let ext = fileExtension.lowercased()
        guard Self.allowedExtensions.contains(ext) else { throw AssetError.unsupportedType(ext) }
        guard data.count <= maxBytes else { throw AssetError.tooLarge(data.count) }
        let target = try newFile(ext)
        try data.write(to: target, options: .atomic)
        return Self.urlPrefix + target.lastPathComponent
    }

    /// Moves a finished upload into the store under a fresh unique name and returns the editor URL.
    public func importFile(at source: URL, fileExtension: String) throws -> String {
        guard let kind = Self.kind(ofExtension: fileExtension) else { throw AssetError.unsupportedType(fileExtension) }
        let size = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= Self.maxBytes(for: kind) else { throw AssetError.tooLarge(size) }
        let target = try newFile(fileExtension.lowercased())
        try FileManager.default.moveItem(at: source, to: target)
        return Self.urlPrefix + target.lastPathComponent
    }

    /// File for an asset name — in the workspace folder, else the old directory — or nil if the name
    /// tries to escape the directory or doesn't exist.
    public func file(named name: String) -> URL? {
        guard Self.isValidName(name) else { return nil }
        let fm = FileManager.default
        let candidates = lock.withLock { [workspaceAssets].compactMap { $0 } + previous + [legacy] }
        return candidates.map { $0.appending(path: name) }.first { fm.fileExists(atPath: $0.path) }
    }

    /// The asset name in a `hikki-editor://assets/<name>` URL.
    public static func name(fromURL url: String) -> String? {
        guard url.hasPrefix(urlPrefix) else { return nil }
        let name = String(url.dropFirst(urlPrefix.count))
        return isValidName(name) ? name : nil
    }

    static func isValidName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && !name.hasPrefix(".") && !name.contains("\\")
    }

    private func newFile(_ ext: String) throws -> URL {
        let directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "\(UUID().uuidString.lowercased()).\(ext)")
    }
}

/// Large files arrive from the editor in chunks (base64 over the bridge would otherwise mean one huge
/// message): begin → chunk… → finish, written to a temporary file, then moved into the asset store.
public final class AssetUploads: @unchecked Sendable {
    public enum UploadError: Error, Equatable {
        case unknownUpload
        case tooLarge
    }

    private struct Upload {
        let fileExtension: String
        let file: URL
        let handle: FileHandle
        var bytes: Int
        let limit: Int
    }

    private let lock = NSLock()
    private var uploads: [String: Upload] = [:]
    private let store: AssetStore
    private let temporary: URL

    public init(store: AssetStore, temporary: URL = FileManager.default.temporaryDirectory.appending(path: "hikki-uploads")) {
        self.store = store
        self.temporary = temporary
    }

    /// Starts an upload of `size` bytes; returns its id. Refuses types and sizes the store won't take.
    public func begin(fileExtension: String, size: Int) throws -> String {
        guard let kind = AssetStore.kind(ofExtension: fileExtension) else {
            throw AssetStore.AssetError.unsupportedType(fileExtension)
        }
        let limit = AssetStore.maxBytes(for: kind)
        guard size >= 0, size <= limit else { throw AssetStore.AssetError.tooLarge(size) }
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        let id = UUID().uuidString.lowercased()
        let file = temporary.appending(path: id)
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let handle = try FileHandle(forWritingTo: file)
        lock.withLock {
            uploads[id] = Upload(fileExtension: fileExtension, file: file, handle: handle, bytes: 0, limit: min(limit, size))
        }
        return id
    }

    public func append(_ id: String, _ data: Data) throws {
        try lock.withLock {
            guard var upload = uploads[id] else { throw UploadError.unknownUpload }
            guard upload.bytes + data.count <= upload.limit else {
                discard(id)
                throw UploadError.tooLarge
            }
            try upload.handle.write(contentsOf: data)
            upload.bytes += data.count
            uploads[id] = upload
        }
    }

    /// Moves the upload into the store; returns the editor URL.
    public func finish(_ id: String) throws -> String {
        let upload: Upload = try lock.withLock {
            guard let upload = uploads.removeValue(forKey: id) else { throw UploadError.unknownUpload }
            return upload
        }
        try upload.handle.close()
        do {
            return try store.importFile(at: upload.file, fileExtension: upload.fileExtension)
        } catch {
            try? FileManager.default.removeItem(at: upload.file)
            throw error
        }
    }

    public func cancel(_ id: String) {
        lock.withLock { discard(id) }
    }

    /// Caller holds the lock.
    private func discard(_ id: String) {
        guard let upload = uploads.removeValue(forKey: id) else { return }
        try? upload.handle.close()
        try? FileManager.default.removeItem(at: upload.file)
    }
}
