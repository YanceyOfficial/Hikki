import Foundation
import Testing

@testable import HikkiCore

struct LinkPreviewTests {
    private let base = URL(string: "https://www.yanceyleo.com/posts/a")!

    @Test func readsOpenGraphFirstThenPlainTags() {
        let html = """
            <!doctype html><html><head>
            <meta charset="utf-8"><title>  Plain   title </title>
            <meta name="description" content="Plain description">
            <meta property="og:title" content="Yancey Blog">
            <meta property='og:description' content="Thoughts &amp; stories about technology, design, and life">
            <link rel="icon" href="/favicon.svg"><link rel="apple-touch-icon" href="/apple-touch-icon.png">
            </head><body><meta property="og:title" content="not in the head"></body></html>
            """
        let preview = LinkPreview.parse(html: html, url: base)
        #expect(preview.title == "Yancey Blog")
        #expect(preview.description == "Thoughts & stories about technology, design, and life")
        #expect(preview.icon == "https://www.yanceyleo.com/apple-touch-icon.png")
    }

    @Test func fallsBackToTitleTagAndFavicon() {
        let html = "<html><head><TITLE>Caf&eacute; &#8212; &#x4E2D;文</TITLE><meta name=description content=Short></head></html>"
        let preview = LinkPreview.parse(html: html, url: base)
        #expect(preview.title == "Caf&eacute; — 中文")
        #expect(preview.description == "Short")
        #expect(preview.icon == "https://www.yanceyleo.com/favicon.ico")
    }

    @Test func iconsResolveAndOnlyWebOnesCount() {
        let relative = LinkPreview.parse(html: #"<head><link rel="shortcut icon" href="img/i.png"></head>"#, url: base)
        #expect(relative.icon == "https://www.yanceyleo.com/posts/img/i.png")
        let data = LinkPreview.parse(html: #"<head><link rel="icon" href="data:image/png;base64,AAAA"></head>"#, url: base)
        #expect(data.icon == nil)
        let empty = LinkPreview.parse(html: "", url: base)
        #expect(empty.title == nil && empty.description == nil)
    }

    @Test func longTextIsCut() {
        let long = String(repeating: "word ", count: 200)
        let preview = LinkPreview.parse(html: "<head><meta name=\"description\" content=\"\(long)\"></head>", url: base)
        #expect((preview.description?.count ?? 0) == 300)
        #expect(preview.description?.hasSuffix("…") == true)
    }

    @Test func onlyPublicHostsAreFetched() async throws {
        for ip in ["8.8.8.8", "1.1.1.1", "2606:4700:4700::1111", "198.18.0.1"] {
            #expect(PublicHost.isPublic(try #require(PublicHost.bytes(of: ip))), "\(ip)")
        }
        for ip in [
            "127.0.0.1", "10.0.0.5", "192.168.1.1", "172.16.0.1", "169.254.169.254", "100.64.0.1", "0.0.0.0", "::1",
            "fe80::1", "fc00::1", "::ffff:127.0.0.1", "2001:db8::1", "224.0.0.1",
        ] {
            #expect(!PublicHost.isPublic(try #require(PublicHost.bytes(of: ip))), "\(ip)")
        }
        for url in [
            "http://localhost:8080/", "https://127.0.0.1/", "http://[::1]/", "https://printer.local/", "file:///etc/hosts",
            "ftp://example.com/", "http://169.254.169.254/latest/meta-data/",
        ] {
            await #expect(throws: PublicHost.Refused.self) { try await PublicHost.check(URL(string: url)!) }
        }
    }

    @Test func hostilePagesStayCheapToRead() {
        // No closing tags anywhere, half a megabyte of it: parsing must stay quick (and find nothing odd).
        let junk = "<head><title>" + String(repeating: "<meta content=x ", count: 30_000)
        let start = Date()
        let preview = LinkPreview.parse(html: junk, url: base)
        // Linear parsing takes a few milliseconds; quadratic would take minutes. The bound is loose so a busy machine
        // (parallel builds) can't fail it.
        #expect(Date().timeIntervalSince(start) < 5)
        #expect(preview.title == nil)
    }
}
