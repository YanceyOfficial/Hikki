import Foundation
import Testing

@testable import HikkiCore

struct PinyinTests {
    @Test func buildsFullAndInitialKeys() {
        #expect(Pinyin.searchKey(for: "路线图") == "luxiantu lxt")
        #expect(Pinyin.searchKey(for: "Weekly 路线图") == "weeklyluxiantu wlxt")
    }

    @Test func isEmptyWithoutHanCharacters() {
        #expect(Pinyin.searchKey(for: "Weekly sync") == "")
        #expect(Pinyin.searchKey(for: "") == "")
    }
}

struct FuzzyMatchTests {
    @Test func matchesSubsequencesOnly() {
        #expect(FuzzyMatch.score("wkly", in: "Weekly sync") != nil)
        #expect(FuzzyMatch.score("ylkw", in: "Weekly sync") == nil)
        #expect(FuzzyMatch.score("toolong", in: "too") == nil)
    }

    @Test func prefersConsecutiveAndWordStartMatches() throws {
        let prefix = try #require(FuzzyMatch.score("week", in: "Weekly sync"))
        let scattered = try #require(FuzzyMatch.score("week", in: "We sell kiwis"))
        #expect(prefix > scattered)
        let wordStart = try #require(FuzzyMatch.score("sy", in: "Weekly sync"))
        let midWord = try #require(FuzzyMatch.score("sy", in: "Easy yoga"))
        #expect(wordStart > midWord)
    }

    @Test func prefersShorterCandidatesOnTies() throws {
        #expect(try #require(FuzzyMatch.score("map", in: "Map")) > #require(FuzzyMatch.score("map", in: "Map of the world")))
    }
}

struct SearchQueryTests {
    @Test func splitsLowercasesAndDedupes() {
        let query = SearchQuery("  Weekly  SYNC weekly ")
        #expect(query.terms == ["weekly", "sync"])
        #expect(query.joined == "weekly sync")
        #expect(SearchQuery("   ").isEmpty)
    }

    @Test func dropsAccents() {
        #expect(SearchQuery("Café").terms == ["cafe"])
    }
}

struct SearchRankerTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func score(_ query: String, title: String = "", pinyin: String = "", text: String = "", age: TimeInterval = 0)
        -> Int?
    {
        SearchRanker.score(
            SearchQuery(query),
            SearchRanker.Page(title: title, titlePinyin: pinyin, text: text, updatedAt: now.addingTimeInterval(-age)),
            now: now)
    }

    @Test func titlesRankByHowWellTheyMatch() throws {
        let exact = try #require(score("roadmap", title: "Roadmap"))
        let prefix = try #require(score("roadmap", title: "Roadmap 2026"))
        let wordStart = try #require(score("roadmap", title: "Product roadmap"))
        let inside = try #require(score("map", title: "Roadmap"))
        let fuzzy = try #require(score("rdmp", title: "Roadmap"))
        #expect(exact > prefix && prefix > wordStart && wordStart > inside && inside > fuzzy)
        #expect(score("ylkw", title: "Weekly sync") == nil)
    }

    @Test func everyTermCountsAndTextRanksBelowTitles() throws {
        let both = try #require(score("roadmap friday", text: "the roadmap is due friday"))
        let one = try #require(score("roadmap friday", text: "the roadmap is due monday"))
        #expect(both > one)
        let title = try #require(score("roadmap", title: "Roadmap"))
        let text = try #require(score("roadmap", title: "Notes", text: "roadmap roadmap roadmap"))
        #expect(title > text)
        // A page holding every term still beats a loose subsequence of a title.
        let loose = try #require(score("rdmp", title: "Red map"))
        #expect(text > loose)
    }

    @Test func pinyinFindsHanTitles() {
        let key = Pinyin.searchKey(for: "产品路线图")
        #expect(score("lxt", title: "产品路线图", pinyin: key) != nil)
        #expect(score("luxiantu", title: "产品路线图", pinyin: key) != nil)
        #expect(score("cplxt", title: "产品路线图", pinyin: key) != nil)
        #expect(score("huiyi", title: "产品路线图", pinyin: key) == nil)
    }

    @Test func recentPagesComeAheadOnTies() throws {
        let fresh = try #require(score("roadmap", title: "Roadmap", age: 3600))
        let old = try #require(score("roadmap", title: "Roadmap", age: 60 * 86_400))
        #expect(fresh > old)
    }

    @Test func caseAndAccentsDoNotMatter() {
        #expect(score("cafe", title: "Café notes") != nil)
        #expect(score("CAFÉ", text: "a cafe downtown") != nil)
    }

    @Test func snippetSurroundsTheFirstTermAtWordBoundaries() {
        let text =
            "Line one is long enough to be cut.\nThe roadmap is due Friday, after the review with the team.\nMore text follows here."
        let snippet = SearchRanker.snippet(of: text, terms: ["friday", "roadmap"], width: 40)
        #expect(snippet.hasPrefix("…") && snippet.hasSuffix("…"))
        #expect(snippet.contains("roadmap is due Friday"))
        #expect(!snippet.contains("\n"))
        #expect(SearchRanker.snippet(of: text, terms: ["nothing"]) == "")
        #expect(SearchRanker.snippet(of: "short text", terms: ["short"]) == "short text")
    }
}

