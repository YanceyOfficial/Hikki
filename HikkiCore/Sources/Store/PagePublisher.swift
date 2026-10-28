import CloudKit
import CryptoKit
import Foundation

/// Publishes a page: one `PublishedPage` record in the container's public database — the page and its attachments,
/// each as a `CKAsset` — made by the signed-in iCloud account, which alone may change or delete it (the public
/// database's default roles: the world reads, signed-in users create, the creator writes). Two ways (`PublishOptions`):
/// only for people with the link — the payload and files sealed under the link's key (`PublishedContent`), nothing
/// readable on the record — or listed in Hikki Shared — the payload and files as they are, and the fields the
/// website's list queries: `listed` = 1, `title`, `icon`, `excerpt`, `tags`, `author`, `terms` (`PublishSearch`) and
/// `publishedAt`. A page made link-only again has those fields emptied. The site reads a record by name (and lists the
/// listed ones); the app reads one back only to save a copy (`fetchShared`). Limits: `maxBytes` for a page with its
/// attachments, `maxPages` published at once (counted by `PublishedLinks`).
public final class PagePublisher: Sendable {
    public static let recordType = "PublishedPage"
    public static let maxBytes = 20 * 1024 * 1024
    public static let maxPages = 50

    public enum PublishError: Error, Equatable {
        /// The page with its attachments is over `maxBytes`.
        case tooLarge(Int)
        /// `maxPages` are published already.
        case tooMany
        /// No iCloud account on the device: the public database takes records from signed-in users only.
        case notSignedIn
    }

    private let container: CKContainer

    public init(containerID: String = CloudSync.containerID) {
        container = CKContainer(identifier: containerID)
    }

    /// The record and the files that go up, laid out before CloudKit sees them (tested without it).
    struct Upload {
        var link: PublishedLink
        var key: SymmetricKey
        /// The payload as it goes up: sealed for a link, as it is for a listed page.
        var payload: Data
        /// The attachments sealed, in the payload's order.
        var files: [URL]
        var bytes: Int
    }

    /// Lays the payload and the attachments out in temporary files under `scratch` — sealed for a link, as they are
    /// for a listed page: a new link gets a fresh key and record name, an update keeps both (the link stays valid,
    /// whichever way it is published now).
    static func prepare(
        payload: PublishedPayload, assets: [(name: String, file: URL)], existing: PublishedLink?,
        options: PublishOptions = .linkOnly, scratch: URL, now: Date
    ) throws -> Upload {
        let options = options.normalized
        let key = existing.flatMap { PublishedContent.key(from: $0.key) } ?? PublishedContent.makeKey()
        let link = PublishedLink(
            recordName: existing?.recordName ?? UUID().uuidString.lowercased(), key: PublishedContent.keyString(key),
            publishedAt: existing?.publishedAt ?? now, updatedAt: now, listed: options.listed, tags: options.tags,
            author: options.author)
        var sealedPayload = payload
        sealedPayload.publishedAt = link.publishedAt
        sealedPayload.tags = options.tags
        sealedPayload.author = options.author.isEmpty ? nil : options.author
        let data =
            options.listed
            ? try PublishedContent.encoder.encode(sealedPayload) : try PublishedContent.seal(sealedPayload, key: key)
        var bytes = data.count
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        var files: [URL] = []
        for (index, asset) in assets.enumerated() {
            let plain = try Data(contentsOf: asset.file)
            bytes += plain.count
            guard bytes <= maxBytes else { throw PublishError.tooLarge(bytes) }
            let sealed = options.listed ? plain : try PublishedContent.encrypt(plain, key: key)
            let file = scratch.appending(path: "\(index)")
            try sealed.write(to: file, options: .atomic)
            files.append(file)
        }
        guard bytes <= maxBytes else { throw PublishError.tooLarge(bytes) }
        return Upload(link: link, key: key, payload: data, files: files, bytes: bytes)
    }

