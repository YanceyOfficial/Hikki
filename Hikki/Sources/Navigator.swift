import HikkiCore
import Observation
import SwiftUI

nonisolated enum Route: Hashable, Codable, Sendable {
    case home
    case trash
    case page(String)

    var pageID: String? {
        if case .page(let id) = self { id } else { nil }
    }
}

struct TitleFocusRequest: Equatable {
    let pageID: String
    let serial: Int
}

/// Per-window navigation: browser-style tabs (each with back/forward history) plus the sidebar's
/// selection and expansion state.
@Observable
final class Navigator {
    private(set) var tabs = NavigationTabs<Route>(initial: .home)
    /// The sidebar list's selection. Usually mirrors the active tab's route; nil on iPhone when the
    /// sidebar is showing (popping back to it clears the selection).
    var sidebarSelection: Route? {
        didSet {
            if let route = sidebarSelection, route != tabs.route { tabs.navigate(to: route) }
        }
    }
    var isSearching = false
    var isShowingSettings = false
    /// Bumped by "Rename": the editor selects that page's title once it has loaded it.
    private(set) var titleFocusRequest: TitleFocusRequest?
    var expanded: Set<String> = []
    /// Sidebar drag state: the page being dragged and where it would land (for the drop indicator).
    var draggingPageID: String?
    var dropIndicator: (pageID: String, zone: DropZone)?
    @ObservationIgnored private(set) weak var model: AppModel?

    var route: Route { tabs.route }

    func attach(_ model: AppModel) {
        self.model = model
    }

    // MARK: Navigation within the active tab

    func open(_ id: String) {
        reveal(id)
        go(.page(id))
    }

    /// Opens the page with its title selected for typing (Notion's Rename, done in the editor so the title
    /// keeps a single write path).
    func rename(_ id: String) {
        open(id)
        titleFocusRequest = TitleFocusRequest(pageID: id, serial: (titleFocusRequest?.serial ?? 0) + 1)
    }

    func go(_ route: Route) {
        tabs.navigate(to: route)
        syncSelection()
    }

    func goBack() {
        tabs.goBack()
        syncSelection()
    }

    func goForward() {
        tabs.goForward()
        syncSelection()
    }

    func newPage(parentId: String? = nil) {
        guard let id = model?.createPage(parentId: parentId) else { return }
        if let parentId { expanded.insert(parentId) }
        go(.page(id))
    }

    // MARK: Tabs

    func openInNewTab(_ route: Route) {
        if let id = route.pageID { reveal(id) }
        tabs.openTab(route)
        syncSelection()
    }

    func selectTab(_ id: UUID) {
        tabs.select(id)
        syncSelection()
    }

    func selectNeighborTab(_ delta: Int) {
        tabs.selectNeighbor(delta)
        syncSelection()
    }

    /// False when it was the last tab (the caller may close the window instead).
    @discardableResult
    func closeTab(_ id: UUID) -> Bool {
        defer { syncSelection() }
        return tabs.close(id)
    }

    /// Drops trashed pages from every tab's history.
    func prune(existing: (String) -> Bool) {
        let before = tabs.route
        tabs.prune(fallback: .home) { route in route.pageID.map { !existing($0) } ?? false }
        // Only when pruning changed the page: re-selecting on every tree change pushed the last page back
        // onto the iPhone stack while the sidebar was showing (e.g. after Duplicate).
        if tabs.route != before { syncSelection() }
    }

    // MARK: Persistence (scene storage)

    func encodedTabs() -> Data? {
        try? JSONEncoder().encode(tabs)
    }

    func restoreTabs(from data: Data?) {
        guard let data, let restored = try? JSONDecoder().decode(NavigationTabs<Route>.self, from: data) else { return }
        tabs = restored
    }

    private func reveal(_ id: String) {
        guard let model else { return }
        for ancestor in model.tree.path(to: id).dropLast() { expanded.insert(ancestor.id) }
    }

    private func syncSelection() {
        if sidebarSelection != tabs.route { sidebarSelection = tabs.route }
    }
}

extension FocusedValues {
    @Entry var editor: EditorController?
    @Entry var navigator: Navigator?
}
