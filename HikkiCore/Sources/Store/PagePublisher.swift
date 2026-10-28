import CloudKit
import CryptoKit
import Foundation

/// Publishes a page as a read-only link: one `PublishedPage` record in the container's public database — the page
/// and its attachments sealed under the link's key (`PublishedContent`), each as a `CKAsset` — made by the signed-in
/// iCloud account, which alone may change or delete it (the public database's default roles: the world reads,
/// signed-in users create, the creator writes). The site reads the record by name and opens it with the key from
/// the link; the app never reads records back. Limits: `maxBytes` for a page with its attachments, `maxPages`
/// published at once (counted by `PublishedLinks`).
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
        var payload: Data
        /// The attachments sealed, in the payload's order.
        var files: [URL]
        var bytes: Int
    }

    /// Seals the payload and the attachments into temporary files under `scratch`: a new link gets a fresh key and
    /// record name, an update keeps both (the link stays valid).
    static func prepare(
        payload: PublishedPayload, assets: [(name: String, file: URL)], existing: PublishedLink?, scratch: URL, now: Date
    ) throws -> Upload {
        let key = existing.flatMap { PublishedContent.key(from: $0.key) } ?? PublishedContent.makeKey()
        let link = PublishedLink(
            recordName: existing?.recordName ?? UUID().uuidString.lowercased(), key: PublishedContent.keyString(key),
            publishedAt: existing?.publishedAt ?? now, updatedAt: now)
        var sealedPayload = payload
        sealedPayload.publishedAt = link.publishedAt
        let data = try PublishedContent.seal(sealedPayload, key: key)
        var bytes = data.count
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        var files: [URL] = []
        for (index, asset) in assets.enumerated() {
            let plain = try Data(contentsOf: asset.file)
            bytes += plain.count
            guard bytes <= maxBytes else { throw PublishError.tooLarge(bytes) }
            let sealed = try PublishedContent.encrypt(plain, key: key)
            let file = scratch.appending(path: "\(index)")
            try sealed.write(to: file, options: .atomic)
            files.append(file)
        }
        guard bytes <= maxBytes else { throw PublishError.tooLarge(bytes) }
        return Upload(link: link, key: key, payload: data, files: files, bytes: bytes)
    }

    /// Publishes the page, or updates its record when `existing` is given; returns the link to copy. `published` is
    /// how many pages are published already (the limit, for a new link).
    public func publish(
        payload: PublishedPayload, assets: [(name: String, file: URL)], existing: PublishedLink?, published: Int,
        now: Date = .now
    ) async throws -> PublishedLink {
        if existing == nil, published >= Self.maxPages { throw PublishError.tooMany }
        guard try await container.accountStatus() == .available else { throw PublishError.notSignedIn }
        let scratch = FileManager.default.temporaryDirectory.appending(
            path: "hikki-publish-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let upload = try Self.prepare(payload: payload, assets: assets, existing: existing, scratch: scratch, now: now)
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
        _ = try await container.publicCloudDatabase.save(record)
        Log.info(
            "page published", category: "publish",
            context: ["update": existing == nil ? "no" : "yes", "bytes": "\(upload.bytes)", "files": "\(upload.files.count)"])
        return upload.link
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
