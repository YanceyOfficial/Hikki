import Foundation
import Testing

@testable import HikkiCore

struct PageDiffTests {
    private func doc(_ json: String) throws -> JSONValue {
        try JSONValue(jsonData: Data(json.utf8))
    }

    @Test func blocksFollowTheReadingOrderWithListsAndNesting() throws {
        let content = try doc(
            #"""
            {"type":"doc","content":[
              {"type":"heading","attrs":{"level":2},"content":[{"type":"text","text":"Plan"}]},
              {"type":"bulletList","content":[{"type":"listItem","content":[
                {"type":"paragraph","content":[{"type":"text","text":"one"}]},
                {"type":"bulletList","content":[{"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"deeper"}]}]}]}
              ]}]},
              {"type":"taskList","content":[{"type":"taskItem","attrs":{"checked":true},"content":[{"type":"paragraph","content":[{"type":"text","text":"done"}]}]}]},
              {"type":"blockquote","content":[{"type":"paragraph","content":[{"type":"text","text":"said"}]}]},
              {"type":"table","content":[{"type":"tableRow","content":[
                {"type":"tableCell","content":[{"type":"paragraph","content":[{"type":"text","text":"a"}]}]},
                {"type":"tableCell","content":[{"type":"paragraph","content":[{"type":"text","text":"b"}]}]}]}]},
              {"type":"image","attrs":{"src":"hikki-editor://assets/x.png","alt":"cat"}},
              {"type":"callout","content":[{"type":"paragraph","content":[{"type":"text","text":"note"}]}]}
            ]}
            """#)
        #expect(
            TextBlock.blocks(in: content) == [
                TextBlock(kind: .heading2, text: "Plan"),
                TextBlock(kind: .bullet, text: "one"),
                TextBlock(kind: .bullet, text: "deeper", depth: 1),
                TextBlock(kind: .taskDone, text: "done"),
                TextBlock(kind: .quote, text: "said"),
                TextBlock(kind: .table, text: "a | b"),
                TextBlock(kind: .media, text: "cat"),
                TextBlock(kind: .paragraph, text: "note", depth: 1),
            ])
        #expect(TextBlock.blocks(in: nil).isEmpty)
    }

    @Test func unchangedAddedRemovedAndEditedBlocks() {
        let old = [
            TextBlock(kind: .heading1, text: "Title"),
            TextBlock(kind: .paragraph, text: "The quick brown fox"),
            TextBlock(kind: .paragraph, text: "Gone for good"),
        ]
        let new = [
            TextBlock(kind: .heading1, text: "Title"),
            TextBlock(kind: .paragraph, text: "The quick red fox"),
            TextBlock(kind: .bullet, text: "Brand new"),
        ]
        let diff = PageDiff.compare(old: old, new: new)
        #expect(diff.map(\.status) == [.same, .changed, .removed, .added])
        #expect(
            diff[1].runs == [
                DiffRun("The quick ", .same), DiffRun("brown", .removed), DiffRun("red", .added), DiffRun(" fox", .same),
            ])
        #expect(diff[2].block.text == "Gone for good")
        #expect(diff[3].block.text == "Brand new")
    }

    @Test func identicalVersionsAreAllTheSame() {
        let blocks = [TextBlock(kind: .paragraph, text: "a"), TextBlock(kind: .paragraph, text: "b")]
        #expect(PageDiff.compare(old: blocks, new: blocks).allSatisfy { $0.status == .same })
        #expect(PageDiff.compare(old: [], new: []).isEmpty)
    }

    @Test func unrelatedReplacementsAreRemovedAndAddedNotEdited() {
        let diff = PageDiff.compare(
            old: [TextBlock(kind: .paragraph, text: "alpha beta gamma")], new: [TextBlock(kind: .paragraph, text: "one two three")])
        #expect(diff.map(\.status) == [.removed, .added])
    }

    @Test func chineseAndJapaneseCompareCharacterByCharacter() {
        let runs = PageDiff.words(old: "今天天气很好", new: "今天天气不好")
        #expect(runs == [DiffRun("今天天气", .same), DiffRun("很", .removed), DiffRun("不", .added), DiffRun("好", .same)])
    }

    @Test func tokensKeepWordsSpacesAndPunctuationApart() {
        #expect(PageDiff.tokens("Hi, there  you") == ["Hi", ",", " ", "there", "  ", "you"])
    }
}
