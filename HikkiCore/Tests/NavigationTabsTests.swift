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

    @Test func backGoesToThePageShownBeforeWhicheverTabItWasIn() {
        var tabs = Tabs(initial: "home")
        tabs.navigate(to: "a")
        let first = tabs.activeID
        tabs.openTab("b")
        let second = tabs.activeID
        tabs.navigate(to: "c")
        tabs.select(first)
        #expect(tabs.route == "a")
        tabs.goBack()
        #expect(tabs.activeID == second && tabs.route == "c")
        tabs.goBack()
        #expect(tabs.route == "b")
        tabs.goBack()
        #expect(tabs.activeID == first && tabs.route == "a")
        tabs.goBack()
        #expect(tabs.route == "home")
        #expect(!tabs.canGoBack)
        tabs.goForward()
        tabs.goForward()
        #expect(tabs.activeID == second && tabs.route == "b")
        // Each tab still keeps its own pages.
        #expect(tabs.tabs.map(\.history) == [["home", "a"], ["b", "c"]])
    }

    /// The bug: pages picked in the sidebar open (or focus) a tab, so a tab's own history stayed one page long and the
    /// arrows never lit up.
    @Test func pagesOpenedFromTheSidebarCanBeWalkedBack() {
        var tabs = Tabs(initial: "home")
        tabs.openRecent("a", limit: 5)
        tabs.openRecent("b", limit: 5)
        tabs.openRecent("a", limit: 5)
        #expect(tabs.canGoBack)
        tabs.goBack()
        #expect(tabs.route == "b")
        tabs.goBack()
        #expect(tabs.route == "a")
        tabs.goBack()
        #expect(tabs.route == "home")
        #expect(tabs.canGoForward)
    }

    @Test func closedTabsAndGonePagesArePassedOver() {
        var tabs = Tabs(initial: "home")
        tabs.openTab("a")
        let a = tabs.activeID
        tabs.openTab("b")
        tabs.close(a)
        tabs.goBack()
        #expect(tabs.route == "home")
        // A page that left every history (trashed) is skipped too.
        var other = Tabs(initial: "home")
        other.navigate(to: "x")
        other.navigate(to: "y")
        other.prune(fallback: "home") { $0 == "x" }
        other.goBack()
        #expect(other.route == "home")
    }

    @Test func navigatingAfterGoingBackDropsTheWayForward() {
        var tabs = Tabs(initial: "home")
        tabs.openRecent("a", limit: 5)
        tabs.goBack()
        tabs.navigate(to: "c")
        #expect(!tabs.canGoForward)
    }

    @Test func historySavedBeforeTheWindowHadOneStartsAtThePageShown() throws {
        let old =
            #"{"tabs":[{"id":"8E3B1B6C-1C1C-4C4C-9C9C-111111111111","history":["home","a"],"position":1}],"activeID":"8E3B1B6C-1C1C-4C4C-9C9C-111111111111"}"#
        let tabs = try JSONDecoder().decode(Tabs.self, from: Data(old.utf8))
        #expect(tabs.route == "a")
        #expect(tabs.visits.map(\.route) == ["a"])
        #expect(!tabs.canGoBack)
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
        #expect(tabs.active.history == ["1", "a", "dropped"])
        // Back: the page shown before — the other tab's.
        tabs.goBack()
        #expect(tabs.route == "2")
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

    // MARK: Split

    @Test func openSplitJoinsANewTabBesideTheFocusedOne() throws {
        var tabs = Tabs(initial: "a")
        let left = tabs.activeID
        tabs.openTab("z")
        tabs.select(left)
        let opened = tabs.openSplit("b", beside: left)
        let right = try #require(opened)
        #expect(tabs.tabs.map(\.route) == ["a", "b", "z"])
        #expect(tabs.activeID == left, "the reader stays where they were")
        #expect(tabs.activeSplit == .init(leading: left, trailing: right))
        // Split already: the other side shows it.
        let other = tabs.openSplit("c", beside: left)
        #expect(other == right)
        #expect(tabs.tabs.map(\.route) == ["a", "c", "z"])
        #expect(tabs.tabs[1].history == ["b", "c"])
    }

    @Test func aSideWithNothingLeftClosesAndTheOtherTakesTheWindow() throws {
        var tabs = Tabs(initial: "a")
        let left = tabs.activeID
        let opened = tabs.openSplit("x", beside: left)
        let right = try #require(opened)
        tabs.select(right)
        tabs.prune(fallback: "home") { $0 == "x" }
        #expect(tabs.tabs.map(\.route) == ["a"], "no Home in half the window")
        #expect(tabs.activeID == left)
        #expect(tabs.activeSplit == nil)
        // Both sides gone: one tab is left, on the fallback.
        let again = tabs.openSplit("y", beside: left)
        _ = try #require(again)
        tabs.prune(fallback: "home") { $0 == "a" || $0 == "y" }
        #expect(tabs.tabs.map(\.route) == ["home"])
        #expect(tabs.activeSplit == nil)
    }

    @Test func focusMovesBetweenSidesWithoutGrowingTheWindowsHistory() throws {
        var tabs = Tabs(initial: "a")
        let left = tabs.activeID
        let opened = tabs.openSplit("b", beside: left)
        let right = try #require(opened)
        let visits = tabs.visits
        tabs.select(right)
        tabs.select(left)
        #expect(tabs.visits == visits)
        #expect(tabs.activeSplit != nil)
    }

    @Test func backAndForwardInASplitWalkTheFocusedSide() throws {
        var tabs = Tabs(initial: "a")
        let left = tabs.activeID
        let opened = tabs.openSplit("b", beside: left)
        let right = try #require(opened)
        tabs.navigate(to: "a2")
        tabs.select(right)
        tabs.navigate(to: "b2")
        #expect(tabs.canGoBack)
        tabs.goBack()
        #expect(tabs.route == "b")
        #expect(tabs.activeID == right)
        #expect(tabs.tabs[0].route == "a2", "the other side is left alone")
        #expect(!tabs.canGoBack)
        tabs.goForward()
        #expect(tabs.route == "b2")
    }

    @Test func swappingTradesPlacesAndKeepsTheFocus() throws {
        var tabs = Tabs(initial: "a")
        let left = tabs.activeID
        let opened = tabs.openSplit("b", beside: left)
        let right = try #require(opened)
        tabs.swapSplit(left)
        #expect(tabs.tabs.map(\.route) == ["b", "a"])
        #expect(tabs.activeSplit == .init(leading: right, trailing: left))
        #expect(tabs.activeID == left)
    }

    @Test func closingASideFocusesTheOtherAndEndsTheSplit() throws {
        var tabs = Tabs(initial: "x")
        tabs.openTab("a")
        let left = tabs.activeID
        tabs.openTab("y")
        tabs.select(left)
        let opened = tabs.openSplit("b", beside: left)
        let right = try #require(opened)
        tabs.select(right)
        tabs.close(right)
        #expect(tabs.activeID == left)
        #expect(tabs.splits.isEmpty)
    }

    @Test func newTabsNeverLandBetweenTheSides() throws {
        var tabs = Tabs(initial: "a")
        let left = tabs.activeID
        tabs.openSplit("b", beside: left)
        tabs.openTab("c", after: left)
        #expect(tabs.tabs.map(\.route) == ["a", "b", "c"])
        tabs.duplicate(left)
        #expect(tabs.tabs.map(\.route) == ["a", "b", "a", "c"])
        tabs.openTab("d", at: 1)
        #expect(tabs.tabs.map(\.route) == ["a", "b", "d", "a", "c"])
        #expect(tabs.splits.count == 1)
    }

    @Test func sidebarPicksShowInTheFocusedSide() throws {
        var tabs = Tabs(initial: "a")
        let left = tabs.activeID
        let opened = tabs.openSplit("b", beside: left)
        let right = try #require(opened)
        tabs.select(right)
        tabs.openRecent("c", limit: 6)
        #expect(tabs.tabs.map(\.route) == ["a", "c"])
        #expect(tabs.activeID == right)
        // A page open on the other side gets the focus there.
        tabs.openRecent("a", limit: 6)
        #expect(tabs.activeID == left)
    }

    @Test func evictionSparesTheSplit() throws {
        var tabs = Tabs(initial: "a")
        let left = tabs.activeID
        tabs.openSplit("b", beside: left)
        tabs.openTab("c")  // leaves the split
        tabs.openRecent("d", limit: 3)
        #expect(tabs.tabs.map(\.route) == ["a", "b", "d"])
        #expect(tabs.splits.count == 1)
    }

    @Test func joinMovesATabBesideAndSeparateKeepsBoth() {
        var tabs = Tabs(initial: "a")
        let a = tabs.activeID
        tabs.openTab("b")
        let c = tabs.openTab("c")
        tabs.select(a)
        tabs.join(a, with: c)
        #expect(tabs.tabs.map(\.route) == ["a", "c", "b"])
        #expect(tabs.activeSplit == .init(leading: a, trailing: c))
        tabs.separate(c)
        #expect(tabs.splits.isEmpty)
        #expect(tabs.tabs.count == 3)
    }

    @Test func aPickerLeftOutsideASplitCloses() throws {
        var tabs = Tabs(initial: "a")
        let left = tabs.activeID
        let opened = tabs.openSplit("picker", beside: left)
        let right = try #require(opened)
        tabs.closeLoose({ $0 == "picker" }, fallback: "home")
        #expect(tabs.tabs.count == 2, "still in its split")
        tabs.replace(right, with: "b")
        #expect(tabs.tabs[1].history == ["b"])
        tabs.openSplit("picker", beside: left)
        tabs.separate(left)
        tabs.closeLoose({ $0 == "picker" }, fallback: "home")
        #expect(tabs.tabs.map(\.route) == ["a"])
    }

    @Test func splitsSurviveEncodingAndBrokenOnesAreDropped() throws {
        var tabs = Tabs(initial: "a")
        let left = tabs.activeID
        tabs.openSplit("b", beside: left)
        let data = try JSONEncoder().encode(tabs)
        #expect(try JSONDecoder().decode(Tabs.self, from: data) == tabs)
        // Saved before splits were tabs: none.
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "splits")
        let old = try JSONDecoder().decode(Tabs.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(old.splits.isEmpty)
    }

    @Test func keepActiveOnlyLeavesTheFocusedTabAndItsSplit() throws {
        var tabs = Tabs(initial: "a")
        tabs.openTab("b")
        tabs.openTab("c")
        tabs.keepActiveOnly()
        #expect(tabs.tabs.map(\.route) == ["c"])
        let left = tabs.activeID
        _ = tabs.openSplit("d", beside: left)
        tabs.keepActiveOnly()
        #expect(Set(tabs.tabs.map(\.route)) == ["c", "d"])
        #expect(tabs.activeSplit != nil)
    }

    @Test func aLinkOpensItsPageInANewTabRightAfterTheLinksTab() {
        var tabs = Tabs(initial: "a")
        let a = tabs.activeID
        tabs.openTab("z")
        tabs.select(a)
        let opened = tabs.openLink("b", from: a, limit: 6)
        #expect(tabs.tabs.map(\.route) == ["a", "b", "z"])
        #expect(tabs.activeID == opened)
        #expect(tabs.tabs[0].history == ["a"], "the page the link was in stays in its tab")
        tabs.goBack()
        #expect(tabs.activeID == a, "back returns to the page with the link")
    }

    @Test func aLinkToAPageAlreadyInATabFocusesThatTab() {
        var tabs = Tabs(initial: "a")
        let a = tabs.activeID
        let b = tabs.openTab("b")
        tabs.select(a)
        #expect(tabs.openLink("b", from: a, limit: 6) == b)
        #expect(tabs.tabs.count == 2)
        #expect(tabs.activeID == b)
    }

    @Test func aLinkFromASideOpensAfterTheSplitAndLeavesItWhole() throws {
        var tabs = Tabs(initial: "a")
        let left = tabs.activeID
        let opened = tabs.openSplit("b", beside: left)
        let right = try #require(opened)
        tabs.openTab("z")
        tabs.select(right)
        tabs.openLink("c", from: right, limit: 6)
        #expect(tabs.tabs.map(\.route) == ["a", "b", "c", "z"])
        #expect(tabs.split(of: left) == .init(leading: left, trailing: right))
        #expect(tabs.activeSplit == nil)
    }

    @Test func linkTabsKeepTheStripToTheLimitAndSpareTheLinksTab() {
        var tabs = Tabs(initial: "a")
        let a = tabs.activeID
        tabs.openTab("b")
        tabs.openTab("c")
        tabs.select(a)
        tabs.openLink("d", from: a, limit: 3)
        #expect(tabs.tabs.map(\.route) == ["a", "d", "c"])
    }

    @Test func openingAPageWithATabFocusesItInsteadOfShowingItTwice() {
        var tabs = Tabs(initial: "a")
        let a = tabs.activeID
        tabs.openTab("b")
        tabs.open("a")
        #expect(tabs.activeID == a)
        #expect(tabs.tabs.map(\.route) == ["a", "b"])
        tabs.open("c")
        #expect(tabs.tabs.map(\.route) == ["c", "b"], "a page without a tab shows in the focused one")
        #expect(tabs.active.history == ["a", "c"])
    }

    @Test func separatingASplitOnOnePageLeavesOneTab() throws {
        var tabs = Tabs(initial: "a")
        let left = tabs.activeID
        let opened = tabs.openSplit("a", beside: left)
        let right = try #require(opened)
        tabs.select(right)
        tabs.separate(right)
        #expect(tabs.splits.isEmpty)
        #expect(tabs.tabs.map(\.id) == [right], "the focused side's tab stays")
        #expect(tabs.activeID == right)
    }

    @Test func separatingASplitOnTwoPagesKeepsBoth() {
        var tabs = Tabs(initial: "a")
        let left = tabs.activeID
        tabs.openSplit("b", beside: left)
        tabs.separate(left)
        #expect(tabs.tabs.map(\.route) == ["a", "b"])
    }

    @Test func closeDuplicatesKeepsTheFocusedTabTheSplitsAndAllowedRepeats() {
        var tabs = Tabs(initial: "a")
        let left = tabs.activeID
        tabs.openSplit("b", beside: left)
        tabs.openTab("home")
        tabs.openTab("b")
        tabs.openTab("home")
        tabs.openTab("c")
        tabs.openTab("a")
        tabs.openTab("c")
        let focused = tabs.activeID
        tabs.closeDuplicates { $0 != "home" }
        #expect(tabs.tabs.map(\.route) == ["a", "b", "home", "home", "c"])
        #expect(tabs.activeID == focused)
        #expect(tabs.splits.count == 1)
    }

    @Test func movingATabPutsItInTheGapAndKeepsTheFocus() {
        var tabs = Tabs(initial: "a")
        tabs.openTab("b")
        tabs.openTab("c")
        let focused = tabs.openTab("d")
        let a = tabs.tabs[0].id
        tabs.move(a, to: 3)
        #expect(tabs.tabs.map(\.route) == ["b", "c", "a", "d"])
        tabs.move(focused, to: 0)
        #expect(tabs.tabs.map(\.route) == ["d", "b", "c", "a"])
        #expect(tabs.activeID == focused)
        tabs.move(focused, to: 1)
        #expect(tabs.tabs.map(\.route) == ["d", "b", "c", "a"], "its own edges move nothing")
        tabs.move(focused, to: 99)
        #expect(tabs.tabs.map(\.route) == ["b", "c", "a", "d"])
    }

    @Test func aSplitMovesWholeAndNoTabLandsBetweenItsSides() throws {
        var tabs = Tabs(initial: "a")
        let left = tabs.activeID
        let opened = tabs.openSplit("b", beside: left)
        let right = try #require(opened)
        tabs.openTab("c")
        let d = tabs.openTab("d")
        tabs.move(right, to: 4)
        #expect(tabs.tabs.map(\.route) == ["c", "d", "a", "b"])
        #expect(tabs.split(of: left) == .init(leading: left, trailing: right))
        tabs.move(d, to: 3)
        #expect(tabs.tabs.map(\.route) == ["c", "a", "b", "d"], "a gap inside the split means after it")
        #expect(tabs.splits.count == 1)
    }

    @Test func closeAllLeavesOneNewTabOnTheFallback() throws {
        var tabs = Tabs(initial: "a")
        let left = tabs.activeID
        tabs.openSplit("b", beside: left)
        tabs.openTab("c")
        tabs.closeAll(fallback: "home")
        #expect(tabs.tabs.map(\.route) == ["home"])
        #expect(tabs.splits.isEmpty)
        #expect(tabs.recency == [tabs.activeID])
        #expect(!tabs.canGoBack, "the closed tabs' pages are passed over")
    }

    // MARK: Reopen Closed Tab

    @Test func aClosedTabComesBackWithItsHistoryAtItsPlace() {
        var tabs = Tabs(initial: "home")
        let first = tabs.activeID
        tabs.openTab("a")
        let middle = tabs.activeID
        tabs.navigate(to: "b")
        tabs.openTab("c")
        #expect(tabs.reopenClosed() == nil, "nothing closed yet")
        tabs.close(middle)
        #expect(tabs.tabs.map(\.route) == ["home", "c"])
        let reopened = tabs.reopenClosed()
        #expect(reopened != nil && reopened != middle, "a new id, the old one is gone")
        #expect(tabs.activeID == reopened)
        #expect(tabs.tabs.map(\.route) == ["home", "b", "c"], "back at its place")
        #expect(tabs.active.history == ["a", "b"] && tabs.active.canGoBack, "with its history")
        #expect(tabs.reopenClosed() == nil, "reopened once")
        tabs.select(first)
        #expect(tabs.tabs.count == 3)
    }

    @Test func closeOthersRightAndAllAreRememberedLastClosedFirstOut() {
        var tabs = Tabs(initial: "home")
        tabs.openTab("a")
        tabs.openTab("b")
        tabs.openTab("c")
        tabs.closeTabs(after: tabs.tabs[1].id)  // b, c
        tabs.closeOthers(tabs.tabs[0].id)  // a
        #expect(tabs.closed.map(\.tab.route) == ["b", "c", "a"])
        tabs.reopenClosed()
        #expect(tabs.route == "a")
        tabs.closeAll(fallback: "home")
        #expect(tabs.closed.map(\.tab.route) == ["b", "c", "home", "a"])
        #expect(tabs.tabs.map(\.route) == ["home"])
    }

    @Test func theWindowsOwnRemovalsAreNotRememberedAndTheListIsCapped() {
        var tabs = Tabs(initial: "a")
        let left = tabs.activeID
        tabs.openSplit("a", beside: left)
        tabs.separate(left)  // both sides showed "a": one tab goes, the window's doing
        #expect(tabs.closed.isEmpty)
        for i in 0..<(Tabs.maxClosed + 3) {
            tabs.openTab("p\(i)")
            tabs.close(tabs.activeID)
        }
        #expect(tabs.closed.count == Tabs.maxClosed)
        #expect(tabs.closed.last?.tab.route == "p\(Tabs.maxClosed + 2)")
    }

    @Test func closedTabsSurviveSaving() throws {
        var tabs = Tabs(initial: "home")
        tabs.openTab("a")
        tabs.close(tabs.activeID)
        let data = try JSONEncoder().encode(tabs)
        var restored = try JSONDecoder().decode(Tabs.self, from: data)
        #expect(restored.closed.map(\.tab.route) == ["a"])
        restored.reopenClosed()
        #expect(restored.route == "a")
    }
}
