import Foundation

/// A zip chosen for import — Notion's export above all (Settings → Export → Markdown & CSV) — unpacked into a folder
/// of its own that `WorkspaceImport.plan` reads as a chosen folder. Notion appends every page's 32-hex id to its
/// file's and its subpages' folder's names ("Trip 1a2b…3c.md", "Trip 1a2b…3c/"): the names lose it (a clash gets a
/// number), each document is stamped with that id (`TransferStamp`, so the import keeps it or renames the links to
/// the id it gives), links between the pages become page links under those ids, pictures' paths follow the renames,
/// and a database (CSV) becomes a page with its rows as a table — its subpages' folder attaching to it by name, as
/// any folder does. Parts of a large export (zips inside the zip) are unpacked too. A zip that isn't Notion's unpacks
/// as it is: a folder of documents.
public enum NotionExport {
    public static func isArchive(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "zip"
    }

    public enum UnpackError: Error, Equatable {
        /// The archive's contents would be larger than `sizeLimit`.
        case tooLarge
        /// Not a zip that can be read.
        case unreadable
    }

    /// The most an archive may hold once unpacked.
    public static let sizeLimit: Int64 = 4 * 1024 * 1024 * 1024

    /// Unpacks `archive` into a new folder under `parent` and returns it; the caller removes it once the import is
    /// done (`WorkspaceImport.Plan.temporaryFolders`).
    public static func unpack(_ archive: URL, into parent: URL) throws -> URL {
        let folder = parent.appending(path: "hikki-import-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try extract(archive, into: folder)
        // A large export comes as parts — zips inside the zip, each a part of the same tree.
        for part in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        where isArchive(part) {
            try extract(part, into: folder)
            try FileManager.default.removeItem(at: part)
        }
        try normalize(folder)
        return folder
    }

    /// Every entry of the archive written under `folder` — never outside it (an entry's path is checked against the
    /// folder; `__MACOSX` and hidden entries are left out).
    static func extract(_ archive: URL, into folder: URL) throws {
        let zip: ZipArchive
        do {
            zip = try ZipArchive(url: archive)
        } catch {
            throw UnpackError.unreadable
        }
        var total: UInt64 = 0
        for entry in zip.entries {
            total += entry.uncompressedSize
            guard total <= UInt64(sizeLimit) else { throw UnpackError.tooLarge }
        }
        let root = folder.standardizedFileURL.path
        for entry in zip.entries {
            let components = entry.path.split(separator: "/").map(String.init)
            guard !components.isEmpty, !components.contains(where: { $0 == ".." || $0.hasPrefix(".") || $0 == "__MACOSX" })
            else { continue }
            let destination = folder.appending(path: components.joined(separator: "/"))
            guard destination.standardizedFileURL.path.hasPrefix(root + "/") else { continue }
            try zip.extract(entry, to: destination)
        }
    }

    // MARK: - Notion's names, links and databases

    /// One file or folder of the unpacked tree, by its path relative to the folder (components joined with "/").
    struct Entry: Equatable {
        var original: String
        var cleaned: String
        var isDirectory: Bool
        /// Notion's id from the name, if it had one.
        var id: String?
        /// A database's CSV with every row (`…_all.csv`), preferred over the view's.
        var isAllRows = false
        /// A database's view CSV beside its `_all` one: removed, never a page.
        var dropped = false
    }

    /// The space and 32-hex id Notion appends to a name's stem.
    private static let idSuffix = #"\s+([0-9a-fA-F]{32})$"#

    /// A name without Notion's id: "Trip 1a2b…3c.md" → ("Trip.md", "1a2b…3c"); a database's "…_all.csv" says so.
    static func cleanName(_ name: String) -> (name: String, id: String?, isAllRows: Bool) {
        let url = URL(filePath: name)
        let ext = url.pathExtension
        var stem = ext.isEmpty ? name : String(name.dropLast(ext.count + 1))
        var isAllRows = false
        if ext.lowercased() == "csv", stem.hasSuffix("_all") {
            stem = String(stem.dropLast(4))
            isAllRows = true
        }
        guard let match = stem.range(of: idSuffix, options: .regularExpression) else {
            return (name, nil, isAllRows)
        }
        let id = String(stem[match]).trimmingCharacters(in: .whitespaces).lowercased()
        let cleanedStem = String(stem[..<match.lowerBound])
        let cleaned = cleanedStem.isEmpty ? name : (ext.isEmpty ? cleanedStem : "\(cleanedStem).\(ext)")
        return (cleaned, id, isAllRows)
    }

    /// The tree's entries, each with the name it gets: Notion's ids dropped, a clash among siblings numbered.
    static func entries(in folder: URL) -> [Entry] {
        var result: [Entry] = []
        func walk(_ directory: URL, relative: String) {
            let urls =
                (try? FileManager.default.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
            var taken: Set<String> = []
            // A database exported as the view's rows and as every row: only the latter becomes its page.
            let allRows = Set(urls.map { cleanName($0.lastPathComponent) }.filter(\.isAllRows).map { $0.name.lowercased() })
            for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let name = url.lastPathComponent
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                let (base, id, isAllRows) = cleanName(name)
                let original = relative.isEmpty ? name : "\(relative)/\(name)"
                if !isDirectory, !isAllRows, url.pathExtension.lowercased() == "csv", allRows.contains(base.lowercased()) {
                    result.append(Entry(original: original, cleaned: original, isDirectory: false, id: id, dropped: true))
                    continue
                }
                var cleaned = base
                var n = 2
                while !taken.insert(cleaned.lowercased()).inserted {
                    let url = URL(filePath: base)
                    let ext = url.pathExtension
                    let stem = ext.isEmpty ? base : String(base.dropLast(ext.count + 1))
                    cleaned = ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)"
                    n += 1
                }
                let cleanedPath = relative.isEmpty ? cleaned : "\(parentCleaned(relative, in: result))/\(cleaned)"
                result.append(Entry(original: original, cleaned: cleanedPath, isDirectory: isDirectory, id: id, isAllRows: isAllRows))
                if isDirectory { walk(url, relative: original) }
            }
        }
        walk(folder, relative: "")
        return result
    }

