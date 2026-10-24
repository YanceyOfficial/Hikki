import Foundation

/// Excalidraw's Library — shapes kept for every drawing — as one file in the workspace folder,
/// `drawings/library.json` (format-versioned), so it goes with the workspace to the user's other Macs. The items are
/// Excalidraw's own and opaque here: the editor checks them on the way in and out (`storedLibraryItems`). A newer
/// write replaces the file whole; two Macs changing it at once keep the later one.
public struct DrawingLibrary: Sendable {
    public static let format = 1
    public static let folderName = "drawings"
    /// Larger than any Library worth keeping: a bigger one is refused rather than written.
    public static let maxBytes = 20 * 1024 * 1024

    public enum LibraryError: Error, Equatable {
        /// Written by a newer Hikki: read as nothing and never written over.
        case newerFormat(Int)
        case notItems
        case tooLarge(Int)
    }

    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    var file: URL {
        root.appending(path: Self.folderName, directoryHint: .isDirectory).appending(path: "library.json")
    }

    /// The stored items, `[]` when there is no Library yet; throws when the file can't be read (the editor then
    /// leaves it alone).
    public func items() throws -> JSONValue {
        guard FileManager.default.fileExists(atPath: file.path) else { return .array([]) }
        let stored = try JSONValue(jsonData: try Data(contentsOf: file))
        guard case .object(let object) = stored else { throw LibraryError.notItems }
        if case .number(let format) = object["format"], Int(format) > Self.format { throw LibraryError.newerFormat(Int(format)) }
        guard case .array = object["items"] else { throw LibraryError.notItems }
        return object["items"] ?? .array([])
    }

    /// Replaces the stored items (written atomically), under the file's lock (`FileLocks`), which what arrives from
    /// iCloud takes too: the two writes never interleave.
    public func save(_ items: JSONValue) throws {
        try FileLocks.shared.withLock(file) { try saveLocked(items) }
    }

    private func saveLocked(_ items: JSONValue) throws {
        guard case .array = items else { throw LibraryError.notItems }
        // A newer Hikki's Library is never overwritten by this one's.
        if case .failure(LibraryError.newerFormat(let format)) = Result(catching: { try self.items() }) {
            throw LibraryError.newerFormat(format)
        }
        let data = try JSONValue.object(["format": .number(Double(Self.format)), "items": items]).jsonData()
        guard data.count <= Self.maxBytes else { throw LibraryError.tooLarge(data.count) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
    }
}
