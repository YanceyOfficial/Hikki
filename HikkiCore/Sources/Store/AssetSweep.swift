import Foundation

/// Files in the workspace's `assets/` that nothing uses any more — a drawing's earlier previews, a replaced cover, a
/// picture taken out of a page — go once they have sat unused for `grace`. "Used" is read as widely as it can be:
/// any string in any of the workspace's own files (pages, their history, comments, AI chats…) or in the database's rows
/// that names the file. Anything that can't be read — a file still downloading from another device, a half-written
/// one — stops the sweep: such a file may name any asset.
public enum AssetSweep {
    /// How long an unused file stays: past an undo, a version in the page's history (kept 30 days), another device's
    /// page that names it still on its way.
    public static let grace: TimeInterval = 30 * 86_400

    /// Deletes the unused files older than `grace`; returns their names, or nil when the workspace couldn't be read
    /// whole (nothing is deleted then). `rows` are the database's strings (each page's content, icon and cover).
    @discardableResult
    public static func sweep(root: URL, rows: [String], now: Date = .now) -> [String]? {
        let assets = root.appending(path: AssetStore.assetsFolderName, directoryHint: .isDirectory)
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: assets.path) else { return [] }
        let cutoff = now.addingTimeInterval(-grace)
        let old = names.filter { name in
            guard AssetStore.isValidName(name) else { return false }
            let keys: Set<URLResourceKey> = [.isRegularFileKey, .creationDateKey, .contentModificationDateKey]
            guard let values = try? assets.appending(path: name).resourceValues(forKeys: keys), values.isRegularFile == true
            else { return false }
            let newest = max(values.creationDate ?? .distantFuture, values.contentModificationDate ?? .distantFuture)
            return newest < cutoff
        }
        guard !old.isEmpty else { return [] }
        guard let mentions = mentions(root: root, rows: rows) else { return nil }
        var removed: [String] = []
        for name in old where !isNamed(name, in: mentions) {
            do {
                try fm.removeItem(at: assets.appending(path: name))
                removed.append(name)
            } catch {
                Log.warn("unused asset not removed: \(error)", category: "assets")
            }
        }
        return removed
    }

    /// Every string in the workspace's files and `rows` that mentions an asset (holds "assets/"); nil when a file
    /// couldn't be read.
    static func mentions(root: URL, rows: [String]) -> [String]? {
        var found: [String] = []
        for row in rows { collect(row, into: &found) }
        let keys: [URLResourceKey] = [.isRegularFileKey, .ubiquitousItemDownloadingStatusKey]
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: []) else {
            return nil
        }
        for case let url as URL in walker {
            let name = url.lastPathComponent
            if name == AssetStore.assetsFolderName, url.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL {
                walker.skipDescendants()
                continue
            }
            // iOS shows a file not downloaded yet as `.<name>.icloud`.
            if name.hasPrefix("."), name.hasSuffix(".icloud") { return nil }
            guard url.pathExtension.lowercased() == "json" else { continue }
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            if let status = values?.ubiquitousItemDownloadingStatus, status != .current { return nil }
            guard let data = try? Data(contentsOf: url), let json = try? JSONSerialization.jsonObject(with: data) else {
                Log.warn("asset sweep stopped: a file couldn't be read", category: "assets")
                return nil
            }
            walk(json, into: &found)
        }
        return found
    }

    private static func walk(_ value: Any, into found: inout [String]) {
        switch value {
        case let string as String: collect(string, into: &found)
        case let array as [Any]: for item in array { walk(item, into: &found) }
        case let object as [String: Any]: for item in object.values { walk(item, into: &found) }
        default: break
        }
    }

    /// A string naming assets; one holding JSON (a row's content) is read for its strings too.
    private static func collect(_ string: String, into found: inout [String]) {
        guard string.contains("assets/") else { return }
        found.append(string)
        if let data = string.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed),
            !(json is String)
        {
            walk(json, into: &found)
        }
    }

    /// Whether a mention names the file — as it is, or percent-encoded (a name with spaces in a link).
    static func isNamed(_ name: String, in mentions: [String]) -> Bool {
        let forms = Set(["assets/" + name, "assets/" + (name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name)])
        return mentions.contains { mention in forms.contains { mention.contains($0) } }
    }
}
