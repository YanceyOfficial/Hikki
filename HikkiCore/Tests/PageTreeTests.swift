import Foundation
import Testing

@testable import HikkiCore

struct PageTreeTests {
    private func page(_ id: String, parent: String? = nil, updated: TimeInterval = 0, favorited: TimeInterval? = nil) -> PageSummary {
        PageSummary(
            id: id, parentId: parent, title: id.uppercased(), icon: nil, updatedAt: Date(timeIntervalSince1970: updated),
            favoritedAt: favorited.map { Date(timeIntervalSince1970: $0) }, deletedAt: nil, sortKey: 0)
    }

    @Test func buildsNestedTreeInGivenOrder() {
        let tree = PageTree([page("a"), page("b"), page("a1", parent: "a"), page("a2", parent: "a"), page("a1x", parent: "a1")])
        #expect(tree.roots.map(\.id) == ["a", "b"])
        #expect(tree.roots[0].children.map(\.id) == ["a1", "a2"])
        #expect(tree.roots[0].children[0].children.map(\.id) == ["a1x"])
        // Every page, depth first (the editors' link index).
        #expect(tree.all.map(\.id) == ["a", "a1", "a1x", "a2", "b"])
    }

    @Test func orphansSurfaceAtTheTopLevel() {
        let tree = PageTree([page("a"), page("orphan", parent: "gone")])
        #expect(tree.roots.map(\.id) == ["a", "orphan"])
    }

    @Test func pathRunsRootToPage() {
        let tree = PageTree([page("a"), page("a1", parent: "a"), page("a1x", parent: "a1")])
        #expect(tree.path(to: "a1x").map(\.id) == ["a", "a1", "a1x"])
        #expect(tree.path(to: "missing").isEmpty)
    }

    @Test func subpageCountTakesEveryDepth() {
        let tree = PageTree([page("a"), page("b"), page("a1", parent: "a"), page("a2", parent: "a"), page("a1x", parent: "a1")])
        #expect(tree.subpageCount(of: "a") == 3)  // a1, a1x, a2 go to the trash with it
        #expect(tree.subpageCount(of: "a1") == 1)
        #expect(tree.subpageCount(of: "b") == 0)
        #expect(tree.subpageCount(of: "missing") == 0)
    }

    @Test func survivesParentCycles() {
        let tree = PageTree([page("a", parent: "b"), page("b", parent: "a")])
        #expect(tree.path(to: "a").count <= 2)
        _ = tree.roots  // must terminate
    }

    @Test func favoritesAndRecentAreOrdered() {
        let tree = PageTree([page("a", updated: 1, favorited: 5), page("b", updated: 3), page("c", updated: 2, favorited: 9)])
        #expect(tree.favorites.map(\.id) == ["c", "a"])
        #expect(tree.recent(limit: 2).map(\.id) == ["b", "c"])
    }
}

struct DropDestinationTests {
    private let tree = PageTree([
        PageSummary(id: "a", parentId: nil, title: "a", icon: nil, updatedAt: .now, favoritedAt: nil, deletedAt: nil, sortKey: 0),
        PageSummary(id: "b", parentId: nil, title: "b", icon: nil, updatedAt: .now, favoritedAt: nil, deletedAt: nil, sortKey: 1),
        PageSummary(id: "c", parentId: nil, title: "c", icon: nil, updatedAt: .now, favoritedAt: nil, deletedAt: nil, sortKey: 2),
        PageSummary(id: "a1", parentId: "a", title: "a1", icon: nil, updatedAt: .now, favoritedAt: nil, deletedAt: nil, sortKey: 0),
    ])

    @Test func zonesSplitTheRowIntoQuarters() {
        #expect(DropZone(y: 2, height: 30) == .before)
        #expect(DropZone(y: 15, height: 30) == .inside)
        #expect(DropZone(y: 28, height: 30) == .after)
    }

    @Test func beforeAndAfterUseTheTargetsSiblingsWithoutTheDraggedPage() {
        // Dragging c before b → index 1 among [a, b]; after a → index 1 too.
        #expect(tree.destination(dropping: "c", onto: "b", zone: .before) == .init(parentId: nil, index: 1))
        #expect(tree.destination(dropping: "c", onto: "a", zone: .after) == .init(parentId: nil, index: 1))
        // Dragging a (top) after c → end of [b, c].
        #expect(tree.destination(dropping: "a", onto: "c", zone: .after) == .init(parentId: nil, index: 2))
        // Dragging a top-level page next to a child moves it into that level.
        #expect(tree.destination(dropping: "c", onto: "a1", zone: .before) == .init(parentId: "a", index: 0))
    }

    @Test func insideNestsAtTheEnd() {
        #expect(tree.destination(dropping: "b", onto: "a", zone: .inside) == .init(parentId: "a", index: .max))
    }

    @Test func invalidDropsReturnNil() {
        #expect(tree.destination(dropping: "a", onto: "a", zone: .inside) == nil)
        #expect(tree.destination(dropping: "a", onto: "a1", zone: .inside) == nil)  // into its own child
        #expect(tree.destination(dropping: "a", onto: "a1", zone: .after) == nil)  // beside its own child
        #expect(tree.destination(dropping: "ghost", onto: "a", zone: .inside) == nil)
    }
}

/// The sidebar's flattened rows (`PageTree.visibleRows`).
struct SidebarRowsTests {
    private func page(_ id: String, parent: String? = nil, updated: TimeInterval = 0) -> PageSummary {
        PageSummary(
            id: id, parentId: parent, title: id.uppercased(), icon: nil, updatedAt: Date(timeIntervalSince1970: updated),
            favoritedAt: nil, deletedAt: nil, sortKey: 0)
    }

    @Test func visibleRowsFollowExpansionDepthFirst() {
        let tree = PageTree([page("a"), page("b"), page("a1", parent: "a"), page("a2", parent: "a"), page("a1x", parent: "a1")])
        #expect(tree.visibleRows(expanded: []).map(\.id) == ["a", "b"])
        let open = tree.visibleRows(expanded: ["a", "a1"])
        #expect(open.map(\.id) == ["a", "a1", "a1x", "a2", "b"])
        #expect(open.map(\.depth) == [0, 1, 2, 1, 0])
        #expect(open.map(\.hasChildren) == [true, true, false, false, false])
        #expect(open.map(\.isExpanded) == [true, true, false, false, false])
        // An expanded page under a collapsed one stays hidden.
        #expect(tree.visibleRows(expanded: ["a1"]).map(\.id) == ["a", "b"])
        // A leaf in `expanded` doesn't count as open.
        #expect(tree.visibleRows(expanded: ["b"]).last?.isExpanded == false)
    }

    @Test func visibleRowsIgnoreEditedTimeAndWordCount() {
        var edited = page("a", updated: 100)
        edited.wordCount = 42
        let before = PageTree([page("a"), page("b")]).visibleRows(expanded: [])
        let after = PageTree([edited, page("b")]).visibleRows(expanded: [])
        #expect(before == after)
        var renamed = page("a")
        renamed.title = "Renamed"
        #expect(PageTree([renamed, page("b")]).visibleRows(expanded: []) != before)
    }
}
