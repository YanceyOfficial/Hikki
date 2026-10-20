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
    /// A split pane with nothing in it yet: recent pages and PDFs to pick from. Only ever inside a split.
    case splitPicker

    var pageID: String? {
        if case .page(let id) = self { id } else { nil }
    }

    /// A page or a file: what a split pane can show (Home and Trash stay in tabs).
    var canSplit: Bool {
        switch self {
        case .page, .file: true
        case .home, .trash, .splitPicker: false
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

/// A side of a split window. Neither is the "main" one: the leading side is simply the split's first tab.
enum PaneSide: String, Hashable, Sendable {
    case leading, trailing
}

/// What a side of the window shows: a tab, and the page (or Home, a PDF…) it is on.
struct Pane: Equatable {
    let tab: UUID
    let route: Route
}

/// A side's panel beside its page (outline, comments, AI).
struct InspectorState: Equatable {
    var isShowing = false
    var mode: InspectorMode = .outline
}

/// A request AI on the selection handed to the chat, and the side whose editor it came from — that side's panel takes it.
struct PaneHandoff: Equatable {
    let handoff: AIHandoff
    let side: PaneSide
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
    /// Whether this window may split (`DeviceRules.allowsSplit`); set by ContentView. A window that
    /// can no longer split comes apart.
    var splitAllowed = true {
        didSet { if !splitAllowed && isSplit { closeSplit() } }
    }
    /// While split: a page is held over the leading side's right edge, so dropping it replaces the trailing side —
    /// which outlines itself whole (the leading side draws no zone of its own; a half-width one read as a third column).
    var splitDropHover = false
    /// Each side's panel (outline, comments, AI), by position; they trade places with the pages when the sides swap.
    private var inspectors: [PaneSide: InspectorState] = [:]
    /// The mode a side's panel opens on when it has none yet (the last one picked, remembered by ContentView).
    private var lastInspectorMode: InspectorMode = .outline

    func inspector(_ side: PaneSide) -> InspectorState {
        inspectors[side] ?? InspectorState(isShowing: false, mode: lastInspectorMode)
    }

    func setInspector(_ side: PaneSide, _ state: InspectorState) {
        guard inspector(side) != state else { return }
        inspectors[side] = state
        lastInspectorMode = state.mode
    }

    /// The focused side's panel — what the menus and the shortcuts act on.
    var isShowingInspector: Bool {
        get { inspector(focusedSide).isShowing }
        set { setInspector(focusedSide, InspectorState(isShowing: newValue, mode: inspector(focusedSide).mode)) }
    }

    var inspectorMode: InspectorMode {
        get { inspector(focusedSide).mode }
        set { setInspector(focusedSide, InspectorState(isShowing: inspector(focusedSide).isShowing, mode: newValue)) }
    }

    /// A button for one mode: opens the side's panel on it, or closes the panel when it already shows it.
    func toggleInspector(_ mode: InspectorMode, side: PaneSide? = nil) {
        let side = side ?? focusedSide
        let state = inspector(side)
        setInspector(side, InspectorState(isShowing: !(state.isShowing && state.mode == mode), mode: mode))
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
    /// A request AI on the selection handed to the chat (either side's editor), waiting for ContentView to open the chat —
    /// that side's panel, or the Ask AI sheet (`AIHandoff.placement`) — and send it there.
    var aiHandoff: PaneHandoff?

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

    /// Split view (Mac/iPad): two tabs side by side, equals (`NavigationTabs.Split`) — the window shows one when its
    /// focused tab is in one.
    var isSplit: Bool { tabs.activeSplit != nil }

    /// What the leading side shows: the split's first tab, or the focused tab when the window isn't split.
    var leadingPane: Pane {
        let id = tabs.activeSplit?.leading ?? tabs.activeID
        return Pane(tab: id, route: route(ofTab: id) ?? tabs.route)
    }

    /// What the trailing side shows; nil when the window isn't split.
    var trailingPane: Pane? {
        guard let id = tabs.activeSplit?.trailing, let route = route(ofTab: id) else { return nil }
        return Pane(tab: id, route: route)
    }

    func pane(_ side: PaneSide) -> Pane? {
        side == .leading ? leadingPane : trailingPane
    }

    /// The side the reader is working in: menus, shortcuts and the sidebar act on it, and its half of the tab is marked.
    var focusedSide: PaneSide {
        tabs.activeSplit?.trailing == tabs.activeID ? .trailing : .leading
    }

    /// A click or a tap in a side: it gets the focus.
    func focus(_ side: PaneSide) {
        guard let pane = pane(side), pane.tab != tabs.activeID else { return }
        tabs.select(pane.tab)
        syncSelection()
    }

    /// Shows `route` beside the focused side: in the other side when split (replacing what it shows), else in a new tab
    /// joined to the focused one. The same page may be on both sides (write on one, read on the other): the editors
    /// reload each other's saves (`EditorController.pageSavedInEditor`).
    func openInSplit(_ route: Route) {
        guard splitAllowed, route.canSplit || route == .splitPicker else { return }
        tabs.openSplit(route, beside: tabs.activeID)
        if let id = route.pageID { reveal(id) }
        tidyTabs()
    }

    /// A page dropped on the leading side's right edge: beside it — in the trailing side when split already.
    func openBeside(_ route: Route) {
        if isSplit { show(route, in: .trailing) } else { openInSplit(route) }
    }

    /// A side with nothing in it yet: it offers recent pages and PDFs to pick from. Beside the focused side, or — given
    /// a side — in that side ("More…" in its title's menu).
    func showSplitPicker(in side: PaneSide? = nil) {
        guard splitAllowed else { return }
        if let side, let pane = pane(side) {
            tabs.navigate(pane.tab, to: .splitPicker)
            syncSelection()
        } else {
            openInSplit(.splitPicker)
        }
    }

    /// What a side shows, picked in it (its picker, its title's menu, a page dropped on it): the picker gives way to it
    /// with no history entry; a page shown before goes into the side's history. The side gets the focus.
    func show(_ route: Route, in side: PaneSide) {
        guard let pane = pane(side) else { return }
        if pane.route == .splitPicker {
            tabs.replace(pane.tab, with: route)
            tabs.select(pane.tab)
        } else {
            tabs.navigate(pane.tab, to: route)
        }
        if let id = route.pageID { reveal(id) }
        syncSelection()
    }

    /// Ends the split (⌘\): both pages stay tabs, the focused one shown (an empty side just goes).
    func closeSplit() {
        guard let split = tabs.activeSplit else { return }
        if focusedSide == .trailing { inspectors[.leading] = inspectors[.trailing] }
        inspectors[.trailing] = nil
        tabs.separate(split.leading)
        tidyTabs()
        syncSelection()
    }

    /// A side's ✕: its tab closes and the other side has the window.
    func closePane(_ side: PaneSide) {
        guard isSplit, let pane = pane(side) else { return }
        closeTab(pane.tab)
    }

    /// The two sides trade places, each with its panel.
    func swapSides() {
        guard isSplit else { return }
        tabs.swapSplit(tabs.activeID)
        let leading = inspectors[.leading]
        inspectors[.leading] = inspectors[.trailing]
        inspectors[.trailing] = leading
    }

    func toggleSplit() {
        if isSplit { closeSplit() } else { showSplitPicker() }
    }

    /// An empty side is only ever part of a split: one left on its own (its split came apart) closes.
    private func tidyTabs() {
        guard tabs.tabs.contains(where: { $0.route == .splitPicker && tabs.split(of: $0.id) == nil }) else { return }
        tabs.closeLoose({ $0 == .splitPicker }, fallback: .home)
        syncSelection()
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
        if let split = tabs.activeSplit, split.contains(id) {
            // A side of the split on screen going: the other one has the window, its panel with it.
            if id == split.leading { inspectors[.leading] = inspectors[.trailing] }
            inspectors[.trailing] = nil
        }
        defer {
            tidyTabs()
            syncSelection()
        }
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
        tidyTabs()
        syncSelection()
    }

    func closeTabs(rightOf id: UUID) {
        tabs.closeTabs(after: id)
        tidyTabs()
        syncSelection()
    }

    /// "Open in Split View": the tab joins the focused one, on its right (the focused tab itself: an empty side beside
    /// it).
    func openTabInSplit(_ id: UUID) {
        guard splitAllowed else { return }
        if id == tabs.activeID {
            if !isSplit { openInSplit(.splitPicker) }
            return
        }
        tabs.join(tabs.activeID, with: id)
        tidyTabs()
    }

    /// "Separate" in a split tab's menu: both stay tabs.
    func separateTab(_ id: UUID) {
        if tabs.activeSplit?.contains(id) == true {
            closeSplit()
        } else {
            tabs.separate(id)
            tidyTabs()
        }
    }

    /// "Swap Sides" in a split tab's menu.
    func swapTab(_ id: UUID) {
        if tabs.activeSplit?.contains(id) == true { swapSides() } else { tabs.swapSplit(id) }
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
        // A side's picker is for the moment it's open: it leaves every history, and a side that held nothing else
        // doesn't come back (the window opens on the page beside it, unsplit).
        tabs.prune(fallback: .home) { $0 == .splitPicker }
        tidyTabs()
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
