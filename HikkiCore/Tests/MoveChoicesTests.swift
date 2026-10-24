import Foundation
import Testing

@testable import HikkiCore

struct MoveChoicesTests {
    private func page(_ id: String, parent: String? = nil, title: String? = nil) -> PageSummary {
        PageSummary(
            id: id, parentId: parent, title: title ?? id.uppercased(), icon: nil, updatedAt: .now, favoritedAt: nil,
            deletedAt: nil, sortKey: 0)
    }

    /// a ─ a1 ─ a1x, a ─ a2; b ─ b1; c
    private var tree: PageTree {
        PageTree([
            page("a"), page("b"), page("c"), page("a1", parent: "a"), page("a2", parent: "a"), page("a1x", parent: "a1"),
            page("b1", parent: "b"),
        ])
    }

    @Test func treeShowsTopLevelPagesUntilOneIsExpanded() {
        let rows = tree.moveChoices(for: "c")
        #expect(rows.map(\.id) == ["a", "b"])
        #expect(rows.map(\.hasChildren) == [true, true])
        #expect(rows.allSatisfy { !$0.isExpanded && $0.depth == 0 && $0.path.isEmpty })

        let open = tree.moveChoices(for: "c", expanded: ["a", "a1"])
        #expect(open.map(\.id) == ["a", "a1", "a1x", "a2", "b"])
        #expect(open.map(\.depth) == [0, 1, 2, 1, 0])
        #expect(open.map(\.isExpanded) == [true, true, false, false, false])
    }

    @Test func neverOffersThePageOrItsSubtree() {
        // Moving a1: not a1, not a1x under it — even with a1 marked expanded.
        let rows = tree.moveChoices(for: "a1", expanded: ["a", "a1"])
        #expect(rows.map(\.id) == ["a", "a2", "b", "c"])
        #expect(!tree.moveChoices(for: "a1", query: "a1").contains { $0.id == "a1" || $0.id == "a1x" })
    }

    @Test func aDisclosureOnlyWhereThereIsSomewhereToGo() {
        // b's only child is the page being moved: nothing to expand.
        let rows = tree.moveChoices(for: "b1", expanded: ["b"])
        #expect(rows.first { $0.id == "b" }?.hasChildren == false)
        #expect(rows.first { $0.id == "b" }?.isExpanded == false)
        #expect(!rows.contains { $0.id == "b1" })
    }

    @Test func marksTheCurrentParent() {
        let rows = tree.moveChoices(for: "a1x", expanded: ["a"])
        #expect(rows.filter(\.isCurrentParent).map(\.id) == ["a1"])
        #expect(tree.moveChoices(for: "c").filter(\.isCurrentParent).isEmpty)
    }

    @Test func searchFoldsCaseAndAccentsAndGivesThePath() {
        let tree = PageTree([
            page("trip", title: "Trip"), page("cafe", parent: "trip", title: "Café Notes"),
            page("other", title: "Recipes"),
        ])
        let rows = tree.moveChoices(for: "other", query: "  CAFE ")
        #expect(rows.map(\.id) == ["cafe"])
        #expect(rows.first?.path == ["Trip"])
        #expect(rows.first?.depth == 0)
        // Every word must be in the title, in any order.
        #expect(tree.moveChoices(for: "other", query: "notes café").map(\.id) == ["cafe"])
        #expect(tree.moveChoices(for: "other", query: "cafe trip").isEmpty)
    }

    @Test func searchPutsTitlesStartingWithTheQueryFirst() {
        let tree = PageTree([
            page("x", title: "Weekly plan"), page("y", title: "Plan B"), page("z", title: "Other"),
        ])
        #expect(tree.moveChoices(for: "z", query: "plan").map(\.id) == ["y", "x"])
    }

    @Test func topLevelIncludesOrphans() {
        let tree = PageTree([page("a"), page("a1", parent: "a"), page("orphan", parent: "gone")])
        #expect(tree.isTopLevel("a"))
        #expect(tree.isTopLevel("orphan"))
        #expect(!tree.isTopLevel("a1"))
    }
}
