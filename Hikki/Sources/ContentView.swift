import HikkiCore
import HikkiUI
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
    @State private var chrome = ChromeMetrics()
    @SceneStorage("tabs") private var storedTabs: Data?

    var body: some View {
        @Bindable var navigator = navigator
        NavigationSplitView(columnVisibility: $columns) {
            SidebarView(navigator: navigator, customChrome: customChrome)
                .navigationSplitViewColumnWidth(
                    min: Size.sidebarMin, ideal: Size.sidebarIdeal, max: Size.sidebarMax
                )
        } detail: {
            DetailView(
                navigator: navigator, editor: editor, customChrome: customChrome,
                sidebarHidden: columns == .detailOnly,
                toggleSidebar: { withAnimation { columns = columns == .detailOnly ? .all : .detailOnly } })
        }
        #if os(macOS)
            .toolbar(removing: .sidebarToggle)
            // Our tab bar / sidebar header replace the window toolbar (see WindowChrome).
            .background(WindowChrome { chrome = $0 })
        #endif
        .sheet(isPresented: customChrome ? .constant(false) : $navigator.isSearching) {
            SearchPalette(navigator: navigator) { navigator.isSearching = false }
        }
        .overlay {
            if customChrome && navigator.isSearching {
                SearchOverlay(navigator: navigator)
            }
        }
        .animation(.snappy(duration: 0.18), value: navigator.isSearching)
        .task { await model.observe() }
        .onAppear {
            navigator.attach(model)
            navigator.restoreTabs(from: storedTabs)
            #if DEBUG
                // Screenshot/test hooks: HIKKI_OPEN_TABS=pageA,pageB opens those pages as tabs; HIKKI_OPEN_SEARCH opens ⌘K.
                if ProcessInfo.processInfo.environment["HIKKI_OPEN_SEARCH"] != nil { navigator.isSearching = true }
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
                        withAnimation { columns = .detailOnly }  // same path as the toolbar button
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation { columns = .all }
                    }
                }
                if let ids = ProcessInfo.processInfo.environment["HIKKI_OPEN_TABS"]?.split(separator: ",") {
                    for (index, id) in ids.enumerated() {
                        if index == 0 { navigator.open(String(id)) } else { navigator.openInNewTab(.page(String(id))) }
                    }
                }
            #endif
            if let initialPageID, model.tree.page(initialPageID) != nil { navigator.open(initialPageID) }
            editor.attach(store: model.store, assets: model.assets)
            editor.open(documentID: navigator.route.pageID)
        }
        .onChange(of: navigator.route) { _, route in editor.open(documentID: route.pageID) }
        .onChange(of: navigator.titleFocusRequest) { _, request in
            if let request { editor.focusTitle(of: request.pageID) }
        }
        // hikki://page/<id> (Copy link).
        .onOpenURL { url in
            if let id = PageLink.pageID(from: url), model.tree.page(id) != nil { navigator.open(id) }
        }
        .onChange(of: navigator.tabs) { _, _ in storedTabs = navigator.encodedTabs() }
        .onChange(of: model.tree) { _, tree in
            // Pages trashed here or in another window disappear from every tab's history.
            navigator.prune { tree.page($0) != nil }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { Task { await editor.flush(reason: "scenePhase-\(phase)") } }
        }
        .environment(\.chromeMetrics, chrome)
        .focusedSceneValue(\.editor, editor)
        .focusedSceneValue(\.navigator, navigator)
        .tint(Theme.primary)
    }

    /// Notion-style tab bar + page bar instead of the system toolbar (Mac and iPad); iPhone keeps the nav bar.
    private var customChrome: Bool {
        #if os(macOS)
            true
        #else
            sizeClass == .regular
        #endif
    }
}

/// The detail column: custom chrome (tabs + page bar) above the routed content.
private struct DetailView: View {
    @Environment(AppModel.self) private var model
    let navigator: Navigator
    let editor: EditorController
    let customChrome: Bool
    let sidebarHidden: Bool
    let toggleSidebar: () -> Void
    @Environment(\.chromeMetrics) private var chromeMetrics

    var body: some View {
        VStack(spacing: Spacing.s0) {
            if customChrome {
                tabBar
                PageBar(route: navigator.route, navigator: navigator)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.background)
        #if os(macOS)
            .ignoresSafeArea(.container, edges: .top)
        #else
            .toolbar(customChrome ? .hidden : .automatic, for: .navigationBar)
        #endif
    }

    @ViewBuilder private var content: some View {
        switch navigator.route {
        case .page(let id):
            PageScreen(pageID: id, editor: editor, navigator: navigator, phoneToolbar: !customChrome)
        case .trash:
            TrashView()
        case .home:
            HomeView(navigator: navigator)
        }
    }

    private var tabBar: some View {
        TabStrip(
            items: navigator.tabs.tabs.map { tab in tabItem(tab.id, tab.route) },
            activeID: navigator.tabs.activeID,
            canGoBack: navigator.tabs.active.canGoBack,
            canGoForward: navigator.tabs.active.canGoForward,
            onSelect: navigator.selectTab,
            onClose: { navigator.closeTab($0) },
            onNew: { navigator.openInNewTab(.home) },
            onBack: navigator.goBack,
            onForward: navigator.goForward
        ) {
            #if os(macOS)
                if sidebarHidden { Color.clear.frame(width: max(0, chromeMetrics.leadingInset - Spacing.s2)) }  // traffic lights
            #endif
            SidebarIconButton(
                sidebarHidden ? "app:chrome.showSidebar" : "app:chrome.hideSidebar", symbol: .sidebarSimple, action: toggleSidebar)
        }
        .background(Theme.sidebar)
        #if os(macOS)
            .background(WindowDragArea())
        #endif
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

#if os(macOS)
    /// Lets the custom tab bar move the window, like a real title bar.
    private struct WindowDragArea: View {
        var body: some View {
            Color.clear.contentShape(.rect).gesture(WindowDragGesture()).allowsWindowActivationEvents(true)
        }
    }
#endif