struct StoreSearchTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private func save(_ store: DocumentStore, _ id: String, _ title: String, _ text: String = "") throws {
        try store.create(id: id, now: t0)
        try store.saveContent(Snapshot(docId: id, content: .object([:]), title: title, text: text, wordCount: 0))
    }

    @Test func findsTitlesByPinyinAndInitials() throws {
        let store = try DocumentStore.inMemory()
        try save(store, "a", "产品路线图")
        try save(store, "b", "Weekly sync")
        #expect(try store.search("luxiantu").map(\.id) == ["a"])
        #expect(try store.search("cplxt").map(\.id) == ["a"])
        #expect(try store.search("wkly").map(\.id) == ["b"])
    }

    @Test func titleMatchesComeBeforeTextMatchesAndCarryWhatTheRowShows() throws {
        let store = try DocumentStore.inMemory()
        try save(store, "text", "Notes", "the roadmap is due friday")
        try save(store, "title", "Roadmap")
        let hits = try store.search("roadmap")
        #expect(hits.map(\.id) == ["title", "text"])
        #expect(hits[0].snippet == "")
        #expect(hits[1].snippet.contains("roadmap"))
        #expect(hits[1].terms == ["roadmap"])
        #expect(hits[1].updatedAt >= t0)
    }

    @Test func pagesHoldingEveryTermComeFirst() throws {
        let store = try DocumentStore.inMemory()
        try save(store, "one", "Notes", "the roadmap is due monday")
        try save(store, "both", "Notes", "the roadmap is due friday")
        let hits = try store.search("roadmap friday")
        #expect(hits.map(\.id) == ["both", "one"])
        #expect(hits[0].terms == ["roadmap", "friday"])
    }

    @Test func shortQueriesSearchTheTextToo() throws {
        let store = try DocumentStore.inMemory()
        try save(store, "a", "周报", "今天的会议记录")
        try save(store, "b", "其他", "没有")
        let hits = try store.search("会议")
        #expect(hits.map(\.id) == ["a"])
        #expect(hits[0].snippet.contains("会议"))
    }

    @Test func pinyinKeyFollowsTitleEdits() throws {
        let store = try DocumentStore.inMemory()
        try save(store, "a", "路线图")
        try store.saveContent(Snapshot(docId: "a", content: .object([:]), title: "会议", text: "", wordCount: 0))
        #expect(try store.search("lxt").isEmpty)
        #expect(try store.search("huiyi").map(\.id) == ["a"])
    }
}
