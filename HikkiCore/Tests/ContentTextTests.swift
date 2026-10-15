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

    @Test func aPageMentionInAHeadingReadsAsItsLabel() {
        let mention: JSONValue = .object([
            "type": .string("mention"), "attrs": .object(["id": .string("p1"), "label": .string("Roadmap")]),
        ])
        let doc = node("doc", [node("heading", [text("See "), mention, text(" first")])])
        #expect(ContentText.headings(in: doc) == ["See @Roadmap first"])
    }

    @Test func collectsTextBlocksWithTheirIdsNestedOnesIncluded() {
        func block(_ type: String, _ id: String?, _ content: [JSONValue]) -> JSONValue {
            var fields: [String: JSONValue] = ["type": .string(type), "content": .array(content)]
            if let id { fields["attrs"] = .object(["id": .string(id)]) }
            return .object(fields)
        }
        let doc = node(
            "doc",
            [
                block("heading", "h1", [text("ので表示理由")]),
                block("paragraph", "p1", [text("雨なので")]),
                node("bulletList", [block("listItem", "li", [block("paragraph", "p2", [text("item")])])]),
                block("callout", "c", [block("paragraph", "p3", [text("inside")])]),
                block("paragraph", "empty", [text("  ")]),
                block("paragraph", nil, [text("no id")]),
                block("codeBlock", "code", [text("let x = 1")]),
            ])
        #expect(
            ContentText.blocks(in: doc) == [
                .init(id: "h1", isHeading: true, text: "ので表示理由"), .init(id: "p1", isHeading: false, text: "雨なので"),
                .init(id: "p2", isHeading: false, text: "item"), .init(id: "p3", isHeading: false, text: "inside"),
                // Stored without an id: found by search, nowhere to land.
                .init(id: "", isHeading: false, text: "no id"), .init(id: "code", isHeading: false, text: "let x = 1"),
            ])
        #expect(ContentText.blocks(in: nil).isEmpty)
    }

    @Test func collectsAttachedAssetsOnceEachWithFileNames() {
        let image: JSONValue = .object([
            "type": .string("image"),
            "attrs": .object(["id": .string("img"), "src": .string("hikki-editor://assets/a1.png"), "alt": .string("")]),
        ])
        let file: JSONValue = .object([
            "type": .string("fileAttachment"),
            "attrs": .object([
                "src": .string("hikki-editor://assets/f1.pdf"), "name": .string("Plan.pdf"), "size": .number(10),
            ]),
        ])
        let web: JSONValue = .object(["type": .string("image"), "attrs": .object(["src": .string("https://x/y.png")])])
        let video: JSONValue = .object([
            "type": .string("video"), "attrs": .object(["src": .string("hikki-editor://assets/v.mp4"), "name": .string("v.mp4")]),
        ])
        let doc = node("doc", [node("paragraph", [text("x")]), image, node("toggle", [file, image]), web, video])
        #expect(
            ContentText.assets(in: doc) == [
                AssetReference(name: "a1.png", blockId: "img"), AssetReference(name: "f1.pdf", label: "Plan.pdf"),
            ])
        #expect(ContentText.assets(in: nil).isEmpty)
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

    @Test func blockTextReadsAsTheEditorsDoes() throws {
        // design/fixtures/content-text.json: the editor's extract.ts is held to the same answers.
        let url = URL(filePath: #filePath).deletingLastPathComponent()
            .appending(path: "../../design/fixtures/content-text.json")
        let fixture = try JSONValue(jsonData: Data(contentsOf: url))
        guard case .object(let fields) = fixture, case .array(let expected)? = fields["blocks"] else {
            Issue.record("fixture without blocks")
            return
        }
        let pairs = expected.compactMap { item -> [String]? in
            guard case .object(let block) = item, case .string(let id)? = block["id"], case .string(let text)? = block["text"]
            else { return nil }
            return [id, text]
        }
        #expect(pairs.count == 7)
        #expect(ContentText.blocks(in: fields["doc"]).map { [$0.id, $0.text] } == pairs)
        #expect(ContentText.headings(in: fields["doc"]) == ["Plan 2026"])
    }

    @Test func oneExtractHoldsHeadingsBlocksAndFiles() {
        let heading: JSONValue = .object([
            "type": .string("heading"), "attrs": .object(["id": .string("h")]), "content": .array([text("Title")]),
        ])
        let file: JSONValue = .object([
            "type": .string("fileAttachment"),
            "attrs": .object(["id": .string("f"), "src": .string("hikki-editor://assets/x.pdf"), "name": .string("X.pdf")]),
        ])
        #expect(
            ContentText.extract(node("doc", [heading, file]))
                == ContentText.Extract(
                    headings: ["Title"], blocks: [.init(id: "h", isHeading: true, text: "Title")],
                    assets: [AssetReference(name: "x.pdf", label: "X.pdf", blockId: "f")]))
    }
}
