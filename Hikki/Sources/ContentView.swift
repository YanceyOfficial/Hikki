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
    @State private var sidebarVisible = true
    @AppStorage("sidebarWidth") private var sidebarWidth = Double(Size.sidebarIdeal)
    @State private var chrome = ChromeMetrics()
    @SceneStorage("tabs") private var storedTabs: Data?
    @AppStorage(ColorTone.storageKey) private var tone = ColorTone.standard
    #if os(macOS)
        @Environment(\.openSettings) private var openSettings
    #endif

    var body: some View {
        @Bindable var navigator = navigator
        // EXPERIMENT (native chrome): the system split view, sidebar List and window toolbar everywhere.
        NavigationSplitView(columnVisibility: $columns) {
            SidebarView(navigator: navigator, customChrome: false, wide: customChrome)
                .navigationSplitViewColumnWidth(min: Size.sidebarMin, ideal: Size.sidebarIdeal, max: Size.sidebarMax)
        } detail: {
            DetailView(navigator: navigator, editor: editor, customChrome: false, phoneToolbar: !customChrome)
                .toolbar { if customChrome { NativeDetailToolbar(navigator: navigator) } }
        }
        #if os(iOS)
            .sheet(isPresented: $navigator.isShowingSettings) { SettingsView() }
        #endif
        .sheet(isPresented: $navigator.isSearching) {
            SearchPalette(navigator: navigator) { navigator.isSearching = false }
        }
        .animation(.snappy(duration: 0.18), value: navigator.isSearching)
        .task { await model.observe() }
        .onAppear {
            navigator.attach(model)
            navigator.restoreTabs(from: storedTabs)
            #if DEBUG
                // Screenshot/test hooks: HIKKI_OPEN_TABS=pageA,pageB opens those pages as tabs; HIKKI_OPEN_SEARCH opens ⌘K.
                if ProcessInfo.processInfo.environment["HIKKI_OPEN_SEARCH"] != nil { navigator.isSearching = true }
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
                        toggleSidebar()  // same path as the header button
                        try? await Task.sleep(for: .seconds(2))
                        toggleSidebar()
                    }
                }
                if let ids = ProcessInfo.processInfo.environment["HIKKI_OPEN_TABS"]?.split(separator: ",") {
                    for (index, id) in ids.enumerated() {
                        if index == 0 { navigator.open(String(id)) } else { navigator.openInNewTab(.page(String(id))) }
                    }
                }
            #endif
            if let initialPageID, model.tree.page(initialPageID) != nil { navigator.open(initialPageID) }
            editor.setTone(tone)
            editor.attach(store: model.store, assets: model.assets)
            editor.open(documentID: navigator.route.pageID)
        }
        .onChange(of: navigator.route) { _, route in editor.open(documentID: route.pageID) }
        .onChange(of: tone) { _, tone in editor.setTone(tone) }
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
    }

    // MARK: Mac / iPad

    /// Notion's frame: one header across the whole top (sidebar controls on the left, tabs from the sidebar's
    /// edge), the sidebar and the page below it. Collapsing the sidebar leaves the header's left controls in
    /// place next to the traffic lights; only the tabs slide over.
    private var desktopLayout: some View {
        VStack(spacing: Spacing.s0) {
            AppHeader(
                navigator: navigator, sidebarVisible: sidebarVisible, sidebarWidth: sidebarWidth,
                toggleSidebar: toggleSidebar)
            HStack(spacing: Spacing.s0) {
                if sidebarVisible {
                    SidebarView(navigator: navigator, customChrome: true, wide: true)
                        .frame(width: sidebarWidth)
                        .overlay(alignment: .trailing) { SidebarResizeHandle(width: $sidebarWidth) }
                        .transition(.move(edge: .leading))
                }
                DetailView(navigator: navigator, editor: editor, customChrome: true)
            }
        }
        .background(Theme.background)
        #if os(macOS)
            .ignoresSafeArea(.container, edges: .top)
        #endif
    }

    private func toggleSidebar() {
        withAnimation(.snappy(duration: 0.22)) { sidebarVisible.toggle() }
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

/// The detail column: the page bar (Mac/iPad) above the routed content.
private struct DetailView: View {
    let navigator: Navigator
    let editor: EditorController
    let customChrome: Bool
    var phoneToolbar = true

    var body: some View {
        VStack(spacing: Spacing.s0) {
            if customChrome {
                PageBar(route: navigator.route, navigator: navigator)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.background)
        #if os(iOS)
            .toolbar(customChrome ? .hidden : .automatic, for: .navigationBar)
        #endif
    }

    @ViewBuilder private var content: some View {
        switch navigator.route {
        case .page(let id):
            PageScreen(pageID: id, editor: editor, navigator: navigator, phoneToolbar: !customChrome && phoneToolbar)
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

    var body: some ToolbarContent {
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
                onForward: navigator.goForward
            )
            .frame(minWidth: 320, idealWidth: 560, maxWidth: 720)  // design-lint: allow (toolbar item width)
        }
        if let id = navigator.route.pageID, let page = model.tree.page(id) {
            ToolbarItemGroup(placement: .primaryAction) {
                FavoriteButton(page: page)
                PageMoreMenu(page: page, navigator: navigator)
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

/// The full-width header (Mac/iPad): the sidebar's controls over the sidebar, then back/forward, tabs and
/// "+" starting at the sidebar's edge. It doubles as the window's title bar (drag to move).
private struct AppHeader: View {
    @Environment(AppModel.self) private var model
    @Environment(\.chromeMetrics) private var metrics
    let navigator: Navigator
    let sidebarVisible: Bool
    let sidebarWidth: Double
    let toggleSidebar: () -> Void

    var body: some View {
        HStack(spacing: Spacing.s0) {
            sidebarControls
                .frame(width: sidebarVisible ? sidebarWidth : nil, alignment: .leading)
                .frame(maxHeight: .infinity)
                .background(sidebarVisible ? Theme.sidebar : .clear)
                .overlay(alignment: .trailing) {
                    if sidebarVisible { Theme.sidebarBorder.frame(width: 1) }
                }
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
            )
            // A line under the tabs only; the sidebar runs up into the header without one (Notion).
            .overlay(alignment: .bottom) { Theme.border.frame(height: 1) }
        }
        .frame(height: metrics.barHeight)
        .background(Theme.sidebar)
        #if os(macOS)
            .background(WindowDragArea())
        #endif
    }

    /// Traffic lights (macOS), the sidebar toggle and New page — the same spot whether or not the sidebar
    /// is open.
    private var sidebarControls: some View {
        HStack(spacing: Spacing.s1) {
            Color.clear.frame(width: max(0, metrics.leadingInset - Spacing.s2))  // traffic lights
            SidebarIconButton(
                sidebarVisible ? "app:chrome.hideSidebar" : "app:chrome.showSidebar", symbol: .sidebarSimple,
                action: toggleSidebar)
            if sidebarVisible { Spacer(minLength: 0) }
            SidebarIconButton("app:page.new", symbol: .notePencil) { navigator.newPage() }
                .accessibilityIdentifier("new-page")
        }
        .padding(.horizontal, Spacing.s2)
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

/// Drag the sidebar's edge to resize it (clamped to the token range).
private struct SidebarResizeHandle: View {
    @Binding var width: Double
    @State private var start: Double?

    var body: some View {
        Color.clear
            .frame(width: Spacing.s1_5)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let origin = start ?? width
                        start = origin
                        width = min(max(origin + value.translation.width, Size.sidebarMin), Size.sidebarMax)
                    }
                    .onEnded { _ in start = nil }
            )
            #if os(macOS)
                .onHover { inside in
                    if inside { NSCursor.columnResize.push() } else { NSCursor.pop() }
                }
            #endif
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
