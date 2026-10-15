import Foundation
import GRDB
import Synchronization
import Testing

@testable import HikkiSearch

struct SearchIndexTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    /// A page whose headings come first, then a block per line of `text` (blocks without ids, as an index of
    /// stored pages without them would hold).
    private func page(
        _ id: String, _ title: String, text: String = "", headings: [String] = [], at: TimeInterval = 0,
        files: [SearchAttachment] = []
    ) -> SearchDocument {
        let blocks =
            headings.map { SearchBlock(id: "", isHeading: true, text: $0) }
            + text.split(separator: "\n").map { SearchBlock(id: "", text: String($0)) }
        return SearchDocument(id: id, title: title, blocks: blocks, attachments: files, updatedAt: t0.addingTimeInterval(at))
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "search-\(UUID().uuidString).sqlite")
    }

    @Test func semanticSearchsLeftoverTablesAreDropped() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let old = try DatabaseQueue(path: url.path)
        try await old.write { db in
            try db.execute(sql: "CREATE TABLE chunk (pageId TEXT, vector BLOB)")
            try db.execute(sql: "PRAGMA user_version = \(SearchIndex.version)")
        }
        try old.close()
        let index = try SearchIndex(url: url)
        try index.index([page("a", "Kept")])
        #expect(try await index.writer.read { try $0.tableExists("chunk") } == false)
        #expect(try await index.search("kept").map(\.id) == ["a"])
    }

    @Test func findsTitlesByPinyinAndInitials() async throws {
        let index = try SearchIndex.inMemory()
        try index.index([page("a", "产品路线图"), page("b", "Weekly sync")])
        #expect(try await index.search("luxiantu").map(\.id) == ["a"])
        #expect(try await index.search("cplxt").map(\.id) == ["a"])
        #expect(try await index.search("wkly").map(\.id) == ["b"])
    }

    @Test func titleMatchesComeBeforeTextMatchesAndCarryWhatTheRowShows() async throws {
        let index = try SearchIndex.inMemory()
        try index.index([page("text", "Notes", text: "the roadmap is due friday"), page("title", "Roadmap")])
        let hits = try await index.search("roadmap")
        #expect(hits.map(\.id) == ["title", "text"])
        #expect(hits[0].snippet == "")
        #expect(hits[1].snippet.contains("roadmap"))
        #expect(hits[1].terms == ["roadmap"])
        #expect(hits[1].updatedAt == t0)
    }

    @Test func aTextHitNamesItsBestBlockAndShowsTheExcerptFromThere() async throws {
        let index = try SearchIndex.inMemory()
        let blocks = [
            SearchBlock(id: "p1", text: "它是 のですか 的普通形"),
            SearchBlock(id: "h1", isHeading: true, text: "ので表示理由"),
            SearchBlock(id: "p2", text: "雨なので、家にいます。"),
        ]
        try index.index([
            SearchDocument(id: "a", title: "N4 文法", blocks: blocks, updatedAt: t0), page("old", "Older", text: "雨なので"),
        ])
        let hits = try await index.search("ので")
        let hit = try #require(hits.first { $0.id == "a" })
        #expect(hit.blockId == "h1")
        #expect(hit.snippet.hasPrefix("ので表示理由 雨なので"))
        // The other blocks holding a term, in reading order, each with its own excerpt.
        #expect(hit.moreMatches.map(\.blockId) == ["p1", "p2"])
        #expect(hit.moreMatches.map(\.snippet) == ["它是 のですか 的普通形", "雨なので、家にいます。"])
        #expect(hit.moreMatchCount == 2)
        // Blocks without ids (nothing to land on): the excerpt as before, no block.
        let old = try #require(hits.first { $0.id == "old" })
        #expect(old.blockId == nil)
        #expect(old.snippet.contains("ので"))
        // Titles carry no block.
        #expect(try await index.search("文法", options: SearchOptions(scope: .titles)).first?.blockId == nil)
    }

    @Test func accentedTextMatchesWithAndWithoutAccents() async throws {
        let index = try SearchIndex.inMemory()
        try index.index([
            SearchDocument(id: "a", title: "Drinks", blocks: [SearchBlock(id: "p1", text: "Café au lait")], updatedAt: t0)
        ])
        for query in ["cafe", "café", "CAFÉ", "au"] {
            let hit = try #require(try await index.search(query).first, "\(query)")
            #expect(hit.blockId == "p1")
            #expect(hit.snippet == "Café au lait")
        }
    }

    @Test func headingsOutrankBodyText() async throws {
        let index = try SearchIndex.inMemory()
        try index.index([
            page("body", "Notes", text: "we talked about the roadmap at length and then some more"),
            page("heading", "Other notes", text: "some text", headings: ["Roadmap"]),
        ])
        #expect(try await index.search("roadmap").map(\.id) == ["heading", "body"])
    }

    @Test func pagesHoldingEveryTermComeFirst() async throws {
        let index = try SearchIndex.inMemory()
        try index.index([
            page("one", "Notes", text: "the roadmap is due monday"),
            // The terms in different blocks still count for the page.
            page("both", "Notes", text: "the roadmap\nis due friday"),
        ])
        let hits = try await index.search("roadmap friday")
        #expect(hits.map(\.id) == ["both", "one"])
        #expect(hits[0].terms == ["roadmap", "friday"])
    }

    @Test func theIndexOrderSeparatesTextMatches() async throws {
        let index = try SearchIndex.inMemory()
        try index.index([
            page("once", "Notes", text: "roadmap, mentioned once in a long page " + String(repeating: "filler ", count: 80)),
            page("often", "Notes", text: "roadmap roadmap roadmap: a page about the roadmap"),
        ])
        #expect(try await index.search("roadmap").map(\.id) == ["often", "once"])
    }

    @Test func everyPageHoldingATermIsACandidateHoweverManyThereAre() async throws {
        let index = try SearchIndex.inMemory()
        var documents = (0..<250).map { page("n\($0)", "Note \($0)", text: "roadmap roadmap roadmap") }
        documents.append(
            page("target", "Plan", text: "roadmap " + String(repeating: "filler ", count: 200) + " friday", at: 60))
        try index.index(documents)
        // Holding both terms beats 250 pages that say one of them more often.
        #expect(try await index.search("roadmap friday").first?.id == "target")
        // The newest page holding the term, however low its BM25.
        #expect(try await index.search("roadmap", options: SearchOptions(sort: .edited), limit: 5).first?.id == "target")
        #expect(try await index.search("roadmap", limit: 300).count == 251)
    }

    @Test func shortQueriesSearchTheTextToo() async throws {
        let index = try SearchIndex.inMemory()
        try index.index([page("a", "周报", text: "今天的会议记录"), page("b", "其他", text: "没有")])
        let hits = try await index.search("会议")
        #expect(hits.map(\.id) == ["a"])
        #expect(hits[0].snippet.contains("会议"))
    }

    @Test func reindexingReplacesAndRemovingForgets() async throws {
        let index = try SearchIndex.inMemory()
        try index.index([page("a", "路线图", text: "old words")])
        #expect(try await index.search("lxt").map(\.id) == ["a"])
        try index.index([page("a", "会议", text: "new words", at: 60.123_456)])
        #expect(try await index.search("lxt").isEmpty)
        #expect(try await index.search("old").isEmpty)
        #expect(try await index.search("huiyi").map(\.id) == ["a"])
        // Edited times come back exactly as given.
        #expect(try index.stamps() == ["a": t0.addingTimeInterval(60.123_456)])
        #expect(
            try index.stamps(of: ["a", "b"]) == ["a": SearchStamp(title: "会议", icon: nil, updatedAt: t0.addingTimeInterval(60.123_456))])
        try index.remove(["a", "never-there"])
        #expect(try await index.search("huiyi").isEmpty)
        #expect(try await index.search("new").isEmpty)
        #expect(try index.stamps().isEmpty)
        #expect(index.count == 0)
    }

    @Test func findsChineseTitlesAndTextOnBothPaths() async throws {
        let index = try SearchIndex.inMemory()
        try index.index([
            page("a", "Weekly sync", text: "我们讨论了产品路线图和发布计划"), page("b", "路线图", text: "Q4 goals"),
        ])
        // Trigram path (3+ characters): the title hit first, the text hit with an excerpt.
        let hits = try await index.search("路线图")
        #expect(hits.map(\.id) == ["b", "a"])
        #expect(hits[1].snippet.contains("路线图"))
        // Short terms (scanned).
        #expect(try await index.search("计划").map(\.id) == ["a"])
        #expect(try await index.search("Q4").map(\.id) == ["b"])
    }

    @Test func specialCharactersAreSearchedLiterally() async throws {
        let index = try SearchIndex.inMemory()
        try index.index([page("a", "Status", text: "100% \"done\" a_b"), page("b", "Plain", text: "nothing special here")])
        #expect(try await index.search("100%").map(\.id) == ["a"])
        #expect(try await index.search("\"done\"").map(\.id) == ["a"])
        #expect(try await index.search("a_b").map(\.id) == ["a"])
        // No wildcards: "_" and "%" mean themselves.
        #expect(try await index.search("1_0").isEmpty)
        #expect(try await index.search("%").map(\.id) == ["a"])
    }

    @Test func listsTheFirstFiftyOtherMatchesAndCountsThemAll() async throws {
        let index = try SearchIndex.inMemory()
        let blocks = (0..<80).map { SearchBlock(id: "b\($0)", text: "match number \($0)") }
        try index.index([SearchDocument(id: "a", title: "Long", blocks: blocks, updatedAt: t0)])
        let hit = try #require(try await index.search("match").first)
        #expect(hit.blockId == "b0")
        #expect(hit.moreMatchCount == 79)
        #expect(hit.moreMatches.count == 50)
        #expect(hit.moreMatches.first?.blockId == "b1")
        #expect(SearchListItem.list([hit], expanded: [], showingAll: [])[1] == .toggle(hit, .expand(count: 79)))
    }

    @Test func aCancelledSearchStops() async throws {
        let index = try SearchIndex.inMemory()
        try index.index([page("a", "Roadmap", text: "the roadmap")])
        let task = Task { () async throws -> [SearchHit] in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await index.search("roadmap")
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    // MARK: Attached files

    @Test func attachmentsAreSearchedAndNamedWhenOnlyTheyMatch() async throws {
        let index = try SearchIndex.inMemory()
        try index.index([
            page(
                "a", "Trip", text: "photos below",
                files: [
                    SearchAttachment(name: "p1.png", blockId: "img"),
                    SearchAttachment(name: "f1.pdf", label: "Plan.pdf", blockId: "file"),
                ]),
            page("b", "Roadmap notes", text: "the roadmap itself"),
        ])
        #expect(try index.unreadFiles() == ["f1.pdf", "p1.png"])
        try index.setFileText("ROADMAP\nQ4 milestones", named: "p1.png")
        try index.setFileText("budget for the quarter", named: "f1.pdf")
        #expect(try index.unreadFiles().isEmpty)
        let hits = try await index.search("roadmap")
        #expect(hits.map(\.id) == ["b", "a"])
        // The page's own text matched: no attachment named.
        #expect(hits[0].attachment == nil)
        // Only the image matched: its excerpt, the attachment it came from (an image has no file name), and the
        // block showing it, where the page opens.
        #expect(hits[1].attachment == SearchHit.Attachment(name: "p1.png", label: nil))
        #expect(hits[1].snippet.contains("ROADMAP"))
        #expect(hits[1].blockId == "img")
        let budget = try await index.search("budget")
        #expect(budget.map(\.id) == ["a"])
        #expect(budget[0].attachment?.label == "Plan.pdf")
        #expect(budget[0].blockId == "file")
        // Short terms reach attachments too.
        #expect(try await index.search("Q4").map(\.id) == ["a"])
    }

    @Test func fileTextIsSharedByNameAndOutlivesThePage() async throws {
        let index = try SearchIndex.inMemory()
        let shared = SearchAttachment(name: "shared.pdf", label: "s.pdf")
        try index.index([page("a", "A", files: [shared, SearchAttachment(name: "only-a.png")]), page("b", "B", files: [shared])])
        #expect(try index.unreadFiles(among: ["shared.pdf"]) == ["shared.pdf"])
        try index.setFileText("common words", named: "shared.pdf")
        try index.setFileText("alpha", named: "only-a.png")
        #expect(Set(try await index.search("common").map(\.id)) == ["a", "b"])
        // The file leaves page a: its text no longer finds it.
        try index.index([page("a", "A", files: [shared])])
        #expect(try await index.search("alpha").isEmpty)
        // Trashed and restored: found again with nothing to read.
        try index.remove(["a"])
        #expect(try await index.search("common").map(\.id) == ["b"])
        try index.index([page("a", "A", files: [shared])])
        #expect(try index.unreadFiles().isEmpty)
        #expect(Set(try await index.search("common").map(\.id)) == ["a", "b"])
    }

    @Test func anUnreadableFileIsNotAskedForAgainAndMatchesNothing() async throws {
        let index = try SearchIndex.inMemory()
        try index.index([page("a", "A", files: [SearchAttachment(name: "broken.pdf")])])
        try index.setFileText(nil, named: "broken.pdf")
        #expect(try index.unreadFiles().isEmpty)
        #expect(try index.hasFileText(named: "broken.pdf"))
        #expect(try await index.search("broken").isEmpty)
    }

    @Test func aNewLayoutKeepsTheFileTexts() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let index = try SearchIndex(url: url)
            try index.index([page("a", "A", files: [SearchAttachment(name: "f.pdf")])])
            try index.setFileText("kept text", named: "f.pdf")
            try await index.writer.write { try $0.execute(sql: "PRAGMA user_version = 1") }
        }
        let index = try SearchIndex(url: url)
        #expect(index.count == 0)
        try index.index([page("a", "A", files: [SearchAttachment(name: "f.pdf")])])
        #expect(try index.unreadFiles().isEmpty)
        #expect(try await index.search("kept").map(\.id) == ["a"])
    }

    @Test func version3sFileTextsMoveOver() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let old = try DatabaseQueue(path: url.path)
        try await old.write { db in
            try db.execute(sql: "CREATE TABLE attachment (name TEXT, pageId TEXT, label TEXT, text TEXT)")
            try db.execute(sql: "INSERT INTO attachment VALUES ('f.pdf', 'a', 'F.pdf', 'Café budget')")
            try db.execute(sql: "PRAGMA user_version = 3")
        }
        try old.close()
        let index = try SearchIndex(url: url)
        #expect(try index.hasFileText(named: "f.pdf"))
        try index.index([page("a", "A", files: [SearchAttachment(name: "f.pdf", label: "F.pdf")])])
        #expect(try index.unreadFiles().isEmpty)
        #expect(try await index.search("cafe").first?.attachment?.label == "F.pdf")
    }

    /// Three pages that each hold "roadmap" in one place only: the title, the text (a heading), an attached file.
    private func scopedIndex() throws -> SearchIndex {
        let index = try SearchIndex.inMemory()
        try index.index([
            page("title", "Roadmap", text: "nothing else here", at: 10),
            page("text", "Notes", text: "the roadmap is due", headings: ["Roadmap"], at: 30),
            page("file", "Trip", text: "photos below", at: 20, files: [SearchAttachment(name: "f.pdf", label: "Plan.pdf")]),
        ])
        try index.setFileText("roadmap Q4", named: "f.pdf")
        return index
    }

    @Test func scopesLimitWhereTheTermsMayMatch() async throws {
        let index = try scopedIndex()
        #expect(try await index.search("roadmap").map(\.id) == ["title", "text", "file"])
        #expect(try await index.search("roadmap", options: SearchOptions(scope: .titles)).map(\.id) == ["title"])
        #expect(try await index.search("roadmap", options: SearchOptions(scope: .text)).map(\.id) == ["text"])
        let files = try await index.search("roadmap", options: SearchOptions(scope: .files))
        #expect(files.map(\.id) == ["file"])
        // A file match always names the file and shows its text.
        #expect(files[0].attachment?.label == "Plan.pdf")
        #expect(files[0].snippet.contains("roadmap"))
        // Short terms (the scan) follow the scope too.
        #expect(try await index.search("Q4", options: SearchOptions(scope: .text)).isEmpty)
        #expect(try await index.search("Q4", options: SearchOptions(scope: .files)).map(\.id) == ["file"])
    }

    @Test func aFileScopeShowsTheFileEvenWhenThePageTextMatchesToo() async throws {
        let index = try SearchIndex.inMemory()
        try index.index([page("a", "Notes", text: "budget talk", files: [SearchAttachment(name: "b.pdf", label: "Budget.pdf")])])
        try index.setFileText("budget 2027", named: "b.pdf")
        #expect(try await index.search("budget").first?.attachment == nil)
        let hit = try #require(try await index.search("budget", options: SearchOptions(scope: .files)).first)
        #expect(hit.attachment?.label == "Budget.pdf")
        #expect(hit.snippet.contains("2027"))
        // Titles show no excerpt.
        try index.index([page("t", "Budget")])
        #expect(try await index.search("budget", options: SearchOptions(scope: .titles)).map(\.snippet) == [""])
    }

    @Test func sortingByEditedTimePutsTheNewestFirst() async throws {
        let index = try scopedIndex()
        #expect(try await index.search("roadmap", options: SearchOptions(sort: .edited)).map(\.id) == ["text", "file", "title"])
        #expect(
            try await index.search("roadmap", options: SearchOptions(scope: .titles, sort: .edited)).map(\.id) == ["title"])
    }

    @Test func emptyAndBlankQueriesFindNothing() async throws {
        let index = try SearchIndex.inMemory()
        try index.index([page("a", "Roadmap")])
        #expect(try await index.search("").isEmpty)
        #expect(try await index.search("   ").isEmpty)
    }
}