    private static func parentCleaned(_ original: String, in entries: [Entry]) -> String {
        entries.first { $0.original == original }?.cleaned ?? original
    }

    /// Renames, rewrites and converts in place.
    static func normalize(_ folder: URL) throws {
        let all = entries(in: folder)
        let byOriginal = Dictionary(all.map { ($0.original, $0) }, uniquingKeysWith: { a, _ in a })
        // A database's view CSV steps aside for the one with every row.
        let dropped = Set(all.filter(\.dropped).map(\.original))
        // Documents first, while every path is still the original: links are resolved against them.
        for entry in all where !entry.isDirectory && !entry.dropped {
            let url = folder.appending(path: entry.original)
            let ext = URL(filePath: entry.original).pathExtension.lowercased()
            let documentFolder = entry.original.contains("/") ? String(entry.original[..<entry.original.lastIndex(of: "/")!]) : ""
            switch ext {
            case "md", "markdown":
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                let rewritten = rewriteLinks(in: text, documentFolder: documentFolder, entries: byOriginal)
                try (stamp(entry.id) + rewritten).write(to: url, atomically: true, encoding: .utf8)
            case "csv":
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                let title = URL(filePath: entry.cleaned).deletingPathExtension().lastPathComponent
                var table = "# \(title)\n\n" + markdownTable(csv: text)
                table = rewriteLinks(in: table, documentFolder: documentFolder, entries: byOriginal)
                try (stamp(entry.id) + table).write(
                    to: url.deletingPathExtension().appendingPathExtension("md"), atomically: true, encoding: .utf8)
                try FileManager.default.removeItem(at: url)
            default:
                continue
            }
        }
        for view in dropped { try? FileManager.default.removeItem(at: folder.appending(path: view)) }
        // Deepest first: a child moves under its parent's old name, then the parent itself.
        for entry in all.sorted(by: { $0.original.count(where: { $0 == "/" }) > $1.original.count(where: { $0 == "/" }) }) {
            var fromPath = entry.original
            var toPath = entry.original
            if fromPath.hasSuffix(".csv") || fromPath.hasSuffix(".CSV") {
                // Converted above.
                if dropped.contains(fromPath) { continue }
                fromPath = String(fromPath.dropLast(4)) + ".md"
                toPath = String(entry.cleaned.dropLast(4)) + ".md"
            } else {
                toPath = entry.cleaned
            }
            let cleanedName = URL(filePath: toPath).lastPathComponent
            let from = folder.appending(path: fromPath)
            let to = from.deletingLastPathComponent().appending(path: cleanedName)
            guard from.path != to.path, FileManager.default.fileExists(atPath: from.path) else { continue }
            try FileManager.default.moveItem(at: from, to: to)
        }
    }

    static func stamp(_ id: String?) -> String {
        guard let id else { return "" }
        return "---\n\(TransferStamp.idKey): \(id)\n---\n\n"
    }

    private static let link = #"\]\(([^)\s]+)((?:\s+"[^"]*")?)\)"#
    private static let notionURL = #"^https?://(?:www\.)?notion\.so/(?:[^/?#]+/)?[^/?#]*?([0-9a-fA-F]{32})(?:[?#].*)?$"#

