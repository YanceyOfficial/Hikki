import CryptoKit
import Foundation
import Testing

@testable import HikkiCore

struct PublishingTests {
    private func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "publish-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func thePayloadSealsAndOpensUnderItsKey() throws {
        let key = PublishedContent.makeKey()
        let payload = PublishedPayload(
            title: "Trip", icon: "✈️", html: "<h1>Trip</h1><p>Plans.</p><img src=\"assets/a.png\">",
            assets: [.init(name: "a.png", type: "image/png")], publishedAt: Date(timeIntervalSince1970: 1_800_000_000))
        let sealed = try PublishedContent.seal(payload, key: key)
        #expect(!String(decoding: sealed, as: UTF8.self).contains("Plans"))
        #expect(try PublishedContent.open(sealed, key: key) == payload)
        // Another key opens nothing.
        #expect(throws: PublishedContent.ContentError.cannotOpen) {
            try PublishedContent.open(sealed, key: PublishedContent.makeKey())
        }
    }

    @Test func theKeyTravelsAsBase64urlInTheLink() throws {
        let key = PublishedContent.makeKey()
        let string = PublishedContent.keyString(key)
        #expect(!string.contains("+") && !string.contains("/") && !string.contains("="))
        #expect(string.count == 43)
        let back = try #require(PublishedContent.key(from: string))
        #expect(back.withUnsafeBytes { Data($0) } == key.withUnsafeBytes { Data($0) })
        #expect(PublishedContent.key(from: "short") == nil)
        let link = PublishedLink(recordName: "abc-123", key: string, publishedAt: .now, updatedAt: .now)
        #expect(link.url(site: URL(string: "https://hikki.yancey.app")!).absoluteString == "https://hikki.yancey.app/p/abc-123#\(string)")
    }

    @Test func anUploadSealsEveryAttachmentAndKeepsAnExistingLink() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let picture = root.appending(path: "a.png")
        try Data([1, 2, 3, 4]).write(to: picture)
        let payload = PublishedPayload(
            title: "T", icon: nil, html: "<p>x</p>", assets: [.init(name: "a.png", type: "image/png")], publishedAt: .now)
        let first = try PagePublisher.prepare(
            payload: payload, assets: [("a.png", picture)], existing: nil, scratch: root.appending(path: "s1"),
            now: Date(timeIntervalSince1970: 1000))
        #expect(first.files.count == 1)
        #expect(try PublishedContent.decrypt(try Data(contentsOf: first.files[0]), key: first.key) == Data([1, 2, 3, 4]))
        #expect(try PublishedContent.open(first.payload, key: first.key).publishedAt == Date(timeIntervalSince1970: 1000))
        #expect(first.link.publishedAt == Date(timeIntervalSince1970: 1000))
        // An update: the same record and key (the link stays valid), a later update time.
        let second = try PagePublisher.prepare(
            payload: payload, assets: [], existing: first.link, scratch: root.appending(path: "s2"), now: Date(timeIntervalSince1970: 2000))
        #expect(second.link.recordName == first.link.recordName)
        #expect(second.link.key == first.link.key)
        #expect(second.link.publishedAt == first.link.publishedAt)
        #expect(second.link.updatedAt == Date(timeIntervalSince1970: 2000))
        #expect(try PublishedContent.open(second.payload, key: first.key).title == "T")
    }

    @Test func aPagePastTheLimitIsRefusedBeforeAnythingGoesUp() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let big = root.appending(path: "big.bin")
        try Data(count: PagePublisher.maxBytes + 1).write(to: big)
        let payload = PublishedPayload(
            title: "T", icon: nil, html: "", assets: [.init(name: "big.bin", type: "application/octet-stream")], publishedAt: .now)
        #expect(throws: PagePublisher.PublishError.self) {
            try PagePublisher.prepare(
                payload: payload, assets: [("big.bin", big)], existing: nil, scratch: root.appending(path: "s"), now: .now)
        }
    }

    @Test func linksAreKeptPerPageInTheWorkspaceFolder() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let links = PublishedLinks(root: root)
        #expect(links.link(of: "p1") == nil)
        #expect(links.count() == 0)
        let link = PublishedLink(
            recordName: "r1", key: "k", publishedAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 2))
        try links.save(link, for: "p1")
        #expect(links.link(of: "p1") == link)
        #expect(links.count() == 1)
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "published/p1.json").path))
        try links.remove(for: "p1")
        #expect(links.link(of: "p1") == nil)
        #expect(links.count() == 0)
        // An id that isn't a page id names no file.
        try links.save(link, for: "../x")
        #expect(links.link(of: "../x") == nil)
    }

    @Test func mediaTypesFollowTheExtension() {
        #expect(PublishedContent.mediaType(forExtension: "PNG") == "image/png")
        #expect(PublishedContent.mediaType(forExtension: "pdf") == "application/pdf")
        #expect(PublishedContent.mediaType(forExtension: "xyz") == "application/octet-stream")
    }
}
