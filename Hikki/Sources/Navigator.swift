import HikkiCore
import HikkiUI
import Observation
import SwiftUI

nonisolated enum Route: Hashable, Codable, Sendable {
    case home
    case trash
    case page(String)
    /// An attached file shown in a pane of its own (a PDF): the asset's name and the file's own name.
    case file(name: String, label: String)

    var pageID: String? {
        if case .page(let id) = self { id } else { nil }
    }

    /// A page or a file: what a split pane can show (Home and Trash stay in tabs).
    var canSplit: Bool {
        switch self {
        case .page, .file: true
        case .home, .trash: false
        }
    }
}

/// A page to export in a format.
struct ExportRequest: Equatable, Identifiable {
    let pageID: String
    let format: PageExport.Format
    var id: String { "\(pageID).\(format.rawValue)" }
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
    /// The Ask AI sheet (iPhone's bottom bar).
    var isAskingAI = false
    /// The page whose actions sheet is open (iPhone's ⋯).
    var pageActionsID: String?
    /// iPhone: which column of the collapsed split view shows — the home screen (sidebar) or the page (detail).
    /// Opening anything shows the detail; the system's back sets it back.
    var compactColumn: NavigationSplitViewColumn = .sidebar
    var isShowingSettings = false
    /// Page ⋯ → Page History…: the page whose versions the history sheet shows.
    var historyPageID: String?
    /// Page ⋯ → Export: the page and format being exported (ContentView presents the save panel / exporter).
    var exportRequest: ExportRequest?
    /// File → Import… / the workspace menu: the file picker is up.
    var isImporting = false
    /// Split view (Mac/iPad): the window shows a second pane beside the current tab.
    private(set) var isSplit = false
    /// What the second pane shows — a page or a file; nil while it offers a picker.
    private(set) var split: Route?
    /// The trailing inspector (outline, info, calendar) — remembered across launches by ContentView.
    var isShowingInspector = false
    var inspectorMode: InspectorMode = .outline

    /// A toolbar button for one mode: opens the panel on it, or closes the panel when it already shows it.
    func toggleInspector(_ mode: InspectorMode) {
        if isShowingInspector && inspectorMode == mode {
            isShowingInspector = false
        } else {
            inspectorMode = mode
            isShowingInspector = true
        }
    }
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
        compactColumn = .detail
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

    /// A page dropped on the tab strip: between tabs it opens there (or its tab is focused), onto a tab it
    /// shows in that tab.
    func dropPage(_ id: String, _ target: TabStripDropTarget) {
        reveal(id)
        switch target {
        case .between(let index): tabs.openTab(.page(id), at: index)
        case .onto(let tabID): tabs.navigate(tabID, to: .page(id))
        }
        syncSelection()
    }

    /// How many tabs sidebar picks keep in the strip (the least recently used one closes past this).
    static let recentTabLimit = 6

    // MARK: Split view

    /// Opens (or replaces) the pane beside the current tab. The same page can't be on both sides (two editors on one page
    /// would overwrite each other), so asking for the left side's page swaps nothing and shows the picker instead.
    func openInSplit(_ route: Route) {
        guard route.canSplit else { return }
        isSplit = true
        isShowingInspector = false
        // The same page may be on both sides (write on the left, read on the right): the editors reload each
        // other's saves (`EditorController.pageSavedInEditor`).
        split = route
        if let id = route.pageID { reveal(id) }
    }

    /// The split pane with nothing in it yet: it offers recent pages and PDFs to pick from.
    func showSplitPicker() {
        isSplit = true
        // The inspector belongs to the left page but would sit beside the right one: it closes with a split.
        isShowingInspector = false
        split = nil
    }

    func closeSplit() {
        isSplit = false
        split = nil
    }

    func toggleSplit() {
        if isSplit { closeSplit() } else { showSplitPicker() }
    }

    /// The pane's page left the workspace (trashed, deleted): the pane closes.
    func pruneSplit(existing: (String) -> Bool) {
        if let id = split?.pageID, !existing(id) { closeSplit() }
    }

    /// A sidebar row: its tab gets focus, or it joins the strip as a new tab (the oldest leaves past the limit).
    func openFromSidebar(_ route: Route) {
        if let id = route.pageID { reveal(id) }
        tabs.openRecent(route, limit: Self.recentTabLimit)
        syncSelection()
    }

    /// An attached PDF clicked in a page: it opens in a viewer pane in a tab of its own (or its tab gets focus).
    func openDocument(name: String, label: String) {
        tabs.openRecent(.file(name: name, label: label), limit: Self.recentTabLimit)
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

    /// Page → Copy Link (⌥⌘C): the open page's hikki://page/<id>.
    func copyCurrentPageLink() {
        if let id = route.pageID { PageLink.copyToPasteboard(id) }
    }

    /// The open page's summary (nil on Home / Trash).
    var currentPage: PageSummary? {
        route.pageID.flatMap { model?.tree.page($0) }
    }

    /// Page → Lock / Unlock (⇧⌘L).
    func toggleLockCurrentPage() {
        guard let page = currentPage else { return }
        model?.setLocked(!page.isLocked, id: page.id)
    }

    /// Expands the sidebar path to the open page (switching tabs, back/forward, the tree loading after launch).
    func revealCurrent() {
        if let id = route.pageID { reveal(id) }
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
    /// Whether the open page is locked (nil on Home / Trash) — a plain value for the menu bar: reading the
    /// model's tree from `Commands` through the navigator made the main menu and the scene rebuild each
    /// other without end.
    @Entry var lockedPage: Bool?
}
