import Foundation

/// Which file of the editor bundle a `hikki-editor://app/<path>` request may read: the path under the bundle's folder
/// and nowhere else. The check is by path components — the folder's path with a trailing separator — so a sibling
/// whose name merely starts with the folder's (`Editor-evil/`) is outside, and `..` is resolved before the check.
public enum BundleFiles {
    /// `relativePath` is the request's path without its leading slashes; empty means the entry page.
    public static func file(for relativePath: String, in root: URL) -> URL? {
        let candidate = root.appending(path: relativePath.isEmpty ? "index.html" : relativePath).standardizedFileURL
        let folder = root.standardizedFileURL.path
        let top = folder.hasSuffix("/") ? folder : folder + "/"
        guard candidate.path.hasPrefix(top) else { return nil }
        return candidate
    }
}
