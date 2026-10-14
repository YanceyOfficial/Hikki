import CoreSpotlight
import HikkiCore
import HikkiUI
import QuickLook
import SwiftUI

struct ContentView: View {
    /// A page to show on open (a window opened with "Open in new window").
    var initialPageID: String?
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    // One editor (and one WKWebView) per window, reused across pages and tabs.
    @State private var editor = EditorController()
    /// The split pane's editor (a second web view), made the first time a page opens in the pane.
    @State private var splitEditor: EditorController?
    @State private var navigator = Navigator()
    @State private var columns: NavigationSplitViewVisibility = .all
    @SceneStorage("tabs") private var storedTabs: Data?
    private let tone = ColorTone.standard
    @AppStorage(EditorPreferences.spellcheckKey) private var spellcheck = true
    #if os(macOS)
        @Environment(\.openSettings) private var openSettings
    #endif

    var body: some View {
        // Split in two so the type checker copes: the layout, then the scene's events.
        sceneEvents(layout)
            .focusedSceneValue(\.editor, editor)
            .focusedSceneValue(\.navigator, navigator)
            .focusedSceneValue(\.lockedPage, navigator.currentPage?.isLocked)
    }

    /// The system split view and window toolbar (the sidebar is native rows, see SidebarView), sheets.
    private var layout: some View {
        @Bindable var navigator = navigator
        @Bindable var editor = editor
        return NavigationSplitView(columnVisibility: $columns) {
            SidebarView(navigator: navigator, wide: wide)
                .navigationSplitViewColumnWidth(min: Size.sidebarMin, ideal: Size.sidebarIdeal, max: Size.sidebarMax)
        } detail: {
            // The inspector takes its room from the page, never from the screen: a panel inside the detail column
            // (SwiftUI's `.inspector` widened the window instead). A sheet on iPhone.
            HStack(spacing: Spacing.s0) {
                SplitDetail(navigator: navigator, splitEditor: splitEditor) {
                    DetailView(navigator: navigator, editor: editor, phoneToolbar: !wide)
                }
                if wide && navigator.isShowingInspector && navigator.route.pageID != nil {
                    InspectorPanel(navigator: navigator, editor: editor)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(Motion.easeOut(), value: navigator.isShowingInspector)
            .animation(Motion.easeOut(), value: navigator.isSplit)
            .background(Theme.background)
            #if os(macOS)
                // Photos' way: with the inspector open the page title and subtitle leave the toolbar, so the tabs keep
                // their width.
                .toolbar(removing: navigator.isShowingInspector && navigator.route.pageID != nil ? .title : nil)
            #endif
            .toolbar { if wide { NativeDetailToolbar(navigator: navigator, editor: editor) } }
            .sheet(
                isPresented: Binding(
                    get: { !wide && navigator.isShowingInspector && navigator.route.pageID != nil },
                    set: { navigator.isShowingInspector = $0 })
            ) {
                InspectorView(navigator: navigator, editor: editor)
                    .presentationDetents([.medium, .large])
            }
        }
        #if os(iOS)
            .sheet(isPresented: $navigator.isShowingSettings) { SettingsView() }
        #else
            .background(HideOnClose())
        #endif
        .sheet(isPresented: $navigator.isSearching) {
            SearchPalette(navigator: navigator) { navigator.isSearching = false }
        }
        .animation(.snappy(duration: 0.18), value: navigator.isSearching)
        // Attachments opened from the editor.
        .quickLookPreview($editor.previewURL)
        // "Open in Split View" wherever page actions are (sidebar, Home, ⋯): by the window's width, not a column's.
        .environment(\.splitAvailable, wide)
    }

    /// Setup, routing to the editor, settings, deep links, tab persistence, backgrounding.
    private func sceneEvents(_ content: some View) -> some View {
        content
            .task { await model.observe() }
            .onAppear(perform: setUp)
            .onChange(of: navigator.route) { _, route in
                editor.open(documentID: route.pageID)
                navigator.revealCurrent()
            }
            .onChange(of: wide) { editor.setSplitDrop(mainSplitDrop) }
            .onChange(of: navigator.isSplit) { editor.setSplitDrop(mainSplitDrop) }
            .onChange(of: spellcheck) { _, on in
                editor.setSpellcheck(on)
                splitEditor?.setSpellcheck(on)
            }
            // Settings → Shortcuts: the page handles the editor's own keys, so it hears about rebindings.
            .onChange(of: ShortcutStore.shared.overrides) {
                editor.updateShortcuts()
                splitEditor?.updateShortcuts()
            }
            // The split pane's page: its own editor, made on first use and wired like the main one.
            .onChange(of: navigator.split) { _, split in
                guard let id = split?.pageID else { return }
                splitPaneEditor().open(documentID: id)
            }
            // The inspector's state outlives the window; the page's own outline rail steps aside while the
            // inspector shows the outline.
            .onChange(of: navigator.isShowingInspector) { _, on in
                editor.setOutlineRail(!(on && navigator.inspectorMode == .outline))
            }
            .onChange(of: navigator.inspectorMode) { _, mode in
                UserDefaults.standard.set(mode.rawValue, forKey: InspectorPreferences.tabKey)
                editor.setOutlineRail(!(navigator.isShowingInspector && mode == .outline))
            }
            // Lock / unlock while the page is open (the load payload carries it otherwise).
            .onChange(of: navigator.currentPage?.isLocked) { _, locked in editor.setLocked(locked ?? false) }
            .onChange(of: navigator.titleFocusRequest) { _, request in
                if let request { editor.focusTitle(of: request.pageID) }
            }
            // A page picked in Spotlight (SpotlightIndex.swift).
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String, model.tree.page(id) != nil
                else { return }
                navigator.open(id)
            }
            // hikki://page/<id> (Copy link).
            .onOpenURL { url in
                guard let id = PageLink.pageID(from: url), model.tree.page(id) != nil else { return }
                navigator.open(id)
                if let block = PageLink.blockID(from: url) { editor.scrollToBlock(block, in: id) }
            }
            // Menu bar extra: New Page / Search land in the key window (MenuBarExtra.swift).
            .menuBarRequests(navigator: navigator)
            // Full screen (macOS): menu bar, traffic lights and toolbar stay, as in a window (FullScreenChrome.swift).
            .fullScreenChrome()
            .onChange(of: navigator.tabs) { _, _ in storedTabs = navigator.encodedTabs() }
            .onChange(of: model.tree) { _, tree in
                // Pages trashed here or in another window disappear from every tab's history.
                navigator.prune { tree.page($0) != nil }
                navigator.pruneSplit { tree.page($0) != nil }
                splitEditor?.setPages(tree.all)
                navigator.revealCurrent()
                editor.setPages(tree.all)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    model.reconcileWorkspace()  // pick up other devices' changes
                    model.purgeTrash()
                } else {
                    Task {
                        await editor.flush(reason: "scenePhase-\(phase)")
                        await splitEditor?.flush(reason: "scenePhase-\(phase)")
                        model.flushWorkspace()
                    }
                }
            }
    }

