import Testing

@testable import HikkiCore

struct BlockMoveTests {
    private func paragraph(_ text: String) -> JSONValue {
        .object(["type": .string("paragraph"), "content": .array([.object(["type": .string("text"), "text": .string(text)])])])
    }

    private func doc(_ blocks: [JSONValue]) -> JSONValue {
        .object(["type": .string("doc"), "content": .array(blocks)])
    }

    @Test func blocksGoAtTheEnd() {
        #expect(BlockMove.appending([paragraph("moved")], to: doc([paragraph("a")])) == doc([paragraph("a"), paragraph("moved")]))
    }

    @Test func aPageWithOnlyAnEmptyLineTakesThemInItsPlace() {
        let empty: JSONValue = .object(["type": .string("paragraph")])
        #expect(BlockMove.appending([paragraph("moved")], to: doc([empty])) == doc([paragraph("moved")]))
        // An empty line after text stays: only a blank page is replaced.
        #expect(
            BlockMove.appending([paragraph("moved")], to: doc([paragraph("a"), empty]))
                == doc([paragraph("a"), empty, paragraph("moved")]))
        #expect(BlockMove.appending([paragraph("moved")], to: nil) == doc([paragraph("moved")]))
    }

    @Test func textJoinsALineApart() {
        #expect(BlockMove.text("one\ntwo", adding: "three") == "one\ntwo\nthree")
        #expect(BlockMove.text("", adding: "three") == "three")
        #expect(BlockMove.text("one", adding: "") == "one")
    }
}
