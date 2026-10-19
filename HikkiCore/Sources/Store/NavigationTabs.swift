import Foundation

/// Browser-style tabs, each with its own history of pages, and one back/forward for the window: back goes to the page
/// shown before — in whatever tab it was, so a page opened from the sidebar (its own new tab, or another tab focused)
/// goes back to where the reader was, as Notion's arrows do. Pure value type so the rules (what back means, which tab
/// gets focus after a close…) are unit-tested, not buried in views.
public struct NavigationTabs<Route: Hashable & Codable & Sendable>: Codable, Equatable, Sendable {
    public struct Tab: Codable, Equatable, Identifiable, Sendable {
        public let id: UUID
        public private(set) var history: [Route]
        public private(set) var position: Int

        public var route: Route { history[position] }
        public var canGoBack: Bool { position > 0 }
        public var canGoForward: Bool { position < history.count - 1 }

        init(id: UUID = UUID(), route: Route) {
            self.id = id
            self.history = [route]
            self.position = 0
        }

        /// A copy of `tab` under a new id — same history, same place in it (Duplicate).
        init(copying tab: Tab) {
            self.id = UUID()
            self.history = tab.history
            self.position = tab.position
        }

        mutating func navigate(to route: Route, maxHistory: Int) {
            guard route != self.route else { return }
            history = Array(history.prefix(position + 1)) + [route]
            if history.count > maxHistory { history.removeFirst(history.count - maxHistory) }
            position = history.count - 1
        }

        mutating func move(by delta: Int) {
            position = min(max(position + delta, 0), history.count - 1)
        }

        /// Back to a page of its own history (the latest time it was there); false when it no longer has it.
        mutating func show(_ route: Route) -> Bool {
            guard let index = history.lastIndex(of: route) else { return false }
            position = index
            return true
        }

        /// Drops every history entry matching `isGone`; false when nothing is left.
        mutating func prune(_ isGone: (Route) -> Bool) -> Bool {
            let current = route
            history.removeAll(where: isGone)
            // Collapse neighbours made adjacent-equal by the removal.
            history = history.reduce(into: []) { if $0.last != $1 { $0.append($1) } }
            guard !history.isEmpty else { return false }
            position = history.lastIndex(of: current) ?? history.count - 1
            return true
        }
    }

    public private(set) var tabs: [Tab]
    public private(set) var activeID: UUID {
        didSet { touch(activeID) }
    }
    public var maxHistory = 50
    /// Tab ids, most recently focused first — what `openRecent` evicts by.
    public private(set) var recency: [UUID] = []

    /// A page as it was shown: in which tab.
    public struct Visit: Codable, Equatable, Sendable {
        public var tab: UUID
        public var route: Route
    }

    /// The window's pages in the order they were shown (back / forward walk it), and where in it the window is.
    public private(set) var visits: [Visit] = []
    public private(set) var visitIndex = 0

    public init(initial: Route) {
        let tab = Tab(route: initial)
        tabs = [tab]
        activeID = tab.id
        recency = [tab.id]
        visits = [Visit(tab: tab.id, route: initial)]
    }

