import Foundation
import Testing

@testable import HikkiSearch

struct SearchIndexTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func page(
        _ id: String, _ title: String, text: String = "", headings: [String] = [], at: TimeInterval = 0
    ) -> SearchDocument {
        SearchDocument(id: id, title: title, headings: headings, text: text, updatedAt: t0.addingTimeInterval(at))
    }

    @Test func findsTitlesByPinyinAndInitials() throws {
        let index = try SearchIndex.inMemory()
        try index.index([page("a", "产品路线图"), page("b", "Weekly sync")])
        #expect(try index.search("luxiantu").map(\.id) == ["a"])
        #expect(try index.search("cplxt").map(\.id) == ["a"])
        #expect(try index.search("wkly").map(\.id) == ["b"])
    }

    @Test func titleMatchesComeBeforeTextMatchesAndCarryWhatTheRowShows() throws {
        let index = try SearchIndex.inMemory()
        try index.index([page("text", "Notes", text: "the roadmap is due friday"), page("title", "Roadmap")])
        let hits = try index.search("roadmap")
        #expect(hits.map(\.id) == ["title", "text"])
        #expect(hits[0].snippet == "")
        #expect(hits[1].snippet.contains("roadmap"))
        #expect(hits[1].terms == ["roadmap"])
        #expect(hits[1].updatedAt == t0)
    }

    @Test func headingsOutrankBodyText() throws {
        let index = try SearchIndex.inMemory()
        try index.index([
            page("body", "Notes", text: "we talked about the roadmap at length and then some more"),
            page("heading", "Other notes", text: "Roadmap\nsome text", headings: ["Roadmap"]),
        ])
        #expect(try index.search("roadmap").map(\.id) == ["heading", "body"])
    }

    @Test func pagesHoldingEveryTermComeFirst() throws {
        let index = try SearchIndex.inMemory()
        try index.index([
            page("one", "Notes", text: "the roadmap is due monday"), page("both", "Notes", text: "the roadmap is due friday"),
        ])
        let hits = try index.search("roadmap friday")
        #expect(hits.map(\.id) == ["both", "one"])
        #expect(hits[0].terms == ["roadmap", "friday"])
    }

    @Test func theIndexOrderSeparatesTextMatches() throws {
        let index = try SearchIndex.inMemory()
        try index.index([
            page("once", "Notes", text: "roadmap, mentioned once in a long page " + String(repeating: "filler ", count: 80)),
            page("often", "Notes", text: "roadmap roadmap roadmap: a page about the roadmap"),
        ])
        #expect(try index.search("roadmap").map(\.id) == ["often", "once"])
    }

    @Test func shortQueriesSearchTheTextToo() throws {
        let index = try SearchIndex.inMemory()
        try index.index([page("a", "周报", text: "今天的会议记录"), page("b", "其他", text: "没有")])
        let hits = try index.search("会议")
        #expect(hits.map(\.id) == ["a"])
        #expect(hits[0].snippet.contains("会议"))
    }

    @Test func reindexingReplacesAndRemovingForgets() throws {
        let index = try SearchIndex.inMemory()
        try index.index([page("a", "路线图")])
        #expect(try index.search("lxt").map(\.id) == ["a"])
        try index.index([page("a", "会议", at: 60)])
        #expect(try index.search("lxt").isEmpty)
        #expect(try index.search("huiyi").map(\.id) == ["a"])
        #expect(try index.stamps() == ["a": t0.addingTimeInterval(60)])
        try index.remove(["a", "never-there"])
        #expect(try index.search("huiyi").isEmpty)
        #expect(try index.stamps().isEmpty)
        #expect(index.count == 0)
    }

    @Test func findsChineseTitlesAndTextOnBothPaths() throws {
        let index = try SearchIndex.inMemory()
        try index.index([
            page("a", "Weekly sync", text: "我们讨论了产品路线图和发布计划"), page("b", "路线图", text: "Q4 goals"),
        ])
        // Trigram path (3+ characters): the title hit first, the text hit with an excerpt.
        let hits = try index.search("路线图")
        #expect(hits.map(\.id) == ["b", "a"])
        #expect(hits[1].snippet.contains("路线图"))
        // Short terms (LIKE).
        #expect(try index.search("计划").map(\.id) == ["a"])
        #expect(try index.search("Q4").map(\.id) == ["b"])
    }

    @Test func specialCharactersAreSearchedLiterally() throws {
        let index = try SearchIndex.inMemory()
        try index.index([page("a", "Status", text: "100% \"done\" a_b"), page("b", "Plain", text: "nothing special here")])
        #expect(try index.search("100%").map(\.id) == ["a"])
        #expect(try index.search("\"done\"").map(\.id) == ["a"])
        #expect(try index.search("a_b").map(\.id) == ["a"])
        // LIKE's wildcards are escaped: "_" and "%" mean themselves.
        #expect(try index.search("1_0").isEmpty)
        #expect(try index.search("%").map(\.id) == ["a"])
    }

    @Test func emptyAndBlankQueriesFindNothing() throws {
        let index = try SearchIndex.inMemory()
        try index.index([page("a", "Roadmap")])
        #expect(try index.search("").isEmpty)
        #expect(try index.search("   ").isEmpty)
    }
}
