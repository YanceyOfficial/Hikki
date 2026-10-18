import Foundation
import Testing

@testable import HikkiCore

struct NavigationTabsTests {
    typealias Tabs = NavigationTabs<String>

    @Test func navigateBuildsHistoryAndBackForwardMove() {
        var tabs = Tabs(initial: "home")
        tabs.navigate(to: "a")
        tabs.navigate(to: "b")
        #expect(tabs.route == "b")
        tabs.goBack()
        #expect(tabs.route == "a")
        #expect(tabs.active.canGoForward)
        tabs.goForward()
        #expect(tabs.route == "b")
        tabs.goForward()
        #expect(tabs.route == "b")
    }

    @Test func navigatingAfterBackDropsForwardHistory() {
        var tabs = Tabs(initial: "home")
        tabs.navigate(to: "a")
        tabs.navigate(to: "b")
        tabs.goBack()
        tabs.navigate(to: "c")
        #expect(tabs.active.history == ["home", "a", "c"])
        #expect(!tabs.active.canGoForward)
    }

    @Test func navigatingToTheCurrentRouteIsANoOp() {
        var tabs = Tabs(initial: "home")
        tabs.navigate(to: "home")
        #expect(tabs.active.history == ["home"])
    }

    @Test func historyIsCapped() {
        var tabs = Tabs(initial: "0")
        tabs.maxHistory = 3
        for i in 1...5 { tabs.navigate(to: "\(i)") }
        #expect(tabs.active.history == ["3", "4", "5"])
        #expect(tabs.route == "5")
    }

    @Test func tabsHaveIndependentHistories() {
        var tabs = Tabs(initial: "home")
        tabs.navigate(to: "a")
        let first = tabs.activeID
        tabs.openTab("b")
        tabs.navigate(to: "c")
        tabs.select(first)
        #expect(tabs.route == "a")
        tabs.goBack()
        #expect(tabs.route == "home")
    }

    @Test func newTabsOpenRightOfTheActiveOne() {
        var tabs = Tabs(initial: "1")
        let one = tabs.activeID
        tabs.openTab("2")
        tabs.select(one)
        tabs.openTab("3")
        #expect(tabs.tabs.map(\.route) == ["1", "3", "2"])
    }

    @Test func aPageDroppedBetweenTabsOpensThereOrFocusesItsTab() {
        var tabs = Tabs(initial: "1")
        tabs.openTab("2")
        tabs.openTab("x", at: 1)
        #expect(tabs.tabs.map(\.route) == ["1", "x", "2"])
        #expect(tabs.route == "x")
        // Clamped: past the end appends, below zero prepends.
        tabs.openTab("y", at: 99)
        tabs.openTab("z", at: -3)
        #expect(tabs.tabs.map(\.route) == ["z", "1", "x", "2", "y"])
        // Already open: that tab is focused, nothing is added.
        let before = tabs.tabs.map(\.id)
        tabs.openTab("x", at: 0)
        #expect(tabs.tabs.map(\.id) == before)
        #expect(tabs.route == "x")
    }

    @Test func aPageDroppedOntoATabShowsThereAndKeepsItsHistory() {
        var tabs = Tabs(initial: "1")
        let first = tabs.activeID
        tabs.navigate(to: "a")
        tabs.openTab("2")
        tabs.navigate(first, to: "dropped")
        #expect(tabs.activeID == first)
        #expect(tabs.route == "dropped")
        tabs.goBack()
        #expect(tabs.route == "a")
        // An unknown tab id changes nothing.
        let snapshot = tabs
        tabs.navigate(UUID(), to: "nowhere")
        #expect(tabs == snapshot)
    }

    @Test func closingFocusesRightNeighbourThenLeft() {
        var tabs = Tabs(initial: "1")
        tabs.openTab("2")
        let two = tabs.activeID
        tabs.openTab("3")
        tabs.select(two)
        let closedTwo = tabs.close(two)
        #expect(closedTwo)
        #expect(tabs.route == "3")
        let closedThree = tabs.close(tabs.activeID)
        #expect(closedThree)
        #expect(tabs.route == "1")
        let closedLast = tabs.close(tabs.activeID)
        #expect(closedLast == false)  // last tab stays
    }

    @Test func selectNeighborWraps() {
        var tabs = Tabs(initial: "1")
        tabs.openTab("2")
        tabs.selectNeighbor(1)
        #expect(tabs.route == "1")
        tabs.selectNeighbor(-1)
        #expect(tabs.route == "2")
    }

    @Test func pruneRemovesGoneRoutesAndFallsBack() {
        var tabs = Tabs(initial: "home")
        tabs.navigate(to: "a")
        tabs.navigate(to: "home")
        tabs.navigate(to: "x")
        let first = tabs.activeID
        tabs.openTab("x")
        tabs.prune(fallback: "home") { $0 == "x" }
        #expect(tabs.route == "home")  // the tab that only had "x"
        tabs.select(first)
        #expect(tabs.active.history == ["home", "a", "home"])
        #expect(tabs.route == "home")
    }

