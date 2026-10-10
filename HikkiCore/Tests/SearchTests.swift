import Foundation
@testable import HikkiCore
import Testing

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

    @Test func titleMatchesComeBeforeBodyMatches() throws {
        let store = try DocumentStore.inMemory()
        try save(store, "body", "Notes", "the roadmap is due friday")
        try save(store, "title", "Roadmap")
        let hits = try store.search("roadmap")
        #expect(hits.map(\.id) == ["title", "body"])
        #expect(hits[1].snippet.contains("roadmap"))
    }

    @Test func pinyinKeyFollowsTitleEdits() throws {
        let store = try DocumentStore.inMemory()
        try save(store, "a", "路线图")
        try store.saveContent(Snapshot(docId: "a", content: .object([:]), title: "会议", text: "", wordCount: 0))
        #expect(try store.search("lxt").isEmpty)
        #expect(try store.search("huiyi").map(\.id) == ["a"])
    }
}
