import Foundation

/// Browser-style tabs, each with its own history of pages, and one back/forward for the window: back goes to the page
/// shown before — in whatever tab it was, so a page opened from the sidebar (its own new tab, or another tab focused)
/// goes back to where the reader was, as Notion's arrows do. Two tabs may be joined into a split (Chrome's split view):
/// side by side in the window and next to each other in the strip, equals — either has the focus, back / forward walk the
/// focused one's own history, and the two can trade places. Pure value type so the rules (what back means, which tab
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

        /// The page shown now becomes `route`, with no new history entry (an empty split pane picking its page).
        mutating func replace(with route: Route) {
            history[position] = route
            history = history.reduce(into: []) { if $0.last != $1 { $0.append($1) } }
            position = min(position, history.count - 1)
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

    /// Two tabs shown side by side: `leading` right before `trailing` in the strip. A tab is in one split at most.
    public struct Split: Codable, Equatable, Sendable {
        public var leading: UUID
        public var trailing: UUID

        public func contains(_ id: UUID) -> Bool { leading == id || trailing == id }
        /// The other side of the split from `id`.
        public func other(_ id: UUID) -> UUID { id == leading ? trailing : leading }
    }

    public private(set) var splits: [Split] = []

    /// The split the tab `id` is in.
    public func split(of id: UUID) -> Split? { splits.first { $0.contains(id) } }
    /// The split the window shows (the focused tab's), if any.
    public var activeSplit: Split? { split(of: activeID) }

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

    private enum CodingKeys: String, CodingKey { case tabs, activeID, maxHistory, recency, visits, visitIndex, splits }

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
        splits = try c.decodeIfPresent([Split].self, forKey: .splits) ?? []
        tidySplits()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(tabs, forKey: .tabs)
        try c.encode(activeID, forKey: .activeID)
        try c.encode(maxHistory, forKey: .maxHistory)
        try c.encode(recency, forKey: .recency)
        try c.encode(visits, forKey: .visits)
        try c.encode(visitIndex, forKey: .visitIndex)
        try c.encode(splits, forKey: .splits)
    }

    public var active: Tab { tabs.first { $0.id == activeID } ?? tabs[0] }
    public var route: Route { active.route }

    /// Navigates the active tab (like clicking a link).
    public mutating func navigate(to route: Route) {
        let limit = maxHistory
        update(activeID) { $0.navigate(to: route, maxHistory: limit) }
        recordVisit()
    }

    /// The page shown before (in its tab, focused); pages whose tab closed or that are gone are passed over. In a split,
    /// the focused side's own history: each side goes back on its own.
    public mutating func goBack() { step(-1) }
    public mutating func goForward() { step(1) }

    public var canGoBack: Bool { activeSplit != nil ? active.canGoBack : target(-1) != nil }
    public var canGoForward: Bool { activeSplit != nil ? active.canGoForward : target(1) != nil }

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
        if activeSplit != nil {
            update(activeID) { $0.move(by: direction) }
            return
        }
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
        tabs.insert(tab, at: insertionIndex(index))
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
        tabs.insert(copy, at: insertionIndex(index + 1))
        activeID = copy.id
        recordVisit()
        return copy.id
    }

    /// Closes every tab but `id` (and the tab beside it in a split), which gets focus ("Close Other Tabs").
    public mutating func closeOthers(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        let kept = split(of: id).map { [$0.leading, $0.trailing] } ?? [id]
        tabs.removeAll { !kept.contains($0.id) }
        recency.removeAll { !kept.contains($0) }
        activeID = id
        tidySplits()
        recordVisit()
    }

    /// Keeps the focused tab alone (with the tab beside it in a split): a window without a tab strip (iPad, an
    /// unfolded iPhone Duo) never holds tabs it can't show. Nothing changes when there is nothing else.
    public mutating func keepActiveOnly() {
        let kept = split(of: activeID).map { [$0.leading, $0.trailing] } ?? [activeID]
        guard tabs.count > kept.count else { return }
        closeOthers(activeID)
    }

    /// Closes the tabs after `id` ("Close Tabs to the Right"); when the focused tab was one of them, `id` gets focus.
    public mutating func closeTabs(after id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }), index < tabs.count - 1 else { return }
        let gone = Set(tabs[(index + 1)...].map(\.id))
        tabs.removeSubrange((index + 1)...)
        recency.removeAll { gone.contains($0) }
        if gone.contains(activeID) { activeID = id }
        tidySplits()
        recordVisit()
    }

    /// Focuses the tab `id`. Moving between the two sides of the split on screen only moves the focus: nothing new was
    /// shown, so the window's history doesn't grow.
    public mutating func select(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        let sameSplit = activeSplit?.contains(id) == true
        activeID = id
        if !sameSplit { recordVisit() }
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
        tabs.insert(tab, at: insertionIndex(min(max(index, 0), tabs.count)))
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
    /// tab at the end, and past `limit` tabs the least recently focused one closes (never the new one, nor one of a split)
    /// — the strip keeps the latest few, like a browser that tidies up after itself. In a split it shows in the focused
    /// side instead, so picking pages doesn't take the reader out of the split.
    @discardableResult
    public mutating func openRecent(_ route: Route, limit: Int) -> UUID {
        if let existing = tabs.first(where: { $0.route == route }) {
            select(existing.id)
            return existing.id
        }
        if activeSplit != nil {
            navigate(to: route)
            return activeID
        }
        let tab = Tab(route: route)
        tabs.append(tab)
        activeID = tab.id
        evict(beyond: limit, sparing: [tab.id])
        tidySplits()
        recordVisit()
        return tab.id
    }

    /// The tab showing `route`: the focused one when it does, else the first in the strip that does.
    public func tab(showing route: Route) -> UUID? {
        if self.route == route { return activeID }
        return tabs.first { $0.route == route }?.id
    }

    /// Shows `route` — in the tab already showing it, which gets focus, else in the focused tab (a search result, a
    /// Spotlight pick, a hikki:// link from outside): opening a page never puts it in two tabs.
    public mutating func open(_ route: Route) {
        if let existing = tab(showing: route) { select(existing) } else { navigate(to: route) }
    }

    /// Closes the tabs outside a split that show what another tab shows (`isUnique` says which routes count: Home may
    /// be open twice) — tabs saved by builds that let a page pile up in several. The focused tab and the splits stay;
    /// of the others, the first one showing a route does.
    public mutating func closeDuplicates(where isUnique: (Route) -> Bool) {
        var claimed: Set<Route> = [route]
        for tab in tabs where split(of: tab.id) != nil { claimed.insert(tab.route) }
        var gone = Set<UUID>()
        for tab in tabs where tab.id != activeID && split(of: tab.id) == nil && isUnique(tab.route) {
            if !claimed.insert(tab.route).inserted { gone.insert(tab.id) }
        }
        guard !gone.isEmpty else { return }
        tabs.removeAll { gone.contains($0.id) }
        recency.removeAll { gone.contains($0) }
        tidySplits()
        recordVisit()
    }

    /// Moves the tab `id` — with the other side when it is in a split, the two staying together — into the gap before
    /// the tab at `index` (`tabs.count`: after the last one), as dragging a tab along the strip does. A gap between the
    /// two sides of another split means after them; a gap at either edge of the moving tabs moves nothing. The focus
    /// and the histories don't change.
    public mutating func move(_ id: UUID, to index: Int) {
        guard let at = tabs.firstIndex(where: { $0.id == id }) else { return }
        let first = split(of: id).flatMap { pair in tabs.firstIndex { $0.id == pair.leading } } ?? at
        let count = split(of: id) == nil ? 1 : 2
        let gap = min(max(index, 0), tabs.count)
        guard gap < first || gap > first + count else { return }
        let moving = Array(tabs[first..<(first + count)])
        tabs.removeSubrange(first..<(first + count))
        tabs.insert(contentsOf: moving, at: insertionIndex(gap > first ? gap - count : gap))
        tidySplits()
    }

    /// A link in the page of the tab `id` followed to another page (Chrome's ⌘-click, made the default): the tab already
    /// showing it gets focus; otherwise it opens in a new tab right after `id` (after its split, when `id` is a side of
    /// one), focused, so the page the link was in stays where it was. Past `limit` tabs the least recently focused one
    /// closes, as for sidebar picks — never the new tab, nor `id`, nor a tab of a split.
    @discardableResult
    public mutating func openLink(_ route: Route, from id: UUID, limit: Int) -> UUID {
        if let existing = tab(showing: route) {
            select(existing)
            return existing
        }
        let source = tabs.contains { $0.id == id } ? id : activeID
        let after = split(of: source)?.trailing ?? source
        let tab = Tab(route: route)
        let index = (tabs.firstIndex { $0.id == after } ?? tabs.count - 1) + 1
        tabs.insert(tab, at: insertionIndex(index))
        activeID = tab.id
        evict(beyond: limit, sparing: [tab.id, source])
        tidySplits()
        recordVisit()
        return tab.id
    }

    // MARK: Split

    /// Shows `route` beside the tab `id`: in the other side when `id` is split already, else in a new tab joined to it
    /// on its right. `id` keeps the focus (the reader is still where they were). Returns the tab showing `route`.
    @discardableResult
    public mutating func openSplit(_ route: Route, beside id: UUID) -> UUID? {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return nil }
        if let split = split(of: id) {
            let other = split.other(id)
            let limit = maxHistory
            update(other) { $0.navigate(to: route, maxHistory: limit) }
            return other
        }
        let tab = Tab(route: route)
        tabs.insert(tab, at: index + 1)
        recency.append(tab.id)
        splits.append(Split(leading: id, trailing: tab.id))
        return tab.id
    }

    /// Joins the tab `other` to `id`, on its right (a tab's "Open in Split View"): it moves next to `id`, and the splits
    /// either was in come apart. `id` keeps the focus.
    public mutating func join(_ id: UUID, with other: UUID) {
        guard id != other, tabs.contains(where: { $0.id == id }), let moving = tabs.first(where: { $0.id == other })
        else { return }
        splits.removeAll { $0.contains(id) || $0.contains(other) }
        tabs.removeAll { $0.id == other }
        let index = tabs.firstIndex { $0.id == id }! + 1
        tabs.insert(moving, at: index)
        splits.append(Split(leading: id, trailing: other))
    }

    /// The two sides of `id`'s split trade places (in the window and in the strip); the focus stays with its tab.
    public mutating func swapSplit(_ id: UUID) {
        guard let index = splits.firstIndex(where: { $0.contains(id) }),
            let at = tabs.firstIndex(where: { $0.id == splits[index].leading })
        else { return }
        tabs.swapAt(at, at + 1)
        splits[index] = Split(leading: splits[index].trailing, trailing: splits[index].leading)
    }

    /// Takes `id`'s split apart: both stay tabs, the focused one shown — unless both sides show the same page, which
    /// then needs one tab only: the focused side's (else the leading one) stays.
    public mutating func separate(_ id: UUID) {
        guard let pair = split(of: id) else { return }
        splits.removeAll { $0.contains(id) }
        let leading = tabs.first { $0.id == pair.leading }?.route
        guard leading != nil, leading == tabs.first(where: { $0.id == pair.trailing })?.route else { return }
        let kept = pair.contains(activeID) ? activeID : pair.leading
        close(pair.other(kept))
    }

    /// The tab `id` shows `route` in place of its page now, with no history entry (an empty split pane picking a page).
    public mutating func replace(_ id: UUID, with route: Route) {
        update(id) { $0.replace(with: route) }
    }

    /// Closes the tabs outside a split whose page only makes sense in one (`isLoose`: an empty pane's picker) — the
    /// last tab shows `fallback` instead.
    public mutating func closeLoose(_ isLoose: (Route) -> Bool, fallback: Route) {
        for tab in tabs where split(of: tab.id) == nil && isLoose(tab.route) {
            if !close(tab.id) { tabs[0] = Tab(id: tabs[0].id, route: fallback) }
        }
    }

    /// Cycles focus (⌃Tab / ⌃⇧Tab).
    public mutating func selectNeighbor(_ delta: Int) {
        guard let index = tabs.firstIndex(where: { $0.id == activeID }) else { return }
        activeID = tabs[(index + delta + tabs.count) % tabs.count].id
        recordVisit()
    }

    /// Closes a tab; the last tab is never closed (returns false so the caller can close the window).
    /// Closing the active tab focuses the other side of its split, else its right neighbour, else its left one — like
    /// browsers.
    @discardableResult
    public mutating func close(_ id: UUID) -> Bool {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == id }) else { return false }
        let partner = split(of: id)?.other(id)
        tabs.remove(at: index)
        recency.removeAll { $0 == id }
        splits.removeAll { $0.contains(id) }
        if activeID == id { activeID = partner ?? tabs[min(index, tabs.count - 1)].id }
        recordVisit()
        return true
    }

    /// Removes routes that no longer exist (trashed pages) from every tab; a tab with nothing left
    /// falls back to `fallback`.
    public mutating func prune(fallback: Route, isGone: (Route) -> Bool) {
        var emptied: [UUID] = []
        for index in tabs.indices where !tabs[index].prune(isGone) {
            tabs[index] = Tab(id: tabs[index].id, route: fallback)
            emptied.append(tabs[index].id)
        }
        // A side of a split with nothing left closes instead, the other side taking the window.
        for id in emptied where split(of: id) != nil { _ = close(id) }
        recordVisit()
    }

    /// `prune` on a copy: equal to `self` when nothing was gone, so an observed owner can skip the assignment (every
    /// assignment of an `@Observable` property notifies, equal or not).
    public func pruned(fallback: Route, isGone: (Route) -> Bool) -> Self {
        var copy = self
        copy.prune(fallback: fallback, isGone: isGone)
        return copy
    }

    /// Where a new tab goes for `index`: never between the two sides of a split (after them instead).
    private func insertionIndex(_ index: Int) -> Int {
        guard index > 0, index < tabs.count,
            splits.contains(where: { $0.leading == tabs[index - 1].id && $0.trailing == tabs[index].id })
        else { return index }
        return index + 1
    }

    /// Drops splits that no longer hold (a side closed, the two no longer next to each other — state saved by an older
    /// build), and a tab joined twice.
    private mutating func tidySplits() {
        var seen = Set<UUID>()
        splits = splits.filter { split in
            guard let at = tabs.firstIndex(where: { $0.id == split.leading }), at + 1 < tabs.count,
                tabs[at + 1].id == split.trailing, !seen.contains(split.leading), !seen.contains(split.trailing)
            else { return false }
            seen.formUnion([split.leading, split.trailing])
            return true
        }
    }

    /// Closes the least recently focused tabs until at most `limit` are left — never one of `kept`, nor one of a split.
    private mutating func evict(beyond limit: Int, sparing kept: Set<UUID>) {
        while tabs.count > max(limit, 1), let oldest = recency.last(where: { !kept.contains($0) && split(of: $0) == nil }) {
            tabs.removeAll { $0.id == oldest }
            recency.removeAll { $0 == oldest }
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