    /// Markdown with its links to the export's other pages (relative, or notion.so addresses) as page links under
    /// their ids, and its other relative links (pictures, attachments) under the cleaned names.
    static func rewriteLinks(in markdown: String, documentFolder: String, entries: [String: Entry]) -> String {
        guard let regex = try? NSRegularExpression(pattern: link) else { return markdown }
        let ns = markdown as NSString
        var result = ""
        var last = 0
        for match in regex.matches(in: markdown, range: NSRange(location: 0, length: ns.length)) {
            let target = ns.substring(with: match.range(at: 1))
            let title = ns.substring(with: match.range(at: 2))
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            result += "](\(rewriteTarget(target, documentFolder: documentFolder, entries: entries))\(title))"
            last = match.range.location + match.range.length
        }
        result += ns.substring(from: last)
        return result
    }

    static func rewriteTarget(_ target: String, documentFolder: String, entries: [String: Entry]) -> String {
        if let match = target.range(of: notionURL, options: .regularExpression) {
            let id = String(target[match]).range(of: #"[0-9a-fA-F]{32}"#, options: .regularExpression).map {
                String(target[match][$0]).lowercased()
            }
            if let id, entries.values.contains(where: { $0.id == id }) { return "hikki://page/\(id)" }
            return target
        }
        guard URL(string: target)?.scheme == nil, !target.hasPrefix("/"), !target.hasPrefix("#") else { return target }
        let fragment = target.firstIndex(of: "#").map { String(target[$0...]) } ?? ""
        let path = fragment.isEmpty ? target : String(target[..<target.firstIndex(of: "#")!])
        let decoded = path.removingPercentEncoding ?? path
        let resolved = resolve(decoded, against: documentFolder)
        guard let entry = entries[resolved] else { return target }
        if let id = entry.id, ["md", "markdown", "csv"].contains(URL(filePath: resolved).pathExtension.lowercased()) {
            return "hikki://page/\(id)"
        }
        let documentCleaned = entries[documentFolder]?.cleaned ?? documentFolder
        let relative = relativePath(entry.cleaned, from: documentCleaned)
        return (relative.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? relative) + fragment
    }

    /// `path` joined onto `folder` with `.` and `..` settled; "" is the root.
    static func resolve(_ path: String, against folder: String) -> String {
        var parts = folder.isEmpty ? [] : folder.split(separator: "/").map(String.init)
        for component in path.split(separator: "/") {
            switch component {
            case ".": continue
            case "..": if !parts.isEmpty { parts.removeLast() }
            default: parts.append(String(component))
            }
        }
        return parts.joined(separator: "/")
    }

    static func relativePath(_ path: String, from folder: String) -> String {
        var from = folder.isEmpty ? [] : folder.split(separator: "/").map(String.init)
        var to = path.split(separator: "/").map(String.init)
        while let a = from.first, let b = to.first, a == b {
            from.removeFirst()
            to.removeFirst()
        }
        return (Array(repeating: "..", count: from.count) + to).joined(separator: "/")
    }

    // MARK: - CSV

    /// A CSV's rows (RFC 4180: quoted fields may hold commas, quotes doubled, and line breaks).
    static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var chars = text.makeIterator()
        var pending: Character? = nil
        func next() -> Character? {
            if let p = pending {
                pending = nil
                return p
            }
            return chars.next()
        }
        while let c = next() {
            if quoted {
                if c == "\"" {
                    if let n = next() {
                        if n == "\"" {
                            field.append("\"")
                        } else {
                            quoted = false
                            pending = n
                        }
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(c)
                }
                continue
            }
            switch c {
            case "\"":
                quoted = true
            case ",":
                row.append(field)
                field = ""
            case "\r":
                continue
            case "\n":
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            default:
                field.append(c)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows.filter { !($0.count == 1 && $0[0].isEmpty) }
    }

    /// The CSV as a Markdown table: the first row its header. Nothing when it has no rows.
    static func markdownTable(csv: String) -> String {
        let rows = parseCSV(csv.hasPrefix("\u{FEFF}") ? String(csv.dropFirst()) : csv)
        guard let header = rows.first, !header.isEmpty else { return "" }
        let width = rows.map(\.count).max() ?? header.count
        func cell(_ text: String) -> String {
            text.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\r\n", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
        }
        func line(_ row: [String]) -> String {
            "| " + (0..<width).map { $0 < row.count ? cell(row[$0]) : "" }.joined(separator: " | ") + " |"
        }
        var lines = [line(header), "| " + Array(repeating: "---", count: width).joined(separator: " | ") + " |"]
        lines += rows.dropFirst().map(line)
        return lines.joined(separator: "\n") + "\n"
    }
}