    /// First appearance: tabs, the editor's settings and store, DEBUG hooks, the first page.
    private func setUp() {
        navigator.attach(model)
        navigator.restoreTabs(from: storedTabs)
        editor.onOpenDocument = { [navigator] name, label in navigator.openDocument(name: name, label: label) }
        // A page dropped on the page's right edge opens beside it (split view).
        editor.onOpenInSplit = { [navigator] id in
            if model.tree.page(id) != nil { navigator.openInSplit(.page(id)) }
        }
        editor.setSplitDrop(mainSplitDrop)
        // The inspector starts closed in every window (its tab is remembered); `-inspector.visible YES` opens it
        // (screenshots).
        // Only the launch argument counts; a value saved by earlier builds (which remembered it) is dropped.
        let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        UserDefaults.standard.removeObject(forKey: InspectorPreferences.visibleKey)
        navigator.isShowingInspector = (arguments[InspectorPreferences.visibleKey] as? String).map { $0 == "YES" } ?? false
        // (A mode saved by older builds — info, calendar — falls back to the outline.)
        if let raw = UserDefaults.standard.string(forKey: InspectorPreferences.tabKey), let mode = InspectorMode(rawValue: raw) {
            navigator.inspectorMode = mode
        }
        editor.setOutlineRail(!(navigator.isShowingInspector && navigator.inspectorMode == .outline))
        #if DEBUG
            // Screenshot/test hooks: HIKKI_OPEN_TABS=pageA,pageB opens those pages as tabs; HIKKI_OPEN_SEARCH opens ⌘K
            // (with its value as the query).
            if ProcessInfo.processInfo.environment["HIKKI_OPEN_SEARCH"] != nil { navigator.isSearching = true }
            // HIKKI_OPEN_FIND opens find in page once the page is up (screenshots of its place under the toolbar).
            if ProcessInfo.processInfo.environment["HIKKI_OPEN_FIND"] != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { editor.find(.find) }
            }
            // HIKKI_ACTIVATE brings the window to the front (screenshots of the active-window look).
            #if os(macOS)
                if ProcessInfo.processInfo.environment["HIKKI_ACTIVATE"] != nil { NSApp.activate() }
            #endif
            // HIKKI_OPEN_SETTINGS opens Settings (screenshots); a page name (`SettingsPage`) as its value opens that page.
            if let value = ProcessInfo.processInfo.environment["HIKKI_OPEN_SETTINGS"] {
                if SettingsPage(rawValue: value) != nil { UserDefaults.standard.set(value, forKey: SettingsPage.storageKey) }
                #if os(macOS)
                    openSettings()
                #else
                    navigator.isShowingSettings = true
                #endif
            }
            // HIKKI_DEBUG_SPOTLIGHT_QUERY=<text> asks Spotlight for pages once indexing settled and logs the ids it
            // ranks (judging its semantic matching).
            if let text = ProcessInfo.processInfo.environment["HIKKI_DEBUG_SPOTLIGHT_QUERY"] {
                Task {
                    try? await Task.sleep(for: .seconds(8))
                    await model.searchIndexer.debugSpotlightQuery(text)
                }
            }
            // HIKKI_OPEN_SPLIT=<page id> | file:<asset name> | picker opens the split pane on it (screenshots).
            if let value = ProcessInfo.processInfo.environment["HIKKI_OPEN_SPLIT"] {
                if value == "picker" {
                    navigator.showSplitPicker()
                } else if value.hasPrefix("file:") {
                    let name = String(value.dropFirst(5))
                    navigator.openInSplit(.file(name: name, label: name))
                } else {
                    navigator.openInSplit(.page(value))
                }
            }
            // HIKKI_OPEN_FILE=<asset name> opens that attachment in the viewer pane (screenshots of the PDF viewer).
            if let name = ProcessInfo.processInfo.environment["HIKKI_OPEN_FILE"] {
                navigator.openDocument(name: name, label: name)
            }
            // HIKKI_DEBUG_NAV=a,b,c visits those pages one per second (reproduces page-switch bugs).
            if let ids = ProcessInfo.processInfo.environment["HIKKI_DEBUG_NAV"]?.split(separator: ",") {
                Task {
                    for id in ids {
                        try? await Task.sleep(for: .seconds(1))
                        navigator.open(String(id))
                    }
                }
            }
            // HIKKI_DEBUG_SIDEBAR: hides the sidebar after 2s and shows it again after 4s (title-bar layout bugs).
            if ProcessInfo.processInfo.environment["HIKKI_DEBUG_SIDEBAR"] != nil {
                Task {
                    #if os(macOS)
                        NSApp.activate()  // the bug shows on a key window
                    #endif
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation { columns = .detailOnly }
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation { columns = .all }
                }
            }
            // "home" opens Home (screenshots of it on iPhone, where the root is the sidebar).
            if let ids = ProcessInfo.processInfo.environment["HIKKI_OPEN_TABS"]?.split(separator: ",") {
                for (index, id) in ids.enumerated() {
                    let route: Route = id == "home" ? .home : .page(String(id))
                    if index == 0 { navigator.go(route) } else { navigator.openInNewTab(route) }
                }
            }
        #endif
        if let initialPageID, model.tree.page(initialPageID) != nil { navigator.open(initialPageID) }
        editor.setTone(tone)
        editor.setSpellcheck(spellcheck)
        editor.attach(store: model.store, assets: model.assets)
        editor.onOpenPage = { id, block in
            guard model.tree.page(id) != nil else { return }
            navigator.open(id)
            if let block { editor.scrollToBlock(block, in: id) }
        }
        editor.setPages(model.tree.all)
        editor.open(documentID: navigator.route.pageID)
    }

    /// The split pane's editor, made and wired on first use: same store, assets, pages and settings as the main one; a
    /// link clicked in it opens in the pane, a PDF attachment in a tab.
    private func splitPaneEditor() -> EditorController {
        if let splitEditor { return splitEditor }
        let pane = EditorController()
        pane.setTone(tone)
        pane.setSpellcheck(spellcheck)
        pane.attach(store: model.store, assets: model.assets)
        pane.onOpenPage = { [navigator] id, block in
            guard model.tree.page(id) != nil else { return }
            navigator.openInSplit(.page(id))
            if let block { pane.scrollToBlock(block, in: id) }
        }
        pane.onOpenDocument = { [navigator] name, label in navigator.openInSplit(.file(name: name, label: label)) }
        // Dropped on the pane's own right edge: it shows that page instead.
        pane.onOpenInSplit = { [navigator] id in
            if model.tree.page(id) != nil { navigator.openInSplit(.page(id)) }
        }
        pane.setSplitDrop(.here)
        pane.setPages(model.tree.all)
        splitEditor = pane
        return pane
    }

    /// What a page dropped on the left page's right edge does: opens beside it, or replaces the right side.
    private var mainSplitDrop: EditorController.SplitDropMode {
        wide ? (navigator.isSplit ? .replace : .open) : .off
    }

    /// A wide window (Mac, regular-width iPad): tabs and page actions in the window toolbar, the workspace
    /// switcher in the sidebar. iPhone keeps its navigation bar.
    private var wide: Bool {
        #if os(macOS)
            true
        #else
            sizeClass == .regular
        #endif
    }
}

