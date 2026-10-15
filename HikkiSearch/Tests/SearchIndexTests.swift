import Foundation
import GRDB
import Testing

@testable import HikkiSearch

struct SearchIndexTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func semanticSearchsLeftoverTablesAreDropped() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "search-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let old = try DatabaseQueue(path: url.path)
        try old.write { db in
            try db.execute(sql: "CREATE TABLE chunk (pageId TEXT, vector BLOB)")
            try db.execute(sql: "PRAGMA user_version = \(SearchIndex.version)")
        }
        try old.close()
        let index = try SearchIndex(url: url)
        try index.index([page("a", "Kept")])
        #expect(try index.queue.read { try $0.tableExists("chunk") } == false)
        #expect(try index.search("kept").map(\.id) == ["a"])
    }

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

    @Test func attachmentsAreSearchedAndNamedWhenOnlyTheyMatch() throws {
        let index = try SearchIndex.inMemory()
        try index.index([page("a", "Trip", text: "photos below"), page("b", "Roadmap notes", text: "the roadmap itself")])
        try index.index(attachments: [
            SearchAttachment(name: "p1.png", pageId: "a", label: nil, text: "ROADMAP\nQ4 milestones"),
            SearchAttachment(name: "f1.pdf", pageId: "a", label: "Plan.pdf", text: "budget for the quarter"),
        ])
        let hits = try index.search("roadmap")
        #expect(hits.map(\.id) == ["b", "a"])
        // The page's own text matched: no attachment named.
        #expect(hits[0].attachment == nil)
        // Only the image matched: its excerpt, and the attachment it came from (an image has no file name).
        #expect(hits[1].attachment == SearchHit.Attachment(name: "p1.png", label: nil))
        #expect(hits[1].snippet.contains("ROADMAP"))
        let budget = try index.search("budget")
        #expect(budget.map(\.id) == ["a"])
        #expect(budget[0].attachment?.label == "Plan.pdf")
        // Short terms reach attachments too.
        #expect(try index.search("Q4").map(\.id) == ["a"])
    }

    @Test func attachmentsFollowTheirPageAndAreSharedByName() throws {
        let index = try SearchIndex.inMemory()
        try index.index([page("a", "A"), page("b", "B")])
        try index.index(attachments: [
            SearchAttachment(name: "shared.pdf", pageId: "a", label: "s.pdf", text: "common words"),
            SearchAttachment(name: "shared.pdf", pageId: "b", label: "s.pdf", text: "common words"),
            SearchAttachment(name: "only-a.png", pageId: "a", text: "alpha"),
        ])
        #expect(try index.attachmentNames(of: "a") == ["shared.pdf", "only-a.png"])
        #expect(try index.attachmentText(named: "shared.pdf") == "common words")
        #expect(try index.attachmentText(named: "nope.pdf") == nil)
        #expect(Set(try index.search("common").map(\.id)) == ["a", "b"])
        try index.removeAttachments(["only-a.png"], of: "a")
        #expect(try index.search("alpha").isEmpty)
        try index.remove(["a"])
        #expect(try index.search("common").map(\.id) == ["b"])
        #expect(try index.attachmentNames(of: "a").isEmpty)
    }

    /// Three pages that each hold "roadmap" in one place only: the title, the text (a heading), an attached file.
    private func scopedIndex() throws -> SearchIndex {
        let index = try SearchIndex.inMemory()
        try index.index([
            page("title", "Roadmap", text: "nothing else here", at: 10),
            page("text", "Notes", text: "Roadmap\nthe roadmap is due", headings: ["Roadmap"], at: 30),
            page("file", "Trip", text: "photos below", at: 20),
        ])
        try index.index(attachments: [SearchAttachment(name: "f.pdf", pageId: "file", label: "Plan.pdf", text: "roadmap Q4")])
        return index
    }

    @Test func scopesLimitWhereTheTermsMayMatch() throws {
        let index = try scopedIndex()
        #expect(try index.search("roadmap").map(\.id) == ["title", "text", "file"])
        #expect(try index.search("roadmap", options: SearchOptions(scope: .titles)).map(\.id) == ["title"])
        #expect(try index.search("roadmap", options: SearchOptions(scope: .text)).map(\.id) == ["text"])
        let files = try index.search("roadmap", options: SearchOptions(scope: .files))
        #expect(files.map(\.id) == ["file"])
        // A file match always names the file and shows its text.
        #expect(files[0].attachment?.label == "Plan.pdf")
        #expect(files[0].snippet.contains("roadmap"))
        // Short terms (the LIKE path) follow the scope too.
        #expect(try index.search("Q4", options: SearchOptions(scope: .text)).isEmpty)
        #expect(try index.search("Q4", options: SearchOptions(scope: .files)).map(\.id) == ["file"])
    }

    @Test func aFileScopeShowsTheFileEvenWhenThePageTextMatchesToo() throws {
        let index = try SearchIndex.inMemory()
        try index.index([page("a", "Notes", text: "budget talk")])
        try index.index(attachments: [SearchAttachment(name: "b.pdf", pageId: "a", label: "Budget.pdf", text: "budget 2027")])
        #expect(try index.search("budget").first?.attachment == nil)
        let hit = try #require(try index.search("budget", options: SearchOptions(scope: .files)).first)
        #expect(hit.attachment?.label == "Budget.pdf")
        #expect(hit.snippet.contains("2027"))
        // Titles show no excerpt.
        try index.index([page("t", "Budget")])
        #expect(try index.search("budget", options: SearchOptions(scope: .titles)).map(\.snippet) == [""])
    }

    @Test func sortingByEditedTimePutsTheNewestFirst() throws {
        let index = try scopedIndex()
        #expect(try index.search("roadmap", options: SearchOptions(sort: .edited)).map(\.id) == ["text", "file", "title"])
        #expect(
            try index.search("roadmap", options: SearchOptions(scope: .titles, sort: .edited)).map(\.id) == ["title"])
    }

    @Test func emptyAndBlankQueriesFindNothing() throws {
        let index = try SearchIndex.inMemory()
        try index.index([page("a", "Roadmap")])
        #expect(try index.search("").isEmpty)
        #expect(try index.search("   ").isEmpty)
    }
}
