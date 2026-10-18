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

/// Files dropped on the sidebar: imported at the top level, or as children of the page row they were dropped on.
struct ImportDrop: Equatable, Identifiable {
    let id = UUID()
    let urls: [URL]
    let parentID: String?
}

/// An attached file (a PDF) to show in the viewer over the page: the asset's name and the file's own name.
struct DocumentSheetRequest: Equatable, Identifiable {
    let name: String
    let label: String
    var id: String { name }
}

struct TitleFocusRequest: Equatable {
    let pageID: String
    let serial: Int
}

/// A search result opened: its page scrolls to the block the match is in, the (folded) terms selected there.
struct TextRevealRequest: Equatable {
    let pageID: String
    let blockID: String?
    let terms: [String]
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
    /// File → Import… / a page's Import…: the file picker is up.
    var isImporting = false
    /// The page the picked files import under (a page's Import…); nil: the top level (File → Import…).
    private(set) var importParentID: String?

    /// Shows the file picker; what is picked becomes pages under `parentID` (subpages), or top-level pages for nil.
    func importFiles(into parentID: String?) {
        #if DEBUG
            // HIKKI_PICK_FILES=<path>|<path>: the picker's stand-in (it runs out of process) — UI tests.
            if let paths = ProcessInfo.processInfo.environment["HIKKI_PICK_FILES"] {
                importDrop = ImportDrop(urls: paths.split(separator: "|").map { URL(filePath: String($0)) }, parentID: parentID)
                return
            }
        #endif
        importParentID = parentID
        isImporting = true
    }

    /// Files dropped on the sidebar, waiting for ContentView (which has the editor that converts them) to import.
    var importDrop: ImportDrop?
    /// An attached PDF shown over the page (`showDocument`).
    var documentSheet: DocumentSheetRequest?
    /// Split view (Mac/iPad): the window shows a second pane beside the current tab.
    private(set) var isSplit = false
    /// Whether this window may split (`DeviceRules.allowsSplit`); set by ContentView. A window that
    /// can no longer split closes its pane.
    var splitAllowed = true {
        didSet { if !splitAllowed && isSplit { closeSplit() } }
    }
    /// What the second pane shows — a page or a file; nil while it offers a picker.
    private(set) var split: Route?
    /// While split: a page is held over the left side's right edge, so dropping it replaces the right side — which
    /// outlines itself whole (the left side draws no zone of its own; a half-width one read as a third column).
    var splitDropHover = false
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
    private(set) var textRevealRequest: TextRevealRequest?
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

    /// Opens a search result's page at the block it matched, those words selected.
    func open(_ id: String, at blockID: String?, revealing terms: [String]) {
        open(id)
        textRevealRequest = TextRevealRequest(
            pageID: id, blockID: blockID, terms: terms, serial: (textRevealRequest?.serial ?? 0) + 1)
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

    /// A page made from a quick note (Home), opened.
    func newPage(_ note: QuickNote) {
        guard let id = model?.createPage(note) else { return }
        go(.page(id))
    }

    /// Ask AI opened with a question to send at once, about these pages (Home's suggestions); ContentView sends it.
    var pendingAIQuestion: (text: String, pageIDs: [String])?

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
        guard splitAllowed, route.canSplit else { return }
        isSplit = true
        isShowingInspector = false
        // The same page may be on both sides (write on the left, read on the right): the editors reload each
        // other's saves (`EditorController.pageSavedInEditor`).
        split = route
        if let id = route.pageID { reveal(id) }
    }

    /// The split pane with nothing in it yet: it offers recent pages and PDFs to pick from.
    func showSplitPicker() {
        guard splitAllowed else { return }
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

    /// An attached PDF clicked in a page: it opens in a viewer over the page (a sheet on the Mac, a full-screen cover on
    /// iOS), so the page stays in its tab and the PDF can still go beside it (the sheet's Open in Split View).
    func showDocument(name: String, label: String) {
        documentSheet = DocumentSheetRequest(name: name, label: label)
    }

    /// The PDF in a pane of its own in a tab (`Route.file`, or its tab gets focus) — `HIKKI_OPEN_FILE` screenshots.
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

    // MARK: The tab menu (Chrome's)

    /// What the tab `id` shows (nil: no such tab).
    func route(ofTab id: UUID) -> Route? {
        tabs.tabs.first { $0.id == id }?.route
    }

    /// "New Tab to the Right": Home in a new tab right after `id`, as "+" opens.
    func newTab(rightOf id: UUID) {
        tabs.openTab(.home, after: id)
        syncSelection()
    }

    func duplicateTab(_ id: UUID) {
        tabs.duplicate(id)
        syncSelection()
    }

    func closeOtherTabs(_ id: UUID) {
        tabs.closeOthers(id)
        syncSelection()
    }

    func closeTabs(rightOf id: UUID) {
        tabs.closeTabs(after: id)
        syncSelection()
    }

    /// "Open in Split View": the tab's page (or file) in the pane beside the current tab; the tab stays.
    func openTabInSplit(_ id: UUID) {
        if let route = route(ofTab: id) { openInSplit(route) }
    }

    /// Drops trashed pages from every tab's history.
    func prune(existing: (String) -> Bool) {
        let before = tabs.route
        // Assigned only when a page actually left: this runs on every tree change (every save), and assigning an
        // equal value still re-rendered the window.
        let pruned = tabs.pruned(fallback: .home) { route in route.pageID.map { !existing($0) } ?? false }
        guard pruned != tabs else { return }
        tabs = pruned
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
        let ancestors = model.tree.path(to: id).dropLast().map(\.id)
        // Only when one is new: inserting a member already there still notified every sidebar row.
        if !expanded.isSuperset(of: ancestors) { expanded.formUnion(ancestors) }
    }

    private func syncSelection() {
        if sidebarSelection != tabs.route { sidebarSelection = tabs.route }
    }
}

extension FocusedValues {
    @Entry var editor: EditorController?
    @Entry var navigator: Navigator?
    /// The window's AI chat, for File → New AI Chat (⇧⌘N) while the AI panel shows it.
    @Entry var aiChat: AIChat?
    /// Whether the open page is locked (nil on Home / Trash) — a plain value for the menu bar: reading the
    /// model's tree from `Commands` through the navigator made the main menu and the scene rebuild each
    /// other without end.
    @Entry var lockedPage: Bool?
}
