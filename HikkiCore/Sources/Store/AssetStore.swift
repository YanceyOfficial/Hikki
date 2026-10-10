import Foundation

/// User images (page covers today, inline images later), stored as files and served to the editor
/// through the custom scheme as `hikki-editor://assets/<name>`.
public struct AssetStore: Sendable {
    public static let urlPrefix = "hikki-editor://assets/"
    public static let allowedExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic"]

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public enum AssetError: Error, Equatable {
        case unsupportedType(String)
        case tooLarge(Int)
    }

    /// Saves bytes under a fresh unique name and returns the editor URL.
    public func save(_ data: Data, fileExtension: String, maxBytes: Int = 20 * 1024 * 1024) throws -> String {
        let ext = fileExtension.lowercased()
        guard Self.allowedExtensions.contains(ext) else { throw AssetError.unsupportedType(ext) }
        guard data.count <= maxBytes else { throw AssetError.tooLarge(data.count) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = "\(UUID().uuidString.lowercased()).\(ext)"
        try data.write(to: directory.appending(path: name), options: .atomic)
        return Self.urlPrefix + name
    }

    /// File for an asset name, or nil if the name tries to escape the directory or doesn't exist.
    public func file(named name: String) -> URL? {
        guard !name.isEmpty, !name.contains("/"), !name.hasPrefix(".") else { return nil }
        let url = directory.appending(path: name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
