import Testing

@testable import HikkiCore

struct EditorSelectionTests {
    @Test func aPassageGoesOnlyWithItsOwnPage() {
        let selection = EditorSelection(docId: "a", text: "the passage")
        #expect(selection.text(in: "a") == "the passage")
        #expect(selection.text(in: "b") == nil)  // asked about another page: not sent with it
        #expect(selection.text(in: nil) == nil)  // asked about no page at all
    }
}