struct FileTextReaderTests {
    private func index(_ names: [String]) throws -> SearchIndex {
        let index = try SearchIndex.inMemory()
        try index.index([
            SearchDocument(
                id: "a", title: "A", attachments: names.map { SearchAttachment(name: $0) }, updatedAt: .distantPast)
        ])
        return index
    }

    @Test func aFileAskedForTwiceIsReadOnce() async throws {
        let index = try index(["a.pdf", "b.png"])
        let reads = Mutex<[String]>([])
        let reader = FileTextReader(index: index) { name in
            reads.withLock { $0.append(name) }
            try? await Task.sleep(for: .milliseconds(20))
            return .text("text of \(name)")
        }
        await reader.enqueue(["a.pdf", "b.png", "a.pdf"])
        // While the first is being read: asked again (another page, an autosave).
        await reader.enqueue(["a.pdf", "b.png"])
        await reader.idle()
        await reader.enqueue(try index.unreadFiles())
        await reader.enqueue(["a.pdf"])
        await reader.idle()
        #expect(reads.withLock { $0 } == ["a.pdf", "b.png"])
        #expect(try await index.search("text").map(\.id) == ["a"])
    }

    @Test func anUnreadableFileIsTriedOnceAndAMissingOneAgainLater() async throws {
        let index = try index(["broken.pdf", "later.png"])
        let reads = Mutex<[String]>([])
        let reader = FileTextReader(index: index) { name in
            reads.withLock { $0.append(name) }
            return name == "broken.pdf" ? .unreadable : .missing
        }
        await reader.enqueue(try index.unreadFiles())
        await reader.idle()
        #expect(try index.unreadFiles() == ["later.png"])
        await reader.enqueue(try index.unreadFiles())
        await reader.idle()
        #expect(reads.withLock { $0 } == ["broken.pdf", "later.png", "later.png"])
    }
}
