import Foundation
@testable import HikkiCore
import Testing

struct PageTreeTests {
    private func page(_ id: String, parent: String? = nil, updated: TimeInterval = 0, favorited: TimeInterval? = nil) -> PageSummary {
        PageSummary(id: id, parentId: parent, title: id.uppercased(), icon: nil, updatedAt: Date(timeIntervalSince1970: updated),
                    favoritedAt: favorited.map { Date(timeIntervalSince1970: $0) }, deletedAt: nil, sortKey: 0)
    }

    @Test func buildsNestedTreeInGivenOrder() {
        let tree = PageTree([page("a"), page("b"), page("a1", parent: "a"), page("a2", parent: "a"), page("a1x", parent: "a1")])
        #expect(tree.roots.map(\.id) == ["a", "b"])
        #expect(tree.roots[0].children.map(\.id) == ["a1", "a2"])
        #expect(tree.roots[0].children[0].children.map(\.id) == ["a1x"])
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
        _ = tree.roots // must terminate
    }

    @Test func favoritesAndRecentAreOrdered() {
        let tree = PageTree([page("a", updated: 1, favorited: 5), page("b", updated: 3), page("c", updated: 2, favorited: 9)])
        #expect(tree.favorites.map(\.id) == ["c", "a"])
        #expect(tree.recent(limit: 2).map(\.id) == ["b", "c"])
    }
}