    private enum CodingKeys: String, CodingKey { case tabs, activeID, maxHistory, recency, visits, visitIndex }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tabs = try c.decode([Tab].self, forKey: .tabs)
        activeID = try c.decode(UUID.self, forKey: .activeID)
        maxHistory = try c.decodeIfPresent(Int.self, forKey: .maxHistory) ?? 50
        // Saved before recency existed: the strip's order, the active tab first.
        recency = try c.decodeIfPresent([UUID].self, forKey: .recency) ?? [activeID] + tabs.map(\.id).filter { $0 != activeID }
        // Saved before the window had one history: it starts at the page shown.
        visits = try c.decodeIfPresent([Visit].self, forKey: .visits) ?? []
        visitIndex = try c.decodeIfPresent(Int.self, forKey: .visitIndex) ?? 0
        if visits.isEmpty || !visits.indices.contains(visitIndex) {
            visits = [Visit(tab: activeID, route: route)]
            visitIndex = 0
        }
    }

    public var active: Tab { tabs.first { $0.id == activeID } ?? tabs[0] }
    public var route: Route { active.route }

    /// Navigates the active tab (like clicking a link).
    public mutating func navigate(to route: Route) {
        let limit = maxHistory
        update(activeID) { $0.navigate(to: route, maxHistory: limit) }
        recordVisit()
    }

    /// The page shown before (in its tab, focused); pages whose tab closed or that are gone are passed over.
    public mutating func goBack() { step(-1) }
    public mutating func goForward() { step(1) }

    public var canGoBack: Bool { target(-1) != nil }
    public var canGoForward: Bool { target(1) != nil }

    /// The nearest visit in that direction that can still be shown, and isn't what is shown now.
    private func target(_ direction: Int) -> Int? {
        let current = Visit(tab: activeID, route: route)
        var index = visitIndex + direction
        while visits.indices.contains(index) {
            let visit = visits[index]
            if visit != current, let tab = tabs.first(where: { $0.id == visit.tab }), tab.history.contains(visit.route) {
                return index
            }
            index += direction
        }
        return nil
    }

    private mutating func step(_ direction: Int) {
        guard let index = target(direction) else { return }
        let visit = visits[index]
        visitIndex = index
        activeID = visit.tab
        update(visit.tab) { _ = $0.show(visit.route) }
    }

    /// What is shown now joins the window's history (after a navigation, a new or focused tab, a close…); back and
    /// forward only move along it.
    private mutating func recordVisit() {
        let visit = Visit(tab: activeID, route: route)
        if visits.indices.contains(visitIndex), visits[visitIndex] == visit { return }
        visits = Array(visits.prefix(visitIndex + 1)) + [visit]
        let cap = maxHistory * 2
        if visits.count > cap { visits.removeFirst(visits.count - cap) }
        visitIndex = visits.count - 1
    }

    /// Opens a new tab after the active one and focuses it.
    @discardableResult
    public mutating func openTab(_ route: Route) -> UUID {
        openTab(route, after: activeID)
    }

    /// Opens a new tab right after the tab `id` (after the last one when there is no such tab) and focuses it — the tab
    /// menu's "New Tab to the Right".
    @discardableResult
    public mutating func openTab(_ route: Route, after id: UUID) -> UUID {
        let tab = Tab(route: route)
        let index = (tabs.firstIndex { $0.id == id } ?? tabs.count - 1) + 1
        tabs.insert(tab, at: index)
        activeID = tab.id
        recordVisit()
        return tab.id
    }

    /// A copy of the tab `id` — its whole history, at the same place — right after it, focused (the tab menu's
    /// Duplicate). Nil when there is no such tab.
    @discardableResult
    public mutating func duplicate(_ id: UUID) -> UUID? {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return nil }
        let copy = Tab(copying: tabs[index])
        tabs.insert(copy, at: index + 1)
        activeID = copy.id
        recordVisit()
        return copy.id
    }

    /// Closes every tab but `id`, which gets focus ("Close Other Tabs").
    public mutating func closeOthers(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        tabs.removeAll { $0.id != id }
        recency.removeAll { $0 != id }
        activeID = id
        recordVisit()
    }

    /// Closes the tabs after `id` ("Close Tabs to the Right"); when the focused tab was one of them, `id` gets focus.
    public mutating func closeTabs(after id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }), index < tabs.count - 1 else { return }
        let gone = Set(tabs[(index + 1)...].map(\.id))
        tabs.removeSubrange((index + 1)...)
        recency.removeAll { gone.contains($0) }
        if gone.contains(activeID) { activeID = id }
        recordVisit()
    }

    public mutating func select(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeID = id
        recordVisit()
    }

    /// Opens `route` in a new tab at `index` (clamped) and focuses it — a page dropped between tabs. A tab
    /// already showing `route` is focused instead; the strip never gets two tabs on the same page this way.
    @discardableResult
    public mutating func openTab(_ route: Route, at index: Int) -> UUID {
        if let existing = tabs.first(where: { $0.route == route }) {
            activeID = existing.id
            recordVisit()
            return existing.id
        }
        let tab = Tab(route: route)
        tabs.insert(tab, at: min(max(index, 0), tabs.count))
        activeID = tab.id
        recordVisit()
        return tab.id
    }

    /// Shows `route` in the tab `id` and focuses it — a page dropped onto a tab. The tab keeps its history,
    /// as if the page had been opened from it.
    public mutating func navigate(_ id: UUID, to route: Route) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeID = id
        navigate(to: route)
    }

    /// A page (or Home, Trash) picked in the sidebar: the tab already showing it gets focus; otherwise it opens in a new
    /// tab at the end, and past `limit` tabs the least recently focused one closes (never the new one) — the strip keeps
    /// the latest few, like a browser that tidies up after itself.
    @discardableResult
    public mutating func openRecent(_ route: Route, limit: Int) -> UUID {
        if let existing = tabs.first(where: { $0.route == route }) {
            activeID = existing.id
            recordVisit()
            return existing.id
        }
        let tab = Tab(route: route)
        tabs.append(tab)
        activeID = tab.id
        while tabs.count > max(limit, 1), let oldest = recency.last(where: { $0 != tab.id }) {
            tabs.removeAll { $0.id == oldest }
            recency.removeAll { $0 == oldest }
        }
        recordVisit()
        return tab.id
    }

    /// Cycles focus (⌃Tab / ⌃⇧Tab).
    public mutating func selectNeighbor(_ delta: Int) {
        guard let index = tabs.firstIndex(where: { $0.id == activeID }) else { return }
        activeID = tabs[(index + delta + tabs.count) % tabs.count].id
        recordVisit()
    }

    /// Closes a tab; the last tab is never closed (returns false so the caller can close the window).
    /// Closing the active tab focuses its right neighbour, else its left one — like browsers.
    @discardableResult
    public mutating func close(_ id: UUID) -> Bool {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == id }) else { return false }
        tabs.remove(at: index)
        recency.removeAll { $0 == id }
        if activeID == id { activeID = tabs[min(index, tabs.count - 1)].id }
        recordVisit()
        return true
    }

    /// Removes routes that no longer exist (trashed pages) from every tab; a tab with nothing left
    /// falls back to `fallback`.
    public mutating func prune(fallback: Route, isGone: (Route) -> Bool) {
        for index in tabs.indices where !tabs[index].prune(isGone) {
            tabs[index] = Tab(id: tabs[index].id, route: fallback)
        }
        recordVisit()
    }

    /// `prune` on a copy: equal to `self` when nothing was gone, so an observed owner can skip the assignment (every
    /// assignment of an `@Observable` property notifies, equal or not).
    public func pruned(fallback: Route, isGone: (Route) -> Bool) -> Self {
        var copy = self
        copy.prune(fallback: fallback, isGone: isGone)
        return copy
    }

    private mutating func touch(_ id: UUID) {
        recency.removeAll { $0 == id }
        recency.insert(id, at: 0)
    }

    private mutating func update(_ id: UUID, _ body: (inout Tab) -> Void) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        body(&tabs[index])
    }
}
