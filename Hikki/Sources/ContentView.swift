import CoreSpotlight
import HikkiCore
import HikkiUI
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    /// A page to show on open (a window opened with "Open in new window").
    var initialPageID: String?
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    /// One editor (and one WKWebView) per window, reused across pages and tabs; the split pane's second one.
    @State private var editors = WindowEditors()
    private var editor: EditorController { editors.main }
    private var splitEditor: EditorController? { editors.split }
    /// Where each tab's page was scrolled when another tab took over (session only), and the tab the editor shows.
    @State private var tabScroll: [UUID: (docId: String, top: Double)] = [:]
    @State private var shownTab: UUID?
    /// AI on the selection, for both editors.
    @State private var ai = AIService()
    /// Ask AI's conversation (iPhone's bottom bar).
    @State private var chat = AIChat()
    @State private var navigator = Navigator()
    @State private var columns: NavigationSplitViewVisibility = .all
    @SceneStorage("tabs") private var storedTabs: Data?
    /// A finished export waiting for the save panel / exporter.
    @State private var exportFile: ExportFile?
    @State private var isExporting = false
    private let tone = ColorTone.standard
    @AppStorage(EditorPreferences.spellcheckKey) private var spellcheck = true
    @AppStorage(AIPreferences.reviewStyleKey) private var aiReviewStyle = "inline"
    #if os(macOS)
        @Environment(\.openSettings) private var openSettings
    #endif

    /// What both of the window's editors show the same way; each holds it and replays it when its page comes up.
    private var editorSettings: EditorSettings {
        EditorSettings(
            tone: tone, spellcheck: spellcheck, aiReviewStyle: aiReviewStyle, shortcuts: ShortcutStore.shared.overrides)
    }

    var body: some View {
        // Split in two so the type checker copes: the layout, then the scene's events.
        transfers(sceneEvents(layout))
            // Failures and confirmations (Toasts): at the bottom, above the iPhone's floating bar.
            .toastHost(bottomInset: wide ? Spacing.s4 : Size.floatingBar + Spacing.s8)
            .focusedSceneValue(\.editor, editor)
            .focusedSceneValue(\.navigator, navigator)
            .focusedSceneValue(\.lockedPage, navigator.currentPage?.isLocked)
    }

    #if os(iOS)
        /// ⌘K / the search button: full screen on iPhone, a sheet on iPad.
        private var phoneSearch: Binding<Bool> {
            Binding(
                get: { navigator.isSearching && UIDevice.current.userInterfaceIdiom == .phone },
                set: { if !$0 { navigator.isSearching = false } })
        }
        private var padSearch: Binding<Bool> {
            Binding(
                get: { navigator.isSearching && UIDevice.current.userInterfaceIdiom != .phone },
                set: { if !$0 { navigator.isSearching = false } })
        }
    #endif

    /// Opens Settings at a page (the Mac's Settings window, the sheet elsewhere).
    private func openSettingsPage(_ page: SettingsPage) {
        UserDefaults.standard.set(page.rawValue, forKey: SettingsPage.storageKey)
        #if os(macOS)
            openSettings()
        #else
            navigator.isShowingSettings = true
        #endif
    }

    /// The system split view and window toolbar (the sidebar is native rows, see SidebarView), sheets.
    private var layout: some View {
        @Bindable var navigator = navigator
        @Bindable var editor = editor
        return NavigationSplitView(columnVisibility: $columns, preferredCompactColumn: $navigator.compactColumn) {
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
                    InspectorPanel(navigator: navigator, editor: editor, chat: chat)
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
                InspectorView(navigator: navigator, editor: editor, chat: chat)
                    .presentationDetents([.medium, .large])
            }
        }
        #if os(iOS)
            .sheet(isPresented: $navigator.isShowingSettings) { SettingsView() }
            .sheet(isPresented: $navigator.isAskingAI) { AIChatSheet(chat: chat) }
            // Asked from a page: about that page; from the home screen: about nothing in particular.
            .onChange(of: navigator.isAskingAI) { _, asking in
                if asking { chat.show(page: navigator.compactColumn == .detail ? navigator.route.pageID : nil) }
                // A suggestion from Home: its pages as context, the question sent.
                if asking, let question = navigator.pendingAIQuestion {
                    navigator.pendingAIQuestion = nil
                    chat.extraPageIDs = question.pageIDs
                    chat.send(question.text, store: model.store)
                }
            }
            // iPhone: the page's ⋯ as a sheet.
            .sheet(
                isPresented: Binding(
                    get: { navigator.pageActionsID != nil }, set: { if !$0 { navigator.pageActionsID = nil } })
            ) {
                if let id = navigator.pageActionsID, let page = model.tree.page(id) {
                    PhonePageActions(page: page, navigator: navigator, editor: editor)
                }
            }
        #else
            .background(HideOnClose())
        #endif
        #if os(iOS)
            // iPhone: search takes the whole screen (a sheet's large corner and its keyboard avoidance hid the field);
            // a page-sized sheet on iPad.
            .fullScreenCover(isPresented: phoneSearch) {
                SearchPalette(navigator: navigator) { navigator.isSearching = false }
            }
            .sheet(isPresented: padSearch) {
                SearchPalette(navigator: navigator) { navigator.isSearching = false }
            }
        #else
            .sheet(isPresented: $navigator.isSearching) {
                SearchPalette(navigator: navigator) { navigator.isSearching = false }
            }
        #endif
        .animation(.snappy(duration: 0.18), value: navigator.isSearching)
        // Attachments opened from the editor.
        .quickLookPreview($editor.previewURL)
        // The passage selected in the page (the main editor's) rides along to Ask AI as context, as in Notion.
        // It keeps the page it was selected in: a question about another page goes without it.
        .onChange(of: editor.selection) { _, selection in chat.selection = selection }
        // "Open in Split View" wherever page actions are (sidebar, Home, ⋯): by the window's width, not a column's.
        .environment(\.splitAvailable, wide)
    }

    /// Page history, export and import (PageTransfer.swift): the history sheet, the save panel / exporter and the
    /// file picker.
    private func transfers(_ content: some View) -> some View {
        @Bindable var navigator = navigator
        return
            content
            .sheet(
                isPresented: Binding(
                    get: { navigator.historyPageID != nil },
                    set: { if !$0 { navigator.historyPageID = nil } })
            ) {
                if let id = navigator.historyPageID {
                    PageHistoryView(pageID: id) { version in
                        await model.restore(version, editors: [editor] + (splitEditor.map { [$0] } ?? []))
                    }
                    // Room for the list beside the preview on iPad.
                    .presentationSizing(.page)
                }
            }
            // An export is made first (the editor converts, attachments are packed), then offered to save.
            .task(id: navigator.exportRequest) {
                guard let request = navigator.exportRequest else { return }
                do {
                    let file = try await model.exportPackage(request, editor: editor)
                    Log.info("page exported", category: "export", context: ["docId": request.pageID, "format": request.format.rawValue])
                    #if DEBUG
                        // HIKKI_EXPORT_DIR=<folder>: written there without the save panel (UI tests).
                        if let folder = ProcessInfo.processInfo.environment["HIKKI_EXPORT_DIR"] {
                            let name = file.wrapper.preferredFilename ?? "export"
                            try file.wrapper.write(
                                to: URL(filePath: folder).appending(path: name), options: .atomic, originalContentsURL: nil)
                            navigator.exportRequest = nil
                            return
                        }
                    #endif
                    exportFile = file
                    isExporting = true
                } catch {
                    Toasts.report(.exportFailed, error, category: "export", context: ["docId": request.pageID])
                    navigator.exportRequest = nil
                }
            }
            .fileExporter(
                isPresented: $isExporting, document: exportFile, contentType: exportFile?.contentType ?? .data,
                defaultFilename: exportFile?.defaultFilename
            ) { result in
                if case .failure(let error) = result { Log.warn("export not saved: \(error)", category: "export") }
            }
            // Saved or cancelled: the export is done with.
            .onChange(of: isExporting) { _, presented in
                guard !presented else { return }
                navigator.exportRequest = nil
                exportFile = nil
            }
            .fileImporter(isPresented: $navigator.isImporting, allowedContentTypes: Self.importTypes, allowsMultipleSelection: true) {
                result in
                guard case .success(let urls) = result else { return }
                Task { await importFiles(urls) }
            }
            // Files dropped on the sidebar (SidebarFileDrop).
            .onChange(of: navigator.importDrop) { _, drop in
                guard let drop else { return }
                navigator.importDrop = nil
                Task { await importFiles(drop.urls, parentID: drop.parentID) }
            }
    }

    /// Markdown, HTML and plain text files, or a folder of them (with the pictures they link inside it).
    private static let importTypes: [UTType] = [UTType("net.daringfireball.markdown"), .html, .plainText, .folder].compactMap { $0 }

    /// Imported files become pages (under `parentID` when given); the last one opens.
    private func importFiles(_ urls: [URL], parentID: String? = nil) async {
        let ids = await model.importFiles(urls, parentId: parentID, editor: editor)
        if let last = ids.last { navigator.open(last) }
    }

    /// Setup, routing to the editor, settings, deep links, tab persistence, backgrounding.
    private func sceneEvents(_ content: some View) -> some View {
        content
            .onAppear(perform: setUp)
            // The window closed: its editors hand over what was typed in the last moments (nothing else keeps them
            // alive to save it later).
            .onDisappear {
                let editors = [editor] + (splitEditor.map { [$0] } ?? [])
                Task {
                    for editor in editors { await editor.flush(reason: "window-closed") }
                }
            }
            .onChange(of: navigator.route) { _, route in
                // Each tab keeps its place: the page leaving is remembered for its tab, and a tab shown again goes back
                // to where it was — another page opened inside a tab starts at its top.
                let tab = navigator.tabs.activeID
                if let shown = shownTab, let last = editor.lastScroll { tabScroll[shown] = last }
                let restore = tab != shownTab ? tabScroll[tab].flatMap { $0.docId == route.pageID ? $0.top : nil } : nil
                shownTab = tab
                editor.open(documentID: route.pageID, scrollTop: restore)
                navigator.revealCurrent()
            }
            .onChange(of: navigator.tabs.tabs.map(\.id)) { _, ids in
                tabScroll = tabScroll.filter { ids.contains($0.key) }
            }
            .onChange(of: wide) { editor.setSplitDrop(mainSplitDrop) }
            .onChange(of: navigator.isSplit) { editor.setSplitDrop(mainSplitDrop) }
            // Tone, spelling, the AI review style and Settings → Shortcuts' rebindings (the page handles the editor's
            // own keys): both editors, as they change.
            .onChange(of: editorSettings, initial: true) { _, settings in
                editor.apply(settings)
                splitEditor?.apply(settings)
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
                // Pages trashed here or in another window disappear from every tab's history. Each step changes
                // nothing (and so re-renders nothing) when nothing it shows changed — this runs on every save.
                navigator.prune { tree.page($0) != nil }
                navigator.pruneSplit { tree.page($0) != nil }
                navigator.revealCurrent()
                // Each editor: its link index when a title or icon changed, its page's lock when that changed.
                editor.setPages(tree)
                splitEditor?.setPages(tree)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    model.reconcileWorkspace()  // pick up other devices' changes
                    model.purgeTrash()
                    // Other devices may have commented meanwhile (their files synced in).
                    NotificationCenter.default.post(name: .pageCommentsChanged, object: nil)
                } else {
                    let editors = [editor] + (splitEditor.map { [$0] } ?? [])
                    SaveOnExit.flush(editors, model: model, reason: "scenePhase-\(phase)")
                }
            }
    }

    /// First appearance: tabs, the editor's store and callbacks, the last run's crash, DEBUG hooks, the first page.
    private func setUp() {
        navigator.attach(model)
        navigator.restoreTabs(from: storedTabs)
        // The editor's callbacks hold the navigator, the model and the editor weakly (each owns none of them): a
        // strong capture kept every closed window's editor and web process alive.
        let editor = editor
        editor.onOpenDocument = { [weak navigator] name, label in navigator?.openDocument(name: name, label: label) }
        // A page dropped on the page's right edge opens beside it (split view).
        editor.onOpenInSplit = { [weak navigator, weak model] id in
            navigator?.splitDropHover = false
            if model?.tree.page(id) != nil { navigator?.openInSplit(.page(id)) }
        }
        editor.onSplitDropHover = { [weak navigator] active in navigator?.splitDropHover = active }
        editor.setSplitDrop(mainSplitDrop)
        ai.attach(editor)
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
        announcePreviousCrash()
        #if DEBUG
            runDebugHooks()
        #endif
        if let initialPageID, model.tree.page(initialPageID) != nil { navigator.open(initialPageID) }
        editor.apply(editorSettings)
        editor.attach(store: model.store, assets: model.assets) { [weak model] in model?.history }
        editor.comments = { [weak model] in model?.comments }
        // Settings' bulk import / export converts Markdown and HTML with a window's editor.
        model.bulkTransfer.register(editor, model: model)
        editor.deviceName = AppModel.deviceKind
        editor.onOpenPage = { [weak navigator, weak model, weak editor] id, block in
            guard let navigator, model?.tree.page(id) != nil else { return }
            navigator.open(id)
            if let block { editor?.scrollToBlock(block, in: id) }
        }
        editor.setPages(model.tree)
        shownTab = navigator.tabs.activeID
        editor.open(documentID: navigator.route.pageID)
    }

    /// The run before crashed: say so once (in every build), with the way to the diagnostics to send.
    private func announcePreviousCrash() {
        guard model.crashReporter.pendingCrash() else { return }
        let incident = Incident.report(.crashedLastTime, category: "crash")
        Toasts.shared.show(
            .warning, incident.code.message, actionTitle: "app:toast.diagnostics",
            action: { openSettingsPage(.about) })
    }

    #if DEBUG
        /// Screenshot and test hooks, set in the environment.
        private func runDebugHooks() {
            let environment = ProcessInfo.processInfo.environment
            // HIKKI_OPEN_SEARCH opens ⌘K.
            if environment["HIKKI_OPEN_SEARCH"] != nil { navigator.isSearching = true }
            // HIKKI_OPEN_FIND opens find in page once the page is up (screenshots of its place under the toolbar).
            if environment["HIKKI_OPEN_FIND"] != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak editor] in editor?.find(.find) }
            }
            // HIKKI_ACTIVATE brings the window to the front (screenshots of the active-window look).
            #if os(macOS)
                if environment["HIKKI_ACTIVATE"] != nil { NSApp.activate() }
            #endif
            // HIKKI_DEBUG_TOAST shows a reported failure and a confirmation (screenshots, UI tests).
            if environment["HIKKI_DEBUG_TOAST"] != nil {
                Toasts.report(.pageSaveFailed, CocoaError(.fileWriteNoPermission), category: "debug")
                Toasts.shared.show(.success, String(localized: "app:toast.close"))
            }
            // HIKKI_OPEN_SETTINGS opens Settings (screenshots); a page name (`SettingsPage`) as its value opens that page.
            if let value = environment["HIKKI_OPEN_SETTINGS"] {
                if SettingsPage(rawValue: value) != nil { UserDefaults.standard.set(value, forKey: SettingsPage.storageKey) }
                #if os(macOS)
                    openSettings()
                #else
                    navigator.isShowingSettings = true
                #endif
            }
            // HIKKI_DEBUG_SPOTLIGHT_QUERY=<text> asks Spotlight for pages once indexing settled and logs the ids it
            // ranks (judging its semantic matching).
            if let text = environment["HIKKI_DEBUG_SPOTLIGHT_QUERY"] {
                Task {
                    try? await Task.sleep(for: .seconds(8))
                    await model.searchIndexer.debugSpotlightQuery(text)
                }
            }
            // HIKKI_OPEN_SPLIT=<page id> | file:<asset name> | picker opens the split pane on it (screenshots).
            if let value = environment["HIKKI_OPEN_SPLIT"] {
                if value == "picker" {
                    navigator.showSplitPicker()
                } else if value.hasPrefix("file:") {
                    let name = String(value.dropFirst(5))
                    navigator.openInSplit(.file(name: name, label: name))
                } else {
                    navigator.openInSplit(.page(value))
                }
            }
            // HIKKI_IMPORT_FILE=<path> imports that file once the editor is up (UI tests: the file picker runs out of
            // process).
            if let path = environment["HIKKI_IMPORT_FILE"] {
                Task {
                    for _ in 0..<100 where !editor.isReady { try? await Task.sleep(for: .milliseconds(100)) }
                    await importFiles([URL(filePath: path)])
                }
            }
            // HIKKI_OPEN_FILE=<asset name> opens that attachment in the viewer pane (screenshots of the PDF viewer).
            if let name = environment["HIKKI_OPEN_FILE"] {
                navigator.openDocument(name: name, label: name)
            }
            // HIKKI_DEBUG_NAV=a,b,c visits those pages one per second (reproduces page-switch bugs).
            if let ids = environment["HIKKI_DEBUG_NAV"]?.split(separator: ",") {
                Task {
                    for id in ids {
                        try? await Task.sleep(for: .seconds(1))
                        navigator.open(String(id))
                    }
                }
            }
            // HIKKI_DEBUG_SIDEBAR: hides the sidebar after 2s and shows it again after 4s (title-bar layout bugs).
            if environment["HIKKI_DEBUG_SIDEBAR"] != nil {
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
            // HIKKI_OPEN_TABS=pageA,pageB opens those pages as tabs; "home" opens Home (screenshots of it on iPhone,
            // where the root is the sidebar).
            if let ids = environment["HIKKI_OPEN_TABS"]?.split(separator: ",") {
                for (index, id) in ids.enumerated() {
                    let route: Route = id == "home" ? .home : .page(String(id))
                    if index == 0 { navigator.go(route) } else { navigator.openInNewTab(route) }
                }
            }
            // HIKKI_OPEN_AI opens Ask AI, HIKKI_OPEN_PAGE_ACTIONS the open page's ⋯ sheet (iPhone screenshots).
            if environment["HIKKI_OPEN_AI"] != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak navigator] in navigator?.isAskingAI = true }
            }
            if environment["HIKKI_OPEN_PAGE_ACTIONS"] != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak navigator] in
                    navigator?.pageActionsID = navigator?.route.pageID
                }
            }
        }
    #endif

    /// The split pane's editor, made and wired on first use: same store, assets, pages and settings as the main one; a
    /// link clicked in it opens in the pane, a PDF attachment in a tab.
    private func splitPaneEditor() -> EditorController {
        if let splitEditor { return splitEditor }
        let pane = EditorController()
        pane.apply(editorSettings)
        pane.setAutoFocus(false)
        pane.comments = { [weak model] in model?.comments }
        pane.deviceName = AppModel.deviceKind
        pane.attach(store: model.store, assets: model.assets) { [weak model] in model?.history }
        pane.onOpenPage = { [weak navigator, weak model, weak pane] id, block in
            guard let navigator, model?.tree.page(id) != nil else { return }
            navigator.openInSplit(.page(id))
            if let block { pane?.scrollToBlock(block, in: id) }
        }
        pane.onOpenDocument = { [weak navigator] name, label in navigator?.openInSplit(.file(name: name, label: label)) }
        // Dropped on the pane's own right edge: it shows that page instead.
        pane.onOpenInSplit = { [weak navigator, weak model] id in
            if model?.tree.page(id) != nil { navigator?.openInSplit(.page(id)) }
        }
        pane.setSplitDrop(.here)
        ai.attach(pane)
        pane.setPages(model.tree)
        editors.split = pane
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
        // The side panel's views at the trailing end, as in Xcode: the outline and comments in one glass group (the
        // one showing carries the selected pill), then AI in a glass circle of its own. Only where there is a page;
        // off while split (the panel belongs to the left page). Split view itself opens by drag, ⌘\ or "Open in
        // Split View".
        if navigator.route.pageID != nil {
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle(isOn: inspectorBinding(.outline)) {
                    IconLabel("app:inspector.outline", icon: .listBullets)
                }
                .toggleStyle(.button)
                .help("app:inspector.outline")
                .disabled(navigator.isSplit)
                .accessibilityIdentifier("inspector-toggle")
                Toggle(isOn: inspectorBinding(.comments)) {
                    IconLabel("app:inspector.comments", icon: .chatTeardropText)
                }
                .toggleStyle(.button)
                .help("app:inspector.comments")
                .disabled(navigator.isSplit)
                .accessibilityIdentifier("comments-toggle")
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
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

/// A window's editors, each made once: the main one on first use, the split pane's when a page first opens there.
/// (`@State var editor = EditorController()` built a web view on every init of ContentView, which RootView re-inits
/// whenever the workspace or the appearance changes.)
@Observable
final class WindowEditors {
    @ObservationIgnored private(set) lazy var main = EditorController()
    var split: EditorController?
}