/// The detail column: the routed content.
private struct DetailView: View {
    let navigator: Navigator
    let editor: EditorController
    /// iPhone: the page's actions live in its navigation bar.
    var phoneToolbar = true

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
    }

    @ViewBuilder private var content: some View {
        switch navigator.route {
        case .page(let id):
            PageScreen(pageID: id, editor: editor, navigator: navigator, phoneToolbar: phoneToolbar)
        case .trash:
            TrashView()
        case .file(let name, let label):
            DocumentPane(name: name, label: label, editor: editor)
        case .home:
            HomeView(navigator: navigator)
        }
    }
}

/// EXPERIMENT: the detail column's window toolbar on Mac/iPad — tabs (with back/forward) in the middle,
/// the page's favorite and ⋯ on the trailing side; the page title and edited time are the window's title.
private struct NativeDetailToolbar: ToolbarContent {
    @Environment(AppModel.self) private var model
    let navigator: Navigator
    let editor: EditorController
    @AppStorage(InspectorPreferences.widthKey) private var inspectorWidth = Double(Size.inspectorIdeal)

    private var inspectorOpen: Bool { navigator.isShowingInspector && navigator.route.pageID != nil }

    // Photos' toolbar: each group is its own Liquid Glass capsule — back/forward, the tabs, the page's
    // actions. (Search lives in the sidebar's glass field.)
    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            // One control with a divider between the two (‹ | ›), as in Finder/Safari.
            ControlGroup {
                Button(action: navigator.goBack) { IconLabel("app:chrome.back", icon: .caretLeft) }
                    .disabled(!navigator.tabs.active.canGoBack)
                Button(action: navigator.goForward) { IconLabel("app:chrome.forward", icon: .caretRight) }
                    .disabled(!navigator.tabs.active.canGoForward)
            }
            #if os(macOS)
                .controlGroupStyle(.navigation)
            #endif
        }
        ToolbarItem(placement: .principal) {
            TabStrip(
                items: navigator.tabs.tabs.map { tab in tabItem(tab.id, tab.route) },
                activeID: navigator.tabs.activeID,
                canGoBack: navigator.tabs.active.canGoBack,
                canGoForward: navigator.tabs.active.canGoForward,
                onSelect: navigator.selectTab,
                onClose: { navigator.closeTab($0) },
                onNew: { navigator.openInNewTab(.home) },
                onBack: navigator.goBack,
                onForward: navigator.goForward,
                showsHistory: false,
                // A sidebar page dragged here opens as a tab (between tabs) or in a tab (onto one).
                drop: TabStripDrop(
                    types: [.plainText],
                    accepts: { navigator.draggingPageID != nil },
                    perform: { target in
                        guard let id = navigator.draggingPageID else { return false }
                        navigator.draggingPageID = nil
                        navigator.dropPage(id, target)
                        return true
                    }),
                // A page's tab drags its link: onto the split pane, the page's right edge, or into a page.
                dragItem: { id in
                    navigator.tabs.tabs.first { $0.id == id }?.route.pageID.map(PageLink.dragItem)
                }
            )
            .frame(minWidth: 240, idealWidth: 480, maxWidth: 640)  // design-lint: allow (toolbar item width)
            // The toolbar centres it over the whole detail column; with the inspector open that is page + panel, so
            // it moves left by half the panel to sit over the page.
            // Its own glass (the toolbar's shared capsule is hidden below), so the capsule moves with it.
            .glassEffect(.regular, in: .capsule)
            .offset(x: inspectorOpen ? -CGFloat(inspectorWidth) / 2 : 0)
            .animation(Motion.easeOut(), value: inspectorOpen)
        }
        .sharedBackgroundVisibility(.hidden)
        if let id = navigator.route.pageID, let page = model.tree.page(id) {
            // While split they would act on the left page only, from the right end of the window: off until it closes.
            if page.isLocked {
                ToolbarItem(placement: .primaryAction) {
                    LockIndicator(page: page, toolbar: true).disabled(navigator.isSplit)
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                FavoriteButton(page: page, toolbar: true).disabled(navigator.isSplit)
                PageMoreMenu(page: page, navigator: navigator, editor: editor, toolbar: true).disabled(navigator.isSplit)
            }
        }
        // The side panel's modes, at the trailing end as in Xcode, in a glass group of their own: the outline and AI
        // (comments later), each a toggle that shows as on while the panel shows it. Only where there is a page; off
        // while split (the panel belongs to the left page). Split view itself opens by drag, ⌘\ or "Open in Split
        // View".
        if navigator.route.pageID != nil {
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) {
                Toggle(isOn: inspectorBinding(.outline)) {
                    IconLabel("app:inspector.outline", icon: .listBullets)
                }
                .toggleStyle(.button)
                .help("app:inspector.outline")
                .disabled(navigator.isSplit)
                .accessibilityIdentifier("inspector-toggle")
            }
            ToolbarItem(placement: .primaryAction) {
                Toggle(isOn: inspectorBinding(.ai)) {
                    Label {
                        Text("app:inspector.ai")
                    } icon: {
                        AIGlyph(tinted: navigator.isShowingInspector && navigator.inspectorMode == .ai)
                    }
                }
                .toggleStyle(.button)
                .help("app:inspector.ai")
                .disabled(navigator.isSplit)
                .accessibilityIdentifier("ai-toggle")
            }
        }
    }

    private func tabItem(_ id: UUID, _ route: Route) -> TabStripItem {
        switch route {
        case .home: TabStripItem(id: id, title: String(localized: "app:nav.home"), symbol: .house)
        case .trash: TabStripItem(id: id, title: String(localized: "app:nav.trash"), symbol: .trash)
        case .file(_, let label): TabStripItem(id: id, title: label, symbol: .fileText)
        case .page(let pageID):
            TabStripItem(id: id, title: model.tree.page(pageID)?.title ?? "", icon: model.tree.page(pageID)?.icon)
        }
    }
}

/// An attached file in a pane of its own (a PDF, natively): the file's name as the window title, "open in Preview".
extension NativeDetailToolbar {
    /// A mode button's state: on while the panel shows that mode; switching it on opens the panel there.
    fileprivate func inspectorBinding(_ mode: InspectorMode) -> Binding<Bool> {
        Binding(
            get: { navigator.isShowingInspector && navigator.inspectorMode == mode },
            set: { _ in navigator.toggleInspector(mode) })
    }

}

private struct DocumentPane: View {
    let name: String
    let label: String
    let editor: EditorController

    var body: some View {
        Group {
            if let url = editor.assetFile(named: name) {
                PDFViewer(url: url) {
                    #if os(macOS)
                        NSWorkspace.shared.open(url)
                    #else
                        editor.previewURL = url
                    #endif
                }
            } else {
                Text("app:pdf.missing")
                    .font(.hk(.md))
                    .foregroundStyle(Theme.mutedForeground)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(label)
    }
}
