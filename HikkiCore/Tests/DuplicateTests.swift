import Foundation
import Testing

@testable import HikkiCore

struct DuplicateTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let t1 = Date(timeIntervalSince1970: 1_700_000_100)

    @Test func copiesContentAndMetadataRightAfterTheOriginal() throws {
        let s = try DocumentStore.inMemory()
        for id in ["a", "b", "c"] { try s.create(id: id, now: t0) }
        let body = #"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"hello world"}]}]}"#
        _ = try s.saveContent(
            Snapshot(docId: "b", content: try JSONValue(jsonData: Data(body.utf8)), title: "Trip", text: "hello world", wordCount: 2),
            now: t0)
        try s.setIcon("🧭", for: "b", now: t0)
        try s.setFavorite(true, for: "b", now: t0)

        let copy = try #require(try s.duplicate(id: "b", newId: "b2", now: t1))
        #expect(copy.title == "Trip")
        #expect(copy.icon == "🧭")
        #expect(copy.plainText == "hello world")
        #expect(copy.isFavorite == false)
        #expect(copy.createdAt == t1 && copy.updatedAt == t1)
        #expect(try s.pages().filter { $0.parentId == nil }.map(\.id) == ["a", "b", "b2", "c"])
        // Indexed for search like any page.
        #expect(try s.search("hello world").map(\.id).contains("b2"))
    }

    @Test func staysUnderTheSameParentAndSkipsMissingOrTrashedPages() throws {
        let s = try DocumentStore.inMemory()
        try s.create(id: "p", now: t0)
        try s.create(id: "child", parentId: "p", now: t0)
        try s.duplicate(id: "child", newId: "child2", now: t1)
        #expect(try s.pages().filter { $0.parentId == "p" }.map(\.id) == ["child", "child2"])

        #expect(try s.duplicate(id: "nope") == nil)
        try s.moveToTrash(id: "p", now: t1)
        #expect(try s.duplicate(id: "child") == nil)
    }
}
