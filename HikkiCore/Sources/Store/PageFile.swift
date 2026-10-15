import Foundation

/// One page on disk: `pages/<id>.json` in the workspace folder — the format pages sync in (storage option C:
/// the folder is the source of truth, the SQLite store a rebuildable cache). Everything a device needs to show
/// and index the page is here; each page carries its own place in the tree, so no shared index file exists for
/// two devices to write at once.
public struct PageFile: Codable, Equatable, Sendable {
    /// Bumped when the shape changes incompatibly; readers refuse newer formats instead of guessing.
    public static let currentFormat = 1

    public var format: Int
    public var id: String
    public var title: String
    /// An emoji, or nil.
    public var icon: String?
    /// A `PageCover` raw value, or nil.
    public var cover: String?
    public var parentId: String?
    public var sortKey: Double
    public var createdAt: Date
    /// Last edited (title, body, icon, cover, lock): the "Edited" date.
    public var updatedAt: Date
    /// Last change of any kind (an edit, or a move, reorder, trash, restore, favorite) — what devices compare to
    /// pick the newer side. Absent in files from before it existed: then `updatedAt`. Optional, so the format stays 1
    /// (older readers ignore it).
    public var changedAt: Date?
    public var favoritedAt: Date?
    public var deletedAt: Date?
    /// Set while the page is locked (read-only everywhere); absent in files from before locking existed.
    public var lockedAt: Date?
    /// Derived from `content`, stored so another device can index the page without parsing the editor schema.
    public var plainText: String
    public var wordCount: Int
    /// Tiptap JSON (body only), nil for a never-edited page. Stored as JSON, not as an escaped string.
    public var content: JSONValue?

    public init(record: DocumentRecord) throws {
        format = Self.currentFormat
        id = record.id
        title = record.title
        icon = record.icon
        cover = record.cover
        parentId = record.parentId
        sortKey = record.sortKey
        createdAt = record.createdAt
        updatedAt = record.updatedAt
        changedAt = record.changedAt
        favoritedAt = record.favoritedAt
        deletedAt = record.deletedAt
        lockedAt = record.lockedAt
        plainText = record.plainText
        wordCount = record.wordCount
        content = try record.contentValue()
    }

    /// Back into a store row.
    public func record() throws -> DocumentRecord {
        DocumentRecord(
            id: id, title: title, content: try content.map { String(decoding: try $0.jsonData(), as: UTF8.self) },
            plainText: plainText, wordCount: wordCount, createdAt: createdAt, updatedAt: updatedAt, parentId: parentId,
            icon: icon, cover: cover, favoritedAt: favoritedAt, deletedAt: deletedAt, sortKey: sortKey, lockedAt: lockedAt,
            changedAt: changedAt)
    }

    /// The last change of any kind: the later of `changedAt` and `updatedAt` (a writer that predates `changedAt` only
    /// moves `updatedAt`).
    public var lastChange: Date { max(changedAt ?? updatedAt, updatedAt) }
}

/// Reads and writes the page files of one workspace folder.
public struct PageFiles: Sendable {
    public enum PageFileError: Error, Equatable {
        /// Written by a newer Hikki; left alone rather than misread.
        case unsupportedFormat(id: String, format: Int)
        /// Not a page id we would ever create (path separators, dot files…).
        case invalidID(String)
    }

    /// The workspace folder; pages live in `pages/` inside it.
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public var directory: URL { root.appending(path: "pages", directoryHint: .isDirectory) }

    public func url(for id: String) throws -> URL {
        guard Self.isValid(id) else { throw PageFileError.invalidID(id) }
        return directory.appending(path: "\(id).json")
    }

    public func exists(_ id: String) -> Bool {
        (try? url(for: id)).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    /// Atomic write (temp file + rename), so a reader — or iCloud — never sees half a page.
    public func write(_ page: PageFile) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.encoder.encode(page).write(to: try url(for: page.id), options: .atomic)
    }

