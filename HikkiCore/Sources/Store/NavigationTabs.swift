import Foundation

/// Browser-style tabs, each with its own back/forward history. Pure value type so the rules
/// (what back means, which tab gets focus after a close…) are unit-tested, not buried in views.
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

        mutating func navigate(to route: Route, maxHistory: Int) {
            guard route != self.route else { return }
            history = Array(history.prefix(position + 1)) + [route]
            if history.count > maxHistory { history.removeFirst(history.count - maxHistory) }
            position = history.count - 1
        }

        mutating func move(by delta: Int) {
            position = min(max(position + delta, 0), history.count - 1)
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

    public init(initial: Route) {
        let tab = Tab(route: initial)
        tabs = [tab]
        activeID = tab.id
        recency = [tab.id]
    }

    private enum CodingKeys: String, CodingKey { case tabs, activeID, maxHistory, recency }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tabs = try c.decode([Tab].self, forKey: .tabs)
        activeID = try c.decode(UUID.self, forKey: .activeID)
        maxHistory = try c.decodeIfPresent(Int.self, forKey: .maxHistory) ?? 50
        // Saved before recency existed: the strip's order, the active tab first.
        recency = try c.decodeIfPresent([UUID].self, forKey: .recency) ?? [activeID] + tabs.map(\.id).filter { $0 != activeID }
    }

    public var active: Tab { tabs.first { $0.id == activeID } ?? tabs[0] }
    public var route: Route { active.route }

    /// Navigates the active tab (like clicking a link).
    public mutating func navigate(to route: Route) {
        let limit = maxHistory
        update(activeID) { $0.navigate(to: route, maxHistory: limit) }
    }

    public mutating func goBack() { update(activeID) { $0.move(by: -1) } }
    public mutating func goForward() { update(activeID) { $0.move(by: 1) } }

    /// Opens a new tab after the active one and focuses it.
    @discardableResult
    public mutating func openTab(_ route: Route) -> UUID {
        let tab = Tab(route: route)
        let index = (tabs.firstIndex { $0.id == activeID } ?? tabs.count - 1) + 1
        tabs.insert(tab, at: index)
        activeID = tab.id
        return tab.id
    }

    public mutating func select(_ id: UUID) {
        if tabs.contains(where: { $0.id == id }) { activeID = id }
    }

    /// Opens `route` in a new tab at `index` (clamped) and focuses it — a page dropped between tabs. A tab
    /// already showing `route` is focused instead; the strip never gets two tabs on the same page this way.
    @discardableResult
    public mutating func openTab(_ route: Route, at index: Int) -> UUID {
        if let existing = tabs.first(where: { $0.route == route }) {
            activeID = existing.id
            return existing.id
        }
        let tab = Tab(route: route)
        tabs.insert(tab, at: min(max(index, 0), tabs.count))
        activeID = tab.id
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
            return existing.id
        }
        let tab = Tab(route: route)
        tabs.append(tab)
        activeID = tab.id
        while tabs.count > max(limit, 1), let oldest = recency.last(where: { $0 != tab.id }) {
            tabs.removeAll { $0.id == oldest }
            recency.removeAll { $0 == oldest }
        }
        return tab.id
    }

    /// Cycles focus (⌃Tab / ⌃⇧Tab).
    public mutating func selectNeighbor(_ delta: Int) {
        guard let index = tabs.firstIndex(where: { $0.id == activeID }) else { return }
        activeID = tabs[(index + delta + tabs.count) % tabs.count].id
    }

    /// Closes a tab; the last tab is never closed (returns false so the caller can close the window).
    /// Closing the active tab focuses its right neighbour, else its left one — like browsers.
    @discardableResult
    public mutating func close(_ id: UUID) -> Bool {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == id }) else { return false }
        tabs.remove(at: index)
        recency.removeAll { $0 == id }
        if activeID == id { activeID = tabs[min(index, tabs.count - 1)].id }
        return true
    }

    /// Removes routes that no longer exist (trashed pages) from every tab; a tab with nothing left
    /// falls back to `fallback`.
    public mutating func prune(fallback: Route, isGone: (Route) -> Bool) {
        for index in tabs.indices where !tabs[index].prune(isGone) {
            tabs[index] = Tab(id: tabs[index].id, route: fallback)
        }
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