    @Test func prunedIsUnchangedWhenNothingIsGone() {
        var tabs = Tabs(initial: "home")
        tabs.navigate(to: "a")
        tabs.openTab("b")
        tabs.navigate(to: "c")
        // Nothing gone: an equal value (the navigator then skips assigning it, so no window re-renders).
        #expect(tabs.pruned(fallback: "home") { _ in false } == tabs)
        let pruned = tabs.pruned(fallback: "home") { $0 == "c" }
        #expect(pruned != tabs)
        #expect(pruned.route == "b")
        #expect(tabs.route == "c")  // the original is untouched
    }

    @Test func sidebarPicksFocusTheirTabOrOpenOneAndKeepTheLatestFew() {
        var tabs = Tabs(initial: "home")
        tabs.openRecent("a", limit: 3)
        tabs.openRecent("b", limit: 3)
        #expect(tabs.tabs.map(\.route) == ["home", "a", "b"])
        // Already open: focused, nothing added.
        tabs.openRecent("a", limit: 3)
        #expect(tabs.tabs.map(\.route) == ["home", "a", "b"])
        #expect(tabs.route == "a")
        // A fourth closes the least recently focused (home), not the order's first by accident.
        tabs.openRecent("c", limit: 3)
        #expect(tabs.tabs.map(\.route) == ["a", "b", "c"])
        tabs.select(tabs.tabs[0].id)  // a
        tabs.openRecent("d", limit: 3)
        #expect(tabs.tabs.map(\.route) == ["a", "c", "d"])
        #expect(tabs.route == "d")
    }

    @Test func recencySurvivesJSONAndOlderDataWithoutIt() throws {
        var tabs = Tabs(initial: "home")
        tabs.openTab("a")
        tabs.select(tabs.tabs[0].id)
        let decoded = try JSONDecoder().decode(Tabs.self, from: JSONEncoder().encode(tabs))
        #expect(decoded.recency == tabs.recency)
        let old =
            #"{"tabs":[{"id":"00000000-0000-0000-0000-000000000001","history":["x"],"position":0},{"id":"00000000-0000-0000-0000-000000000002","history":["y"],"position":0}],"activeID":"00000000-0000-0000-0000-000000000002","maxHistory":50}"#
        let legacy = try JSONDecoder().decode(Tabs.self, from: Data(old.utf8))
        #expect(legacy.recency.first == legacy.activeID)
        #expect(legacy.recency.count == 2)
    }

    @Test func roundTripsThroughJSON() throws {
        var tabs = Tabs(initial: "home")
        tabs.navigate(to: "a")
        tabs.openTab("b")
        let decoded = try JSONDecoder().decode(Tabs.self, from: JSONEncoder().encode(tabs))
        #expect(decoded == tabs)
    }

    // MARK: The tab menu

    @Test func newTabToTheRightOpensRightAfterThatTab() {
        var tabs = Tabs(initial: "a")
        let a = tabs.activeID
        tabs.openTab("b")
        tabs.openTab("c")
        let new = tabs.openTab("home", after: a)
        #expect(tabs.tabs.map(\.route) == ["a", "home", "b", "c"])
        #expect(tabs.activeID == new)
    }

    @Test func duplicateCopiesHistoryAndPlaceRightAfterTheTab() throws {
        var tabs = Tabs(initial: "home")
        tabs.navigate(to: "a")
        tabs.navigate(to: "b")
        tabs.goBack()
        let original = tabs.activeID
        tabs.openTab("c")
        let duplicated = tabs.duplicate(original)
        let copy = try #require(duplicated)
        #expect(tabs.tabs.map(\.id)[1] == copy)
        #expect(tabs.activeID == copy)
        #expect(tabs.active.history == ["home", "a", "b"])
        #expect(tabs.route == "a")
        #expect(tabs.active.canGoForward)
        #expect(copy != original)
        let missing = tabs.duplicate(UUID())
        #expect(missing == nil)
    }

    @Test func closeOthersKeepsOnlyThatTabFocused() {
        var tabs = Tabs(initial: "a")
        tabs.openTab("b")
        let b = tabs.activeID
        tabs.openTab("c")
        tabs.closeOthers(b)
        #expect(tabs.tabs.map(\.route) == ["b"])
        #expect(tabs.activeID == b)
        #expect(tabs.recency == [b])
        tabs.closeOthers(UUID())
        #expect(tabs.tabs.count == 1)
    }

    @Test func closeToTheRightFocusesTheTabWhenTheActiveOneCloses() {
        var tabs = Tabs(initial: "a")
        let a = tabs.activeID
        tabs.openTab("b")
        let b = tabs.activeID
        tabs.openTab("c")
        tabs.closeTabs(after: b)
        #expect(tabs.tabs.map(\.route) == ["a", "b"])
        #expect(tabs.activeID == b)
        let open = Set(tabs.tabs.map(\.id))
        #expect(Set(tabs.recency).isSubset(of: open))
        tabs.select(a)
        tabs.closeTabs(after: b)  // nothing to its right: no change
        tabs.closeTabs(after: a)
        #expect(tabs.tabs.map(\.route) == ["a"])
        #expect(tabs.activeID == a)
    }

    @Test func closeToTheRightKeepsFocusLeftOfIt() {
        var tabs = Tabs(initial: "a")
        let a = tabs.activeID
        tabs.openTab("b")
        let b = tabs.activeID
        tabs.openTab("c")
        tabs.select(a)
        tabs.closeTabs(after: b)
        #expect(tabs.activeID == a)
    }
}
