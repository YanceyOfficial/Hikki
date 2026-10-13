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
            DetailView(navigator: navigator, editor: editor, phoneToolbar: !wide)
                .toolbar { if wide { NativeDetailToolbar(navigator: navigator, editor: editor) } }
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
            .onChange(of: spellcheck) { _, on in editor.setSpellcheck(on) }
            // Lock / unlock while the page is open (the load payload carries it otherwise).
            .onChange(of: navigator.currentPage?.isLocked) { _, locked in editor.setLocked(locked ?? false) }
            .onChange(of: navigator.titleFocusRequest) { _, request in
                if let request { editor.focusTitle(of: request.pageID) }
            }
            // hikki://page/<id> (Copy link).
            .onOpenURL { url in
                guard let id = PageLink.pageID(from: url), model.tree.page(id) != nil else { return }
                navigator.open(id)
                if let block = PageLink.blockID(from: url) { editor.scrollToBlock(block, in: id) }
            }
            // Menu bar extra: New Page / Search land in the key window (MenuBarExtra.swift).
            .menuBarRequests(navigator: navigator)
            .onChange(of: navigator.tabs) { _, _ in storedTabs = navigator.encodedTabs() }
            .onChange(of: model.tree) { _, tree in
                // Pages trashed here or in another window disappear from every tab's history.
                navigator.prune { tree.page($0) != nil }
                navigator.revealCurrent()
                editor.setPages(tree.all)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    model.reconcileWorkspace()  // pick up other devices' changes
                } else {
                    Task {
                        await editor.flush(reason: "scenePhase-\(phase)")
                        model.flushWorkspace()
                    }
                }
            }
    }

    /// First appearance: tabs, the editor's settings and store, DEBUG hooks, the first page.
    private func setUp() {
        navigator.attach(model)
        navigator.restoreTabs(from: storedTabs)
        #if DEBUG
            // Screenshot/test hooks: HIKKI_OPEN_TABS=pageA,pageB opens those pages as tabs; HIKKI_OPEN_SEARCH opens ⌘K.
            if ProcessInfo.processInfo.environment["HIKKI_OPEN_SEARCH"] != nil { navigator.isSearching = true }
            // HIKKI_OPEN_FIND opens find in page once the page is up (screenshots of its place under the toolbar).
            if ProcessInfo.processInfo.environment["HIKKI_OPEN_FIND"] != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { editor.find(.find) }
            }
            // HIKKI_ACTIVATE brings the window to the front (screenshots of the active-window look).
            #if os(macOS)
                if ProcessInfo.processInfo.environment["HIKKI_ACTIVATE"] != nil { NSApp.activate() }
            #endif
            // HIKKI_OPEN_SETTINGS opens Settings (screenshots).
            if ProcessInfo.processInfo.environment["HIKKI_OPEN_SETTINGS"] != nil {
                #if os(macOS)
                    openSettings()
                #else
                    navigator.isShowingSettings = true
                #endif
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
            #if os(macOS)
                .fullScreenScrim(Theme.background)
            #endif
    }

    @ViewBuilder private var content: some View {
        switch navigator.route {
        case .page(let id):
            PageScreen(pageID: id, editor: editor, navigator: navigator, phoneToolbar: phoneToolbar)
        case .trash:
            TrashView()
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
                showsHistory: false
            )
            .frame(minWidth: 240, idealWidth: 480, maxWidth: 640)  // design-lint: allow (toolbar item width)
        }
        if let id = navigator.route.pageID, let page = model.tree.page(id) {
            if page.isLocked {
                ToolbarItem(placement: .primaryAction) { LockIndicator(page: page, toolbar: true) }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                FavoriteButton(page: page, toolbar: true)
                PageMoreMenu(page: page, navigator: navigator, editor: editor, toolbar: true)
            }
        }
    }

    private func tabItem(_ id: UUID, _ route: Route) -> TabStripItem {
        switch route {
        case .home: TabStripItem(id: id, title: String(localized: "app:nav.home"), symbol: .house)
        case .trash: TabStripItem(id: id, title: String(localized: "app:nav.trash"), symbol: .trash)
        case .page(let pageID):
            TabStripItem(id: id, title: model.tree.page(pageID)?.title ?? "", icon: model.tree.page(pageID)?.icon)
        }
    }
}
