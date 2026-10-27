import Testing

@testable import HikkiCore

struct AIPageChangeTests {
    /// A change's card shows what it says before it is reviewed, from the texts kept when it was proposed
    /// (ISSUE-255: a card read "Insert / Insert" and nothing else).
    @Test func aPendingChangePreviewsItsText() {
        let insert = AIPageChange(id: "1", kind: .insert, after: "b1", html: "<em>新</em>段", title: "新段", afterText: "新段")
        #expect(insert.preview == [DiffRun("新段", .added)])

        let delete = AIPageChange(id: "2", kind: .delete, block: "b2", title: "删掉重复", beforeText: "She is a teacher.")
        #expect(delete.preview == [DiffRun("She is a teacher.", .removed)])

        let move = AIPageChange(id: "3", kind: .move, block: "b3", after: "b1", title: "放到前面", beforeText: "第二段", afterText: "第二段")
        #expect(move.preview == [DiffRun("第二段", .same)])

        let rewrite = AIPageChange(
            id: "4", kind: .rewrite, block: "b4", html: "He knows it.", title: "He know → He knows", beforeText: "He know it.",
            afterText: "He knows it.")
        #expect(rewrite.preview.contains(DiffRun("know", .removed)))
        #expect(rewrite.preview.contains(DiffRun("knows", .added)))
        #expect(rewrite.preview.contains { $0.change == .same })
    }

    @Test func aChangeWithoutItsTextsPreviewsNothing() {
        // Changes kept by an earlier version carry no texts until they are reviewed.
        #expect(AIPageChange(id: "1", kind: .insert, after: "b1", html: "x", title: "t").preview.isEmpty)
        #expect(AIPageChange(id: "2", kind: .delete, block: "b2", title: "t").preview.isEmpty)
        #expect(AIPageChange(id: "3", kind: .rewrite, block: "b3", html: "x", title: "t").preview.isEmpty)
        // A blank line inserted (an empty paragraph) has nothing to show either.
        #expect(AIPageChange(id: "4", kind: .insert, after: "b1", html: "", title: "空行", afterText: "").preview.isEmpty)
    }
}