    /// Publishes the page, or updates its record when `existing` is given; returns the link to copy. `published` is
    /// how many pages are published already (the limit, for a new link); `plainText` gives a listed page its excerpt
    /// and search terms.
    public func publish(
        payload: PublishedPayload, assets: [(name: String, file: URL)], existing: PublishedLink?,
        options: PublishOptions = .linkOnly, plainText: String = "", published: Int, now: Date = .now
    ) async throws -> PublishedLink {
        if existing == nil, published >= Self.maxPages { throw PublishError.tooMany }
        guard try await container.accountStatus() == .available else { throw PublishError.notSignedIn }
        let scratch = FileManager.default.temporaryDirectory.appending(
            path: "hikki-publish-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let upload = try Self.prepare(
            payload: payload, assets: assets, existing: existing, options: options, scratch: scratch, now: now)
        let payloadFile = scratch.appending(path: "payload")
        try upload.payload.write(to: payloadFile, options: .atomic)
        let recordID = CKRecord.ID(recordName: upload.link.recordName)
        let record: CKRecord
        if existing != nil, let current = try? await container.publicCloudDatabase.record(for: recordID) {
            record = current
        } else {
            record = CKRecord(recordType: Self.recordType, recordID: recordID)
        }
        record["version"] = 1 as Int64
        record["bytes"] = Int64(upload.bytes)
        record["payloadFile"] = CKAsset(fileURL: payloadFile)
        record["files"] = upload.files.map { CKAsset(fileURL: $0) }
        for (field, value) in Self.listingFields(payload: payload, link: upload.link, plainText: plainText) {
            record[field] = value
        }
        _ = try await container.publicCloudDatabase.save(record)
        Log.info(
            "page published", category: "publish",
            context: [
                "update": existing == nil ? "no" : "yes", "listed": upload.link.listed ? "yes" : "no", "bytes": "\(upload.bytes)",
                "files": "\(upload.files.count)",
            ])
        return upload.link
    }

    /// The record's readable fields: a listed page's, or every one of them emptied for a link (a page made link-only
    /// again leaves nothing readable behind).
    static func listingFields(payload: PublishedPayload, link: PublishedLink, plainText: String) -> [(String, CKRecordValue?)] {
        guard link.listed else {
            return [
                ("listed", NSNumber(value: 0)), ("title", nil), ("icon", nil), ("excerpt", nil), ("tags", nil), ("terms", nil),
                ("publishedAt", nil), ("author", nil),
            ]
        }
        let terms = PublishSearch.terms([payload.title, plainText].joined(separator: "\n"))
        return [
            ("listed", NSNumber(value: 1)), ("title", payload.title as NSString), ("icon", payload.icon.map { $0 as NSString }),
            ("excerpt", PublishSearch.excerpt(plainText) as NSString), ("tags", link.tags as NSArray),
            // CloudKit refuses an empty list; a page with no words is found by its tags alone.
            ("terms", terms.isEmpty ? nil : terms as NSArray), ("publishedAt", link.publishedAt as NSDate),
            ("author", link.author.isEmpty ? nil : link.author as NSString),
        ]
    }

    /// A shared page as it was published, for saving a copy (the website's "Save to Hikki", `hikki://shared/…`):
    /// the payload and each attachment's bytes, opened with the link's key when the page isn't listed.
    public struct SharedPage: Sendable {
        public var payload: PublishedPayload
        public var files: [(name: String, data: Data)]
    }

    public enum FetchError: Error, Equatable {
        /// Unpublished, or never there.
        case notFound
        /// A page only for people with the link, asked for without its key (or with another one).
        case cannotOpen
    }

    public func fetchShared(recordName: String, key: String?) async throws -> SharedPage {
        let record: CKRecord
        do {
            record = try await container.publicCloudDatabase.record(for: CKRecord.ID(recordName: recordName))
        } catch let error as CKError where error.code == .unknownItem {
            throw FetchError.notFound
        }
        guard record.recordType == Self.recordType, let payloadURL = (record["payloadFile"] as? CKAsset)?.fileURL else {
            throw FetchError.notFound
        }
        let files = ((record["files"] as? [CKAsset]) ?? []).map(\.fileURL)
        return try Self.open(
            listed: (record["listed"] as? Int64) == 1, key: key, payload: try Data(contentsOf: payloadURL),
            files: try files.map { url in try url.map { try Data(contentsOf: $0) } ?? Data() })
    }

    /// The record's payload and files as the reader opens them: as they are for a listed page, opened with the key
    /// otherwise; the files named by the payload's asset list, in its order.
    static func open(listed: Bool, key: String?, payload: Data, files: [Data]) throws -> SharedPage {
        let opened: PublishedPayload
        var contents = files
        if listed {
            opened = try PublishedContent.decoder.decode(PublishedPayload.self, from: payload)
        } else {
            guard let key = key.flatMap(PublishedContent.key(from:)) else { throw FetchError.cannotOpen }
            do {
                opened = try PublishedContent.open(payload, key: key)
                contents = try files.map { try PublishedContent.decrypt($0, key: key) }
            } catch {
                throw FetchError.cannotOpen
            }
        }
        let named = zip(opened.assets, contents).map { (name: $0.0.name, data: $0.1) }
        return SharedPage(payload: opened, files: named)
    }

    /// Takes the page's record down; a record already gone counts as taken down.
    public func unpublish(_ link: PublishedLink) async throws {
        do {
            _ = try await container.publicCloudDatabase.deleteRecord(withID: CKRecord.ID(recordName: link.recordName))
        } catch let error as CKError where error.code == .unknownItem {
            return
        }
        Log.info("page unpublished", category: "publish")
    }
}
