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
    }

    @Test func moveTargetsSkipTheSubtreeAndCurrentParent() {
        let tree = PageTree([page("a"), page("b"), page("a1", parent: "a"), page("a1x", parent: "a1"), page("b1", parent: "b")])
        let targets = tree.moveTargets(for: "a1")
        #expect(targets.map(\.page.id) == ["b", "b1"])  // not a1 / a1x (own subtree), not a (already its parent)
        #expect(targets.map(\.depth) == [0, 1])
        #expect(tree.moveTargets(for: "b").map(\.page.id) == ["a", "a1", "a1x"])
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
