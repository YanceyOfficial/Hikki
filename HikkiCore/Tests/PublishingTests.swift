import CloudKit
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

    // MARK: Listed pages (Hikki Shared)

    private func fixture() throws -> [String: JSONValue] {
        let url = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../design/fixtures/publish.json")
        guard case .object(let fields) = try JSONValue(jsonData: Data(contentsOf: url)) else { return [:] }
        return fields
    }

    private func strings(_ value: JSONValue?) -> [String] {
        guard case .array(let items)? = value else { return [] }
        return items.compactMap { if case .string(let s) = $0 { s } else { nil } }
    }

    private func cases(_ value: JSONValue?, input: String) -> [(String, [String])] {
        guard case .array(let items)? = value else { return [] }
        return items.compactMap { item in
            guard case .object(let fields) = item, case .string(let text)? = fields[input] else { return nil }
            return (text, strings(fields["terms"]))
        }
    }

    @Test func theTagsAreTheWebsitesTags() throws {
        #expect(PublishTags.all == strings(try fixture()["tags"]))
    }

    @Test func aPageCarriesItsWordsAsTermsAsTheWebsiteFindsThem() throws {
        let fields = try fixture()
        let pages = cases(fields["terms"], input: "text")
        #expect(pages.count == 7)
        for (text, expected) in pages { #expect(PublishSearch.terms(text) == expected, "\(text)") }
        let queries = cases(fields["queries"], input: "query")
        #expect(queries.count == 5)
        for (query, expected) in queries { #expect(PublishSearch.queryTerms(query) == expected, "\(query)") }
    }

    @Test func optionsKeepKnownTagsInTheListsOrderUpToTheLimit() {
        let options = PublishOptions(listed: true, tags: ["travel", "nope", "study", "food", "tech"]).normalized
        #expect(options.tags == ["study", "tech", "travel"])
        #expect(PublishOptions(listed: false, tags: ["study", "nope"]).normalized.tags == ["study"])
        #expect(PublishOptions(listed: false, author: "  Yancey\nLeo ").normalized.author == "Yancey Leo")
        #expect(PublishOptions(listed: false, author: String(repeating: "a", count: 99)).normalized.author.count == 60)
        #expect(!PublishOptions(listed: true, tags: ["nope"]).isComplete)
        #expect(PublishOptions.linkOnly.isComplete)
    }

    @Test func coversGoWithThePageWhenAReaderCanDrawThem() {
        #expect(PublishedCover.from(PageCover("gradient:ocean"))?.cover == PublishedCover(gradient: "ocean"))
        let unsplash = PublishedCover.from(PageCover("https://images.unsplash.com/photo-1?w=2000#y=30"))
        #expect(unsplash?.cover == PublishedCover(image: "https://images.unsplash.com/photo-1?w=2000", position: 30))
        #expect(unsplash?.asset == nil)
        let uploaded = PublishedCover.from(PageCover("hikki-editor://assets/abc.png"))
        #expect(uploaded?.cover.image == "assets/abc.png")
        #expect(uploaded?.asset == "abc.png")
        #expect(PublishedCover.from(PageCover("data:image/png;base64,AAAA")) == nil)
        // Any other host would learn who reads the page.
        #expect(PublishedCover.from(PageCover("https://tracker.example/pixel.png")) == nil)
        #expect(PublishedCover.from(PageCover("https://images.unsplash.com.evil.example/a.png")) == nil)
        #expect(PublishedCover.from(nil) == nil)
    }

    @Test func saveToHikkiLinksNameTheRecordAndItsKey() throws {
        let linked = SharedLink.parse(try #require(URL(string: "hikki://shared/2164cc13-79da#abcKEY_-")))
        #expect(linked == SharedLink.Target(recordName: "2164cc13-79da", key: "abcKEY_-"))
        let listed = SharedLink.parse(try #require(URL(string: "hikki://shared/2164cc13")))
        #expect(listed == SharedLink.Target(recordName: "2164cc13", key: nil))
        #expect(SharedLink.parse(try #require(URL(string: "hikki://page/2164cc13"))) == nil)
        #expect(SharedLink.parse(try #require(URL(string: "hikki://shared/../etc"))) == nil)
        #expect(SharedLink.parse(try #require(URL(string: "https://shared/abc"))) == nil)
    }

    @Test func aSavedCopyStoresTheCoverAsThePageDid() {
        #expect(PublishedCover(gradient: "ocean").stored(assetURL: { _ in nil }) == "gradient:ocean")
        #expect(
            PublishedCover(image: "https://images.unsplash.com/p?w=1", position: 30).stored(assetURL: { _ in nil })
                == "https://images.unsplash.com/p?w=1#y=30")
        #expect(
            PublishedCover(image: "assets/a.png").stored(assetURL: { "hikki-editor://assets/new-\($0)" })
                == "hikki-editor://assets/new-a.png#y=50")
        #expect(PublishedCover(image: "assets/a.png").stored(assetURL: { _ in nil }) == nil)
        #expect(PublishedCover(image: "http://example.com/a.png").stored(assetURL: { _ in nil }) == nil)
    }

    @Test func thePayloadCarriesTheTagsAndTheAuthor() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let payload = PublishedPayload(
            title: "T", icon: nil, html: "<p>x</p>", assets: [], publishedAt: .now, cover: PublishedCover(gradient: "dusk"))
        let upload = try PagePublisher.prepare(
            payload: payload, assets: [], existing: nil,
            options: PublishOptions(listed: false, tags: ["travel"], author: "Yancey"), scratch: root, now: .now)
        let opened = try PublishedContent.open(upload.payload, key: upload.key)
        #expect(opened.tags == ["travel"])
        #expect(opened.author == "Yancey")
        #expect(opened.cover == PublishedCover(gradient: "dusk"))
        #expect(upload.link.author == "Yancey")
        #expect(upload.link.tags == ["travel"])
    }

    @Test func aListedPageGoesUpReadableAndItsLinkHasNoKey() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let picture = root.appending(path: "a.png")
        try Data([9, 8, 7]).write(to: picture)
        let payload = PublishedPayload(
            title: "Grammar", icon: nil, html: "<p>x</p>", assets: [.init(name: "a.png", type: "image/png")], publishedAt: .now)
        let listed = try PagePublisher.prepare(
            payload: payload, assets: [("a.png", picture)], existing: nil, options: PublishOptions(listed: true, tags: ["study"]),
            scratch: root.appending(path: "s1"), now: Date(timeIntervalSince1970: 10))
        #expect(listed.link.listed && listed.link.tags == ["study"])
        #expect(try Data(contentsOf: listed.files[0]) == Data([9, 8, 7]))
        let opened = try PagePublisher.open(listed: true, key: nil, payload: listed.payload, files: [Data([9, 8, 7])])
        #expect(opened.payload.title == "Grammar" && opened.files.first?.name == "a.png")
        let site = URL(string: "https://hikki.yancey.app")!
        #expect(listed.link.url(site: site).absoluteString == "https://hikki.yancey.app/shared/\(listed.link.recordName)")
        // Made link-only again: the same record and key, sealed once more.
        let sealed = try PagePublisher.prepare(
            payload: payload, assets: [], existing: listed.link, scratch: root.appending(path: "s2"), now: Date(timeIntervalSince1970: 20))
        #expect(!sealed.link.listed && sealed.link.key == listed.link.key && sealed.link.recordName == listed.link.recordName)
        #expect(throws: PagePublisher.FetchError.cannotOpen) {
            try PagePublisher.open(listed: false, key: nil, payload: sealed.payload, files: [])
        }
        #expect(try PagePublisher.open(listed: false, key: sealed.link.key, payload: sealed.payload, files: []).payload.title == "Grammar")
    }

    @Test func aLinkOnlyRecordLeavesNothingReadable() {
        let payload = PublishedPayload(title: "Secret", icon: "🔒", html: "", assets: [], publishedAt: .now)
        let link = PublishedLink(recordName: "r", key: "k", publishedAt: .now, updatedAt: .now)
        let fields = PagePublisher.listingFields(payload: payload, link: link, plainText: "private words")
        func value(_ name: String, in fields: [(String, CKRecordValue?)]) -> CKRecordValue? {
            fields.first { $0.0 == name }?.1 ?? nil
        }
        #expect(value("listed", in: fields) as? NSNumber == 0)
        #expect(fields.filter { $0.0 != "listed" }.allSatisfy { $0.1 == nil })
        var shared = link
        shared.listed = true
        shared.tags = ["study"]
        let listed = PagePublisher.listingFields(payload: payload, link: shared, plainText: "Some words")
        #expect(value("listed", in: listed) as? NSNumber == 1)
        #expect(value("title", in: listed) as? String == "Secret")
        #expect((value("terms", in: listed) as? [String])?.contains("words") == true)
        #expect(value("tags", in: listed) as? [String] == ["study"])
    }

    @Test func aLinkKeptBeforeListingReadsAsLinkOnly() throws {
        let data = Data(#"{"recordName":"r","key":"k","publishedAt":"2026-10-28T00:00:00Z","updatedAt":"2026-10-28T00:00:00Z"}"#.utf8)
        let link = try PublishedContent.decoder.decode(PublishedLink.self, from: data)
        #expect(!link.listed && link.tags.isEmpty)
    }
}
