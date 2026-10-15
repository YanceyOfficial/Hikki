import Foundation
import Testing

@testable import HikkiSearch

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

    /// A page as the index would offer it for `query`: the terms found in each of its parts.
    private func page(
        _ query: String, title: String = "", pinyin: String = "", headings: String = "", text: String = "",
        attachmentText: String = "", age: TimeInterval = 0, textRank: Int = 0
    ) -> SearchRanker.Page {
        let terms = SearchQuery(query).terms
        func found(_ text: String) -> Int {
            let folded = SearchQuery.fold(text)
            return terms.count { folded.contains($0) }
        }
        return SearchRanker.Page(
            foldedTitle: SearchQuery.fold(title), titlePinyin: pinyin, headingTerms: found(headings),
            textTerms: found(headings + " " + text), fileTerms: found(attachmentText), updatedAt: now.addingTimeInterval(-age),
            textRank: textRank)
    }

    private func score(
        _ query: String, title: String = "", pinyin: String = "", headings: String = "", text: String = "",
        attachmentText: String = "", age: TimeInterval = 0, textRank: Int = 0
    ) -> Int? {
        SearchRanker.score(
            SearchQuery(query),
            page(
                query, title: title, pinyin: pinyin, headings: headings, text: text, attachmentText: attachmentText, age: age,
                textRank: textRank),
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

    @Test func titlesBeatHeadingsBeatTextBeatAttachments() throws {
        let title = try #require(score("roadmap", title: "Roadmap"))
        let heading = try #require(score("roadmap", title: "Notes", headings: "Roadmap\nRisks", text: "Roadmap\n…"))
        let text = try #require(score("roadmap", title: "Notes", text: "the roadmap is due friday"))
        let attachment = try #require(score("roadmap", title: "Notes", attachmentText: "the roadmap is due friday"))
        #expect(title > heading && heading > text && text > attachment)
        #expect(score("roadmap", title: "Notes", text: "nothing", attachmentText: "nothing") == nil)
    }

    @Test func aScopeOnlyCountsMatchesWhereItLooks() throws {
        func scoped(_ scope: SearchScope, _ page: SearchRanker.Page) -> Int? {
            SearchRanker.score(SearchQuery("roadmap"), page, scope: scope, now: now)
        }
        let inTitle = page("roadmap", title: "Roadmap", text: "nothing", textRank: 40)
        let inText = page("roadmap", title: "Notes", headings: "Roadmap", text: "the roadmap", textRank: 40)
        let inFile = page("roadmap", title: "Notes", attachmentText: "roadmap")
        #expect(scoped(.titles, inTitle) != nil)
        #expect(scoped(.titles, inText) == nil)
        #expect(scoped(.titles, inFile) == nil)
        #expect(scoped(.text, inTitle) == nil)
        #expect(scoped(.text, inText) != nil)
        #expect(scoped(.text, inFile) == nil)
        #expect(scoped(.files, inTitle) == nil)
        #expect(scoped(.files, inText) == nil)
        #expect(scoped(.files, inFile) != nil)
        // A page matching in its title and its text scores only the text part under Text.
        let both = page("roadmap", title: "Roadmap", text: "the roadmap")
        #expect(try #require(scoped(.text, both)) < (try #require(scoped(.all, both))))
    }

    @Test func everyTermCountsAndTheIndexOrderBreaksTies() throws {
        let both = try #require(score("roadmap friday", text: "the roadmap is due friday"))
        let one = try #require(score("roadmap friday", text: "the roadmap is due monday"))
        #expect(both > one)
        let ranked = try #require(score("roadmap", text: "roadmap roadmap roadmap", textRank: 40))
        let unranked = try #require(score("roadmap", text: "a roadmap", textRank: 0))
        #expect(ranked > unranked)
        // A page holding every term still beats a loose subsequence of a title.
        let loose = try #require(score("rdmp", title: "Red map"))
        #expect(unranked > loose)
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

    @Test func aLooseTitleMatchCountsOnlyWhenNothingElseMatches() throws {
        // Two letters are a subsequence of most titles.
        #expect(score("ey", title: "Easy yoga") == nil)
        // Scattered letters are no match either.
        #expect(score("abc", title: "xaxxbxxcx") == nil)
        #expect(score("wkly", title: "Weekly sync") != nil)
        // A page whose text holds the term gets nothing for a title that loosely resembles it.
        let plain = try #require(score("rdmp", title: "Notes", text: "rdmp"))
        let resembling = try #require(score("rdmp", title: "Roadmap", text: "rdmp"))
        #expect(plain == resembling)
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

struct BestBlockTests {
    /// Blocks as the index holds them: folded, with whether each is a heading.
    private func folded(_ blocks: [(String, Bool)]) -> [(folded: String, isHeading: Bool)] {
        blocks.map { (SearchQuery.fold($0.0), $0.1) }
    }

    @Test func prefersMoreTermsThenHeadingsThenAStartThenTheEarliest() {
        let blocks = folded([
            ("它是 のですか 的普通形", false), ("ので、早く着くでしょう", false), ("名词化的の ので", true), ("ので表示理由", true),
            ("Weekly sync notes", false),
        ])
        #expect(SearchRanker.bestBlock(["ので"], in: blocks) == 3)
        #expect(SearchRanker.bestBlock(["ので"], in: Array(blocks[0...1])) == 1)
        #expect(SearchRanker.bestBlock(["ので"], in: [blocks[0], blocks[0]]) == 0)
        #expect(SearchRanker.bestBlock(["weekly", "notes"], in: blocks + folded([("Weekly", true)])) == 4)
        #expect(SearchRanker.bestBlock(["cafe"], in: folded([("nothing", false), ("Café", false)])) == 1)
        #expect(SearchRanker.bestBlock(["missing"], in: blocks) == nil)
        #expect(SearchRanker.bestBlock(["ので"], in: []) == nil)
    }
}

struct SearchListItemTests {
    private func hit(_ id: String, matches: Int) -> SearchHit {
        SearchHit(
            id: id, title: id, icon: nil, snippet: "x", updatedAt: .distantPast, terms: ["x"], blockId: "b",
            moreMatches: (0..<matches).map { SearchMatch(blockId: "m\($0)", snippet: "x \($0)") })
    }

    @Test func aPageWithOtherMatchesGetsAToggleThatOpensTheFirstFewThenAll() {
        let hits = [hit("a", matches: 7), hit("b", matches: 0), hit("c", matches: 2)]
        #expect(
            SearchListItem.list(hits, expanded: [], showingAll: []).map(\.id) == ["a", "a#toggle", "b", "c", "c#toggle"])
        #expect(SearchListItem.list(hits, expanded: [], showingAll: [])[1] == .toggle(hits[0], .expand(count: 7)))

        let open = SearchListItem.list(hits, expanded: ["a", "c"], showingAll: [])
        #expect(open.map(\.id) == ["a", "a#m0", "a#m1", "a#m2", "a#m3", "a#m4", "a#toggle", "b", "c", "c#m0", "c#m1", "c#toggle"])
        #expect(open[6] == .toggle(hits[0], .showAll(remaining: 2)))
        #expect(open[11] == .toggle(hits[2], .collapse))

        let all = SearchListItem.list(hits, expanded: ["a"], showingAll: ["a"])
        #expect(all.filter { if case .match = $0 { true } else { false } }.count == 7)
        #expect(all[8] == .toggle(hits[0], .collapse))
    }

    @Test func anAttachmentHitListsNoOtherMatches() {
        var file = hit("f", matches: 3)
        file.attachment = SearchHit.Attachment(name: "a.pdf", label: nil)
        #expect(SearchListItem.list([file], expanded: ["f"], showingAll: []).map(\.id) == ["f"])
    }
}
