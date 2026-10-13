import Foundation
import Testing

@testable import HikkiCore

struct PageLinkTests {
    @Test func roundTrips() {
        let id = "6F9619FF-8B86-D011-B42D-00C04FC964FF"
        let url = PageLink.url(for: id)
        #expect(url.absoluteString == "hikki://page/\(id)")
        #expect(PageLink.pageID(from: url) == id)
    }

    @Test func rejectsOtherLinks() {
        for raw in ["https://page/abc", "hikki://settings/abc", "hikki://page/", "hikki://page/a/b"] {
            #expect(PageLink.pageID(from: URL(string: raw)!) == nil, "\(raw)")
        }
    }

    @Test func carriesABlockAsTheFragment() {
        let url = PageLink.url(for: "page-1", block: "blk-9")
        #expect(url.absoluteString == "hikki://page/page-1#blk-9")
        #expect(PageLink.pageID(from: url) == "page-1")
        #expect(PageLink.blockID(from: url) == "blk-9")
        #expect(PageLink.blockID(from: PageLink.url(for: "page-1")) == nil)
        #expect(PageLink.blockID(from: URL(string: "hikki://page/page-1#a/b")!) == nil)
    }
}
