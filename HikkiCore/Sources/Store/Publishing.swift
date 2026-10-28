import CryptoKit
import Foundation

/// A page's published link (page ⋯ → Publish Link): the public-database record that holds it (`PagePublisher`) and
/// the key that opens it. CloudKit's public database holds only what the key encrypts; the key travels in the link's
/// fragment (`#…`), which browsers never send to a server — so anyone with the link reads the page, and nobody
/// without it, iCloud included.
public struct PublishedLink: Codable, Equatable, Sendable {
    public var recordName: String
    /// The content key, base64url without padding (the link's fragment).
    public var key: String
    public var publishedAt: Date
    /// When the record was last written (an update).
    public var updatedAt: Date

    public init(recordName: String, key: String, publishedAt: Date, updatedAt: Date) {
        self.recordName = recordName
        self.key = key
        self.publishedAt = publishedAt
        self.updatedAt = updatedAt
    }

    /// The link itself: the site's reader with the record's name, the key as the fragment.
    public func url(site: URL) -> URL {
        let page = site.appending(path: "p/\(recordName)")
        var components = URLComponents(url: page, resolvingAgainstBaseURL: false)
        components?.fragment = key
        return components?.url ?? page
    }
}

/// What a published record holds once decrypted: the page as the editor exports it (HTML, its attachments linked
/// as `assets/<name>`), and the attachments by name in the order their files follow.
public struct PublishedPayload: Codable, Equatable, Sendable {
    public struct Asset: Codable, Equatable, Sendable {
        public var name: String
        /// The file's media type as far as its extension says (`image/png`); the reader needs it for its blob.
        public var type: String

        public init(name: String, type: String) {
            self.name = name
            self.type = type
        }
    }

    public static let currentFormat = 1

    public var format: Int
    public var title: String
    public var icon: String?
    public var html: String
    public var assets: [Asset]
    public var publishedAt: Date

    public init(title: String, icon: String?, html: String, assets: [Asset], publishedAt: Date) {
        format = Self.currentFormat
        self.title = title
        self.icon = icon
        self.html = html
        self.assets = assets
        self.publishedAt = publishedAt
    }
}

/// The encryption behind a published link: AES-GCM under a 256-bit key made per link, the sealed box's nonce,
/// ciphertext and tag together (`combined`), the key written base64url for the link.
public enum PublishedContent {
    public enum ContentError: Error, Equatable {
        case badKey
        case cannotOpen
    }

    public static func makeKey() -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }

    public static func keyString(_ key: SymmetricKey) -> String {
        key.withUnsafeBytes { Data($0) }.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func key(from string: String) -> SymmetricKey? {
        var base64 = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64), data.count == 32 else { return nil }
        return SymmetricKey(data: data)
    }

    public static func encrypt(_ data: Data, key: SymmetricKey) throws -> Data {
        guard let combined = try AES.GCM.seal(data, using: key).combined else { throw ContentError.badKey }
        return combined
    }

    public static func decrypt(_ data: Data, key: SymmetricKey) throws -> Data {
        do {
            return try AES.GCM.open(try AES.GCM.SealedBox(combined: data), using: key)
        } catch {
            throw ContentError.cannotOpen
        }
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// The payload sealed for the record.
    public static func seal(_ payload: PublishedPayload, key: SymmetricKey) throws -> Data {
        try encrypt(try encoder.encode(payload), key: key)
    }

    /// The record's payload opened (the reader's side, and tests).
    public static func open(_ data: Data, key: SymmetricKey) throws -> PublishedPayload {
        try decoder.decode(PublishedPayload.self, from: try decrypt(data, key: key))
    }

    /// A file's media type by its extension, for the payload's asset list.
    public static func mediaType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "gif": "image/gif"
        case "webp": "image/webp"
        case "heic": "image/heic"
        case "svg": "image/svg+xml"
        case "pdf": "application/pdf"
        case "mp4", "m4v": "video/mp4"
        case "mov": "video/quicktime"
        case "mp3": "audio/mpeg"
        case "m4a": "audio/mp4"
        case "wav": "audio/wav"
        default: "application/octet-stream"
        }
    }
}

/// The workspace's published links, one file per page — `published/<page id>.json` in the workspace folder, so every
/// device of the workspace sees a page is published, updates the same record and takes it down.
public final class PublishedLinks: Sendable {
    public static let folderName = "published"
    static let currentFormat = 1

    struct File: Codable {
        var format: Int
        var link: PublishedLink
    }

    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    private var folder: URL { root.appending(path: Self.folderName, directoryHint: .isDirectory) }

    private func file(for pageID: String) -> URL? {
        guard PageFiles.isValid(pageID) else { return nil }
        return folder.appending(path: "\(pageID).json")
    }

    /// The page's link, if it is published.
    public func link(of pageID: String) -> PublishedLink? {
        guard let file = file(for: pageID), let data = try? Data(contentsOf: file) else { return nil }
        guard let decoded = try? PublishedContent.decoder.decode(File.self, from: data), decoded.format <= Self.currentFormat
        else { return nil }
        return decoded.link
    }

    public func save(_ link: PublishedLink, for pageID: String) throws {
        guard let file = file(for: pageID) else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = try PublishedContent.encoder.encode(File(format: Self.currentFormat, link: link))
        try FileLocks.shared.withLock(file) { try data.write(to: file, options: .atomic) }
    }

    public func remove(for pageID: String) throws {
        guard let file = file(for: pageID), FileManager.default.fileExists(atPath: file.path) else { return }
        try FileLocks.shared.withLock(file) { try FileManager.default.removeItem(at: file) }
    }

    /// How many pages are published (the publisher's limit counts these).
    public func count() -> Int {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".json") }.count
    }
}
