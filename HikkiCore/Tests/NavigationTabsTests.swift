import Foundation
@testable import HikkiCore
import Testing

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
        #expect(closedLast == false) // last tab stays
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
        #expect(tabs.route == "home")           // the tab that only had "x"
        tabs.select(first)
        #expect(tabs.active.history == ["home", "a", "home"])
        #expect(tabs.route == "home")
    }

    @Test func roundTripsThroughJSON() throws {
        var tabs = Tabs(initial: "home")
        tabs.navigate(to: "a")
        tabs.openTab("b")
        let decoded = try JSONDecoder().decode(Tabs.self, from: JSONEncoder().encode(tabs))
        #expect(decoded == tabs)
    }
}
