import Foundation

/// Remembers a user-picked folder across launches (security-scoped where the platform needs it).
public enum FolderBookmark {
    public enum BookmarkError: Error, Equatable {
        case stale
    }

    public static func make(for url: URL) throws -> Data {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        #if os(macOS)
            // Security-scoped bookmarks need the sandbox; fall back to a plain one outside it.
            if let data = try? url.bookmarkData(options: .withSecurityScope) { return data }
        #endif
        return try url.bookmarkData(options: [])
    }

    public static func resolve(_ data: Data) throws -> URL {
        var stale = false
        #if os(macOS)
            let options: URL.BookmarkResolutionOptions = [.withSecurityScope, .withoutUI]
            let url: URL
            if let scoped = try? URL(resolvingBookmarkData: data, options: options, bookmarkDataIsStale: &stale) {
                url = scoped
            } else {
                url = try URL(resolvingBookmarkData: data, options: [.withoutUI], bookmarkDataIsStale: &stale)
            }
        #else
            let url = try URL(resolvingBookmarkData: data, options: [.withoutUI], bookmarkDataIsStale: &stale)
        #endif
        if stale { throw BookmarkError.stale }
        return url
    }

    /// "iCloud Drive › Hikki" for folders in iCloud Drive, otherwise the folder name.
    public static func displayName(for url: URL) -> String {
        let path = url.standardizedFileURL.path
        if let range = path.range(of: "/Mobile Documents/com~apple~CloudDocs") {
            let inside = path[range.upperBound...].split(separator: "/").map(String.init)
            return (["iCloud Drive"] + inside).joined(separator: " › ")
        }
        return url.lastPathComponent
    }
}