    public func read(_ id: String) throws -> PageFile? {
        let url = try url(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Self.decode(Data(contentsOf: url))
    }

    /// Every readable page file. Files that aren't pages (or come from a newer format) are skipped and returned
    /// in `skipped`, so a stray file never blocks the rest.
    public func readAll() throws -> (pages: [PageFile], skipped: [URL]) {
        let listing = try scan()
        return (listing.pages, listing.skipped)
    }

    /// A page file as last seen: when it was modified, its size, and the last change it holds (`lastChange`). A
    /// file whose date and size still match needn't be read again.
    public struct Stamp: Equatable, Sendable {
        public var modified: Date
        public var size: Int
        public var changedAt: Date

        public init(modified: Date, size: Int, changedAt: Date) {
            self.modified = modified
            self.size = size
            self.changedAt = changedAt
        }
    }

    /// What the folder holds. `present` names every page the folder has *any* trace of — a readable file, one
    /// that isn't (half-downloaded, corrupt, from a newer Hikki) and iCloud placeholders for files not downloaded
    /// yet — so nothing that merely can't be read right now is ever mistaken for a deletion.
    public struct Listing: Sendable {
        public var folderExists: Bool
        /// Pages read in this scan: every readable file, minus those `known` already describes.
        public var pages: [PageFile]
        public var skipped: [URL]
        /// Pages iCloud hasn't delivered yet, by the URL they will have — what `startDownloadingUbiquitousItem`
        /// takes (asking it to download the `.<id>.json.icloud` stand-in itself does nothing).
        public var placeholders: [URL]
        public var present: Set<String>
        /// Every readable page file, whether read now or reused from `known`.
        public var stamps: [String: Stamp]
    }

    /// Lists the folder. Files matching their stamp in `known` aren't read again (the folder watcher scans
    /// after every change, including this device's own writes).
    public func scan(known: [String: Stamp] = [:]) throws -> Listing {
        var listing = Listing(folderExists: false, pages: [], skipped: [], placeholders: [], present: [], stamps: [:])
        guard FileManager.default.fileExists(atPath: directory.path) else { return listing }
        listing.folderExists = true
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) {
            let name = url.lastPathComponent
            if let id = Self.placeholderID(name) {
                // ".<id>.json.icloud": in iCloud, not on this device yet.
                listing.placeholders.append(directory.appending(path: "\(id).json"))
                listing.present.insert(id)
            } else if url.pathExtension == "json" {
                let id = String(name.dropLast(".json".count))
                if Self.isValid(id) { listing.present.insert(id) }
                let attributes = Self.attributes(of: url)
                if let attributes, let stamp = known[id], stamp.size == attributes.size,
                    abs(stamp.modified.timeIntervalSince(attributes.modified)) < 0.000_01
                {
                    listing.stamps[id] = stamp
                } else if let page = try? Self.decode(Data(contentsOf: url)), Self.isValid(page.id), page.id == id {
                    listing.pages.append(page)
                    listing.present.insert(page.id)
                    if let attributes {
                        listing.stamps[id] = Stamp(modified: attributes.modified, size: attributes.size, changedAt: page.lastChange)
                    }
                } else {
                    listing.skipped.append(url)
                }
            }
        }
        listing.pages.sort { $0.id < $1.id }
        return listing
    }

    /// The stamp of a page's file as it is now (after this device wrote it).
    public func stamp(of id: String, changedAt: Date) -> Stamp? {
        guard let url = try? url(for: id), let attributes = Self.attributes(of: url) else { return nil }
        return Stamp(modified: attributes.modified, size: attributes.size, changedAt: changedAt)
    }

    /// The ids of the pages the folder has any trace of (files and iCloud placeholders), without reading a file.
    public func presentIDs() -> Set<String> {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        var ids = Set<String>()
        for name in names {
            if let id = Self.placeholderID(name) {
                ids.insert(id)
            } else if name.hasSuffix(".json"), case let id = String(name.dropLast(".json".count)), Self.isValid(id) {
                ids.insert(id)
            }
        }
        return ids
    }

    private static func attributes(of url: URL) -> (modified: Date, size: Int)? {
        // Fresh values: URL caches resource values per instance.
        var url = url
        url.removeAllCachedResourceValues()
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
            let modified = values.contentModificationDate, let size = values.fileSize
        else { return nil }
        return (modified, size)
    }

    static func placeholderID(_ name: String) -> String? {
        guard name.hasPrefix("."), name.hasSuffix(".json.icloud") else { return nil }
        let id = String(name.dropFirst().dropLast(".json.icloud".count))
        return isValid(id) ? id : nil
    }

    public func delete(_ id: String) throws {
        let url = try url(for: id)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    // MARK: Coding

    static func isValid(_ id: String) -> Bool {
        !id.isEmpty && !id.hasPrefix(".") && id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    static func decode(_ data: Data) throws -> PageFile {
        let page = try decoder.decode(PageFile.self, from: data)
        guard page.format <= PageFile.currentFormat else {
            throw PageFileError.unsupportedFormat(id: page.id, format: page.format)
        }
        return page
    }

    /// Stable output (sorted keys, ISO 8601 with milliseconds) so unchanged pages produce identical files.
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(Self.dateStyle))
        }
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = try? Date(text, strategy: Self.dateStyle) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "not an ISO 8601 date: \(text)")
            }
            return date
        }
        return decoder
    }()

    private static let dateStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
}
