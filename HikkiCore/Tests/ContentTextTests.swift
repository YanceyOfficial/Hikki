import Foundation
import Testing

@testable import HikkiCore

struct ContentTextTests {
    private func text(_ s: String) -> JSONValue { .object(["type": .string("text"), "text": .string(s)]) }
    private func node(_ type: String, _ content: [JSONValue] = []) -> JSONValue {
        .object(["type": .string(type), "content": .array(content)])
    }

    @Test func collectsHeadingsInOrderNestedOnesIncluded() {
        let doc = node(
            "doc",
            [
                node("heading", [text("Plan "), text("2026")]),
                node("paragraph", [text("body")]),
                node("toggle", [node("paragraph", [text("summary")]), node("heading", [text("Inside")])]),
                node("heading", [text("  ")]),
                node("heading", [text("Two"), .object(["type": .string("hardBreak")]), text("lines")]),
            ])
        #expect(ContentText.headings(in: doc) == ["Plan 2026", "Inside", "Two lines"])
        #expect(ContentText.headings(in: nil).isEmpty)
        #expect(ContentText.headings(in: .string("not a document")).isEmpty)
    }

    @Test func aRecordReadsItsHeadingsFromItsContent() throws {
        let t0 = Date(timeIntervalSince1970: 0)
        var record = DocumentRecord(
            id: "a", title: "T", content: nil, plainText: "", wordCount: 0, createdAt: t0, updatedAt: t0, parentId: nil,
            icon: nil, cover: nil, favoritedAt: nil, deletedAt: nil, sortKey: 0)
        #expect(record.headings.isEmpty)
        record.content = #"{"type":"doc","content":[{"type":"heading","attrs":{"level":2},"content":[{"type":"text","text":"H"}]}]}"#
        #expect(record.headings == ["H"])
    }
}
