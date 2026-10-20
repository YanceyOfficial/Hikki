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
    #if os(iOS)
        /// The system's vertical bar (an iPhone Duo), if any: page sheets hide it while open.
        @Environment(\.verticalBarEdge) private var verticalBar
    #endif
    /// The window's width, kept current as it resizes (an iPhone Duo folding or unfolding, Stage Manager): split view
    /// follows it.
    @State private var windowWidth: CGFloat = 0
    private var editor: EditorController { editors.main }
    private var splitEditor: EditorController? { editors.split }
    /// Where each tab's page was scrolled when another tab took over (session only).
    @State private var tabScroll: [UUID: (docId: String, top: Double)] = [:]
    /// AI on the selection, for both editors.
    @State private var ai = AIService()
    /// The chat with AI about the leading side's page (the panel beside it; iPhone's Ask AI sheet).
    @State private var chat = AIChat()
    /// The trailing side's own, about its page (split view).
    @State private var trailingChat = AIChat()
    @State private var navigator = Navigator()
    @State private var columns: NavigationSplitViewVisibility = .all
    @SceneStorage("tabs") private var storedTabs: Data?
    /// A finished export waiting for the save panel / exporter.
    @State private var exportFile: ExportFile?
    @State private var isExporting = false
    private let tone = ColorTone.standard
    @AppStorage(EditorPreferences.spellcheckKey) private var spellcheck = true
    @AppStorage(AIPreferences.reviewStyleKey) private var aiReviewStyle = "inline"
    /// What both of the window's editors show the same way; each holds it and replays it when its page comes up.
    private var editorSettings: EditorSettings {
        EditorSettings(
            tone: tone, spellcheck: spellcheck,
            aiReviewStyle: ReviewStyleThumbnail.Sketch(stored: aiReviewStyle).rawValue, shortcuts: ShortcutStore.shared.overrides)
    }

    var body: some View {
        // Split in two so the type checker copes: the layout, then the scene's events.
        transfers(sceneEvents(layout))
            // Failures and confirmations (Toasts): at the bottom, above the iPhone's floating bar.
            .toastHost(bottomInset: wide ? Spacing.s4 : Size.floatingBar + Spacing.s8)
            // The menus act on the side being worked in (split view).
            .focusedSceneValue(\.editor, editor(for: navigator.focusedSide))
            .focusedSceneValue(\.navigator, navigator)
            .focusedSceneValue(\.aiChat, chat(for: navigator.focusedSide))
            .focusedSceneValue(\.lockedPage, navigator.currentPage?.isLocked)
    }

    #if os(iOS)
        /// ⌘K / the search button: full screen in a compact window (a phone, a folded iPhone Duo), a sheet otherwise.
        private var phoneSearch: Binding<Bool> {
            Binding(
                get: { navigator.isSearching && sizeClass == .compact },
                set: { if !$0 { navigator.isSearching = false } })
        }
        private var padSearch: Binding<Bool> {
            Binding(
                get: { navigator.isSearching && sizeClass != .compact },
                set: { if !$0 { navigator.isSearching = false } })
        }
    #endif

    /// Opens Settings at a page.
    private func openSettingsPage(_ page: SettingsPage) {
        UserDefaults.standard.set(page.rawValue, forKey: SettingsPage.storageKey)
        navigator.isShowingSettings = true
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
            // Each side of the window is a `PaneColumn`: its content, and — split — its bar; then its panel beside it.
            SplitDetail(navigator: navigator) {
                PaneColumn(side: .leading, navigator: navigator, editor: editor, wide: wide) {
                    DetailView(
                        navigator: navigator, side: .leading, route: navigator.leadingPane.route, editor: editor,
                        phoneToolbar: !wide)
                } panel: { cap in
                    InspectorPanel(navigator: navigator, side: .leading, editor: editor, chat: chat, cap: cap)
                }
            } trailing: {
                PaneColumn(side: .trailing, navigator: navigator, editor: splitEditor, wide: wide) {
                    if let pane = navigator.trailingPane {
                        DetailView(
                            navigator: navigator, side: .trailing, route: pane.route, editor: splitEditor,
                            phoneToolbar: false)
                    }
                } panel: { cap in
                    if let splitEditor {
                        InspectorPanel(navigator: navigator, side: .trailing, editor: splitEditor, chat: trailingChat, cap: cap)
                    }
                }
            }
            .animation(Motion.easeOut(), value: navigator.isSplit)
            .background(Theme.background)
            #if os(macOS)
                // Photos' way: with the inspector open the page title and subtitle leave the toolbar, so the tabs keep
                // their width. Split, each side's bar names its page.
                .toolbar(removing: navigator.isSplit || leadingPanelOpen ? .title : nil)
            #endif
            .toolbar { if wide { NativeDetailToolbar(navigator: navigator, editor: editor) } }
            #if os(iOS)
                // A bottom sheet of the page's is open on an iPhone Duo: its vertical bar steps aside (it sits over the
                // sheet's side otherwise), back when the sheet closes. Elsewhere the bars stay.
                .toolbarVisibility(
                    sheetOpen && DeviceRules.sheetHidesBars(hasVerticalBar: verticalBar != nil) ? .hidden : .automatic,
                    for: .navigationBar
                )
                .animation(Motion.easeOut(), value: sheetOpen)
            #endif
            .sheet(
                isPresented: Binding(
                    get: { !wide && navigator.isShowingInspector && navigator.route.pageID != nil },
                    set: { navigator.isShowingInspector = $0 })
            ) {
                InspectorView(navigator: navigator, editor: editor, chat: chat, isSheet: true)
                    .presentationDetents([.medium, .large])
                    .sheetOverVerticalBar()
            }
        }
        #if os(iOS)
            // Settings: the dialog in a page-sized sheet where the window is wide (iPad), the hub list on iPhone.
            .sheet(isPresented: $navigator.isShowingSettings) {
                SettingsView(hub: !wide)
                .presentationSizing(.page)
                .sheetOverVerticalBar()
            }
            .sheet(isPresented: $navigator.isAskingAI) { AIChatSheet(chat: chat).sheetOverVerticalBar() }
            // Asked from a page: about that page; from the home screen: about nothing in particular. A handoff: about
            // the page it came from.
            .onChange(of: navigator.isAskingAI) { _, asking in
                if asking, let handoff = navigator.aiHandoff {
                    sendAIHandoff(handoff)
                    return
                }
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
                    PhonePageActions(page: page, navigator: navigator, editor: editor).sheetOverVerticalBar()
                }
            }
        #else
            .background(HideOnClose())
            // Settings (⌘,): Notion's dialog over the window, its pages in a sidebar.
            .sheet(isPresented: $navigator.isShowingSettings) { SettingsView() }
        #endif
        // AI on the selection handed a request to the chat: it comes up where it belongs and the request is sent.
        .onChange(of: navigator.aiHandoff) { _, handoff in
            if let handoff { routeAIHandoff(handoff) }
        }
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
        // An attached PDF clicked in the page: the viewer over it, the page staying in its tab.
        #if os(iOS)
            .fullScreenCover(item: $navigator.documentSheet) { request in
                DocumentSheet(request: request, editor: editor, navigator: navigator)
            }
        #else
            .sheet(item: $navigator.documentSheet) { request in
                DocumentSheet(request: request, editor: editor, navigator: navigator)
                .frame(minWidth: Size.pdfSheetWidth, minHeight: Size.pdfSheetHeight)
                .presentationSizing(.page)
            }
        #endif
        // The passage selected in a side's page rides along to that side's chat as context, as in Notion. It keeps the
        // page it was selected in: a question about another page goes without it.
        .onChange(of: editor.selection) { _, selection in chat.selection = selection }
        .onChange(of: splitEditor?.selection) { _, selection in trailingChat.selection = selection }
        // "Open in Split View" wherever page actions are (sidebar, Home, ⋯): by the window's width, not a column's,
        // and only where it has room for two pages (`DeviceRules.allowsSplit`).
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            windowWidth = $0
        }
        .environment(\.splitAvailable, splitAllowed)
        .onAppear { navigator.splitAllowed = splitAllowed }
        .onChange(of: splitAllowed) { _, allowed in navigator.splitAllowed = allowed }
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
                    .sheetOverVerticalBar()
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
                let parentID = navigator.importParentID
                Task { await importFiles(urls, parentID: parentID) }
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
            // What each side shows: its editor loads it. Focus moving between the sides changes neither.
            .onChange(of: PaneRoutes(leading: navigator.leadingPane, trailing: navigator.trailingPane)) { old, new in
                // Each tab keeps its place: the pages leaving are remembered for their tabs (both first, as two sides
                // swapping each take the other's), and a tab shown again goes back to where it was — another page
                // opened inside a tab starts at its top.
                remember(old.leading, in: editor)
                if let pane = old.trailing, let splitEditor { remember(pane, in: splitEditor) }
                if new.leading != old.leading { show(new.leading, after: old.leading, in: editor) }
                if let pane = new.trailing, pane != old.trailing { show(pane, after: old.trailing, in: splitPaneEditor()) }
            }
            .onChange(of: navigator.route) { navigator.revealCurrent() }
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
            // A side's own outline rail steps aside while its panel shows the outline; the mode picked last is
            // remembered.
            .onChange(of: navigator.inspector(.leading)) { _, state in
                UserDefaults.standard.set(state.mode.rawValue, forKey: InspectorPreferences.tabKey)
                editor.setOutlineRail(!(state.isShowing && state.mode == .outline))
            }
            .onChange(of: navigator.inspector(.trailing)) { _, state in
                UserDefaults.standard.set(state.mode.rawValue, forKey: InspectorPreferences.tabKey)
                splitEditor?.setOutlineRail(!(state.isShowing && state.mode == .outline))
            }
            // Rename and search results open in the focused side: its editor takes them.
            .onChange(of: navigator.titleFocusRequest) { _, request in
                if let request { editor(for: navigator.focusedSide)?.focusTitle(of: request.pageID) }
            }
            .onChange(of: navigator.textRevealRequest) { _, request in
                if let request {
                    editor(for: navigator.focusedSide)?.revealText(request.terms, at: request.blockID, in: request.pageID)
                }
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
                if let block = PageLink.blockID(from: url) { editor(for: navigator.focusedSide)?.scrollToBlock(block, in: id) }
            }
            // Menu bar extra: New Page / Search land in the key window (MenuBarExtra.swift).
            .menuBarRequests(navigator: navigator)
            // Full screen (macOS): menu bar, traffic lights and toolbar stay, as in a window (FullScreenChrome.swift).
            .fullScreenChrome()
            .onChange(of: navigator.tabs) { _, _ in storedTabs = navigator.encodedTabs() }
            // Tabs restored from the last run may name pages this workspace doesn't have (an empty one never changes
            // its tree, so the prune below doesn't run for it).
            .onChange(of: model.treeLoaded) { _, loaded in if loaded { navigator.prune { model.tree.page($0) != nil } } }
            .onChange(of: model.tree) { _, tree in
                // Pages trashed here or in another window disappear from every tab's history. Each step changes
                // nothing (and so re-renders nothing) when nothing it shows changed — this runs on every save.
                navigator.prune { tree.page($0) != nil }
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
        #if DEBUG
            // UI tests: the window's saved tabs outlive a run (scene storage), so each test starts on fresh ones.
            let restore = ProcessInfo.processInfo.environment["HIKKI_FRESH_TABS"] == nil
        #else
            let restore = true
        #endif
        if restore { navigator.restoreTabs(from: storedTabs) }
        if model.treeLoaded { navigator.prune { model.tree.page($0) != nil } }
        // The editor's callbacks hold the navigator, the model and the editor weakly (each owns none of them): a
        // strong capture kept every closed window's editor and web process alive.
        let editor = editor
        editor.onOpenDocument = { [weak navigator] name, label in navigator?.showDocument(name: name, label: label) }
        // A page dropped on the page's right edge opens beside it (split view; split already, in the trailing side).
        editor.onOpenInSplit = { [weak navigator, weak model] id in
            navigator?.splitDropHover = false
            if model?.tree.page(id) != nil { navigator?.openBeside(.page(id)) }
        }
        editor.onSplitDropHover = { [weak navigator] active in navigator?.splitDropHover = active }
        editor.setSplitDrop(mainSplitDrop)
        ai.attach(editor)
        editor.onAIHandoff = { [weak navigator] handoff in navigator?.aiHandoff = PaneHandoff(handoff: handoff, side: .leading) }
        // Ask AI's changes to the page are reviewed in the main editor; its verdicts go back to the chat's cards.
        chat.editor = editor
        editor.onAIChange = { [weak chat] docId, id, status, before, after in
            chat?.changeReviewed(docId: docId, id: id, status: status, before: before, after: after)
        }
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
        // A link in the leading page opens there (split or not).
        editor.onOpenPage = { [weak navigator, weak model, weak editor] id, block in
            guard let navigator, model?.tree.page(id) != nil else { return }
            navigator.focus(.leading)
            navigator.open(id)
            if let block { editor?.scrollToBlock(block, in: id) }
        }
        editor.setPages(model.tree)
        editor.open(documentID: navigator.leadingPane.route.pageID)
        // A window restored split: the trailing side's editor too.
        if let pane = navigator.trailingPane { splitPaneEditor().open(documentID: pane.route.pageID) }
    }

    /// The window's editor for a side (the trailing one exists once a page has shown there).
    private func editor(for side: PaneSide) -> EditorController? {
        side == .leading ? editor : splitEditor
    }

    /// The chat with AI about a side's page.
    private func chat(for side: PaneSide) -> AIChat {
        side == .leading ? chat : trailingChat
    }

    /// The leading side's panel is beside its page (the window's title steps aside).
    private var leadingPanelOpen: Bool {
        navigator.inspector(.leading).isShowing && navigator.leadingPane.route.pageID != nil
    }

    /// Where `pane`'s page was scrolled, kept for its tab — if the editor still shows that page.
    private func remember(_ pane: Pane, in editor: EditorController) {
        if let last = editor.lastScroll, last.docId == pane.route.pageID { tabScroll[pane.tab] = last }
    }

    /// `pane`'s page in a side's editor: back where it was when its tab is shown again, at its top when it is a new
    /// page in the same tab.
    private func show(_ pane: Pane, after old: Pane?, in editor: EditorController) {
        let restore = pane.tab != old?.tab ? tabScroll[pane.tab].flatMap { $0.docId == pane.route.pageID ? $0.top : nil } : nil
        editor.open(documentID: pane.route.pageID, scrollTop: restore)
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
            // HIKKI_DEBUG_COVER_SHEET opens the open page's cover sheet once it is up (screenshots of the touch sheets).
            if environment["HIKKI_DEBUG_COVER_SHEET"] != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak editor] in editor?.editCover() }
            }
            // HIKKI_DEBUG_AI_ASK=<question> asks the AI panel about the open page, and HIKKI_DEBUG_AI_EDIT=<words> selects
            // those words in it and runs "Improve writing" (screenshots of AI at work; they need a provider key).
            if let question = environment["HIKKI_DEBUG_AI_ASK"] {
                DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak chat, weak model, weak navigator] in
                    chat?.show(page: navigator?.route.pageID)
                    chat?.send(question, store: model?.store)
                }
            }
            if let words = environment["HIKKI_DEBUG_AI_EDIT"] {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak editor] in editor?.debugImprove(words) }
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
                navigator.isShowingSettings = true
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
            // HIKKI_SHOW_FILE=<asset name> shows it the way a click in a page does: the viewer over the page (UI tests).
            if let name = environment["HIKKI_SHOW_FILE"] {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak navigator] in
                    navigator?.showDocument(name: name, label: name)
                }
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

    /// Opens the chat for a handoff: the panel in AI mode beside the page it came from (Mac, a wide iPad — in a split
    /// window, that side's), or the Ask AI sheet (iPhone); then sends it.
    private func routeAIHandoff(_ handoff: PaneHandoff) {
        switch AIHandoff.placement(wide: wide) {
        case .inspector:
            navigator.setInspector(handoff.side, InspectorState(isShowing: true, mode: .ai))
            sendAIHandoff(handoff)
        case .sheet:
            // An open sheet takes it at once; else when it comes up (`isAskingAI`'s change).
            if navigator.isAskingAI { sendAIHandoff(handoff) } else { navigator.isAskingAI = true }
        }
    }

    /// The chat about the handoff's page, its passage as the selected context, the user's words as the next question
    /// (an answer still streaming there stops: the user just asked for something new).
    private func sendAIHandoff(_ request: PaneHandoff) {
        navigator.aiHandoff = nil
        let handoff = request.handoff
        let chat = chat(for: request.side)
        chat.show(page: handoff.docId)
        chat.mention(handoff.docId)
        if chat.isStreaming { chat.stop() }
        chat.selection = EditorSelection(docId: handoff.docId, text: handoff.selection)
        chat.send(handoff.instruction, store: model.store)
    }

    /// The trailing side's editor, made and wired on first use: same store, assets, pages and settings as the leading
    /// one; a link clicked in it opens in its side, a PDF attachment over the window, as on the leading side.
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
            navigator.show(.page(id), in: .trailing)
            if let block { pane?.scrollToBlock(block, in: id) }
        }
        pane.onOpenDocument = { [weak navigator] name, label in navigator?.showDocument(name: name, label: label) }
        // Dropped on the side's own right edge: it shows that page instead.
        pane.onOpenInSplit = { [weak navigator, weak model] id in
            if model?.tree.page(id) != nil { navigator?.show(.page(id), in: .trailing) }
        }
        pane.setSplitDrop(.here)
        ai.attach(pane)
        pane.onAIHandoff = { [weak navigator] handoff in navigator?.aiHandoff = PaneHandoff(handoff: handoff, side: .trailing) }
        // Its own chat: Ask AI's changes to its page are reviewed in it.
        trailingChat.editor = pane
        pane.onAIChange = { [weak trailingChat] docId, id, status, before, after in
            trailingChat?.changeReviewed(docId: docId, id: id, status: status, before: before, after: after)
        }
        pane.setPages(model.tree)
        editors.split = pane
        return pane
    }

    /// What a page dropped on the left page's right edge does: opens beside it, or replaces the right side.
    private var mainSplitDrop: EditorController.SplitDropMode {
        splitAllowed ? (navigator.isSplit ? .replace : .open) : .off
    }

    /// One of the window's editors shows a bottom sheet (`EditorController.sheetOpen`).
    private var sheetOpen: Bool { editor.sheetOpen || splitEditor?.sheetOpen == true }

    /// Whether this window may split into two panes: wide enough for two pages (`DeviceRules.allowsSplit`).
    private var splitAllowed: Bool {
        #if os(macOS)
            true
        #else
            wide && DeviceRules.allowsSplit(windowWidth: windowWidth)
        #endif
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

/// What a side of the window shows.
private struct DetailView: View {
    let navigator: Navigator
    let side: PaneSide
    let route: Route
    /// The side's editor (the trailing side has none until a page first shows there).
    let editor: EditorController?
    /// iPhone: the page's actions live in its navigation bar.
    var phoneToolbar = true

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
    }

    @ViewBuilder private var content: some View {
        switch route {
        case .page(let id):
            if let editor { PageScreen(pageID: id, editor: editor, navigator: navigator, phoneToolbar: phoneToolbar) }
        case .trash:
            TrashView()
        case .file(let name, let label):
            if let editor { DocumentPane(name: name, label: label, editor: editor) }
        case .home:
            HomeView(navigator: navigator)
        case .splitPicker:
            SplitPicker(navigator: navigator, side: side)
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
    #if os(macOS)
        @Environment(\.openWindow) private var openWindow
    #endif

    /// The (unsplit) page's panel is open beside it.
    private var inspectorOpen: Bool { !navigator.isSplit && navigator.isShowingInspector && navigator.route.pageID != nil }

    // Photos' toolbar: each group is its own Liquid Glass capsule — back/forward, the tabs, the page's
    // actions. (Search lives in the sidebar's glass field.)
    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            // One control with a divider between the two (‹ | ›), as in Finder/Safari.
            ControlGroup {
                Button(action: navigator.goBack) { IconLabel("app:chrome.back", icon: .caretLeft) }
                    .disabled(!navigator.tabs.canGoBack)
                Button(action: navigator.goForward) { IconLabel("app:chrome.forward", icon: .caretRight) }
                    .disabled(!navigator.tabs.canGoForward)
            }
            #if os(macOS)
                .controlGroupStyle(.navigation)
            #endif
        }
        ToolbarItem(placement: .principal) {
            TabStrip(
                // The two tabs of a split are one joined item; its focused half is the active one.
                items: navigator.tabs.tabs.map { tab in tabItem(tab.id, tab.route) },
                activeID: navigator.tabs.activeID,
                canGoBack: navigator.tabs.canGoBack,
                canGoForward: navigator.tabs.canGoForward,
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
                },
                menu: TabStripMenu(commands: tabMenuCommands, perform: performTabCommand)
            )
            .frame(minWidth: 240, idealWidth: 480, maxWidth: 640)  // design-lint: allow (toolbar item width)
            // Its own glass (the toolbar's shared capsule is hidden below), so the capsule moves with it.
            .glassEffect(.regular, in: .capsule)
            #if os(macOS)
                // The Mac toolbar centres it over the whole detail column; with the inspector open that is page +
                // panel, so it moves left by half the panel to sit over the page. iPad's toolbar already lays it out
                // between back/forward and the page's buttons, and the shift slid it under back/forward.
                .offset(x: inspectorOpen ? -CGFloat(inspectorWidth) / 2 : 0)
                .animation(Motion.easeOut(), value: inspectorOpen)
            #endif
        }
        .sharedBackgroundVisibility(.hidden)
        // Split, each side's bar has its page's tools (`PaneBar`); the toolbar keeps navigation and the tabs.
        if !navigator.isSplit, let id = navigator.route.pageID, let page = model.tree.page(id) {
            if page.isLocked {
                ToolbarItem(placement: .primaryAction) {
                    LockIndicator(page: page, toolbar: true)
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                FavoriteButton(page: page, toolbar: true)
                PageMoreMenu(page: page, navigator: navigator, editor: editor, toolbar: true)
            }
        }
        // The side panel's views at the trailing end, as in Xcode: the outline and comments in one glass group (the
        // one showing carries the selected pill), then AI in a glass circle of its own. Only where there is a page.
        // Split view itself opens by drag, ⌘\ or "Open in Split View".
        if !navigator.isSplit, navigator.route.pageID != nil {
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle(isOn: inspectorBinding(.outline)) {
                    IconLabel("app:inspector.outline", icon: .listBullets)
                }
                .toggleStyle(.button)
                .help("app:inspector.outline")
                .accessibilityIdentifier("inspector-toggle")
                Toggle(isOn: inspectorBinding(.comments)) {
                    IconLabel("app:inspector.comments", icon: .chatTeardropText)
                }
                .toggleStyle(.button)
                .help("app:inspector.comments")
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
                .accessibilityIdentifier("ai-toggle")
            }
        }
    }

    /// Chrome's tab menu: new / split / duplicate / move, then the closes. Split only where the window may split and
    /// the tab shows a page or a file; a new window only on the Mac, for a page (the "page" window group opens on one).
    private func tabMenuCommands(_ id: UUID) -> [[TabStripCommand]] {
        let route = navigator.route(ofTab: id)
        var first: [TabStripCommand] = [.newToRight]
        if navigator.tabs.split(of: id) != nil {
            first += [.swapSides, .separate]
        } else if navigator.splitAllowed, route?.canSplit == true {
            first.append(.openInSplit)
        }
        first.append(.duplicate)
        #if os(macOS)
            if route?.pageID != nil { first.append(.moveToNewWindow) }
        #endif
        return [first, [.close, .closeOthers, .closeToRight]]
    }

    private func performTabCommand(_ command: TabStripCommand, _ id: UUID) {
        switch command {
        case .newToRight: navigator.newTab(rightOf: id)
        case .openInSplit: navigator.openTabInSplit(id)
        case .swapSides: withAnimation(Motion.easeOut()) { navigator.swapTab(id) }
        case .separate: navigator.separateTab(id)
        case .duplicate: navigator.duplicateTab(id)
        case .moveToNewWindow:
            #if os(macOS)
                guard let pageID = navigator.route(ofTab: id)?.pageID else { return }
                openWindow(id: "page", value: pageID)
                navigator.closeTab(id)
            #endif
        case .close: navigator.closeTab(id)
        case .closeOthers: navigator.closeOtherTabs(id)
        case .closeToRight: navigator.closeTabs(rightOf: id)
        }
    }

    private func tabItem(_ id: UUID, _ route: Route) -> TabStripItem {
        var item =
            switch route {
            case .home: TabStripItem(id: id, title: String(localized: "app:nav.home"), symbol: .house)
            case .trash: TabStripItem(id: id, title: String(localized: "app:nav.trash"), symbol: .trash)
            case .file(_, let label): TabStripItem(id: id, title: label, symbol: .fileText)
            case .splitPicker: TabStripItem(id: id, title: String(localized: "app:split.pickTitle"), symbol: .squareSplitHorizontal)
            case .page(let pageID):
                TabStripItem(id: id, title: model.tree.page(pageID)?.title ?? "", icon: model.tree.page(pageID)?.icon)
            }
        item.joinedToNext = navigator.tabs.split(of: id)?.leading == id
        return item
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

/// An attached PDF over the page (a large sheet on the Mac, a full-screen cover on iOS): the viewer with its own
/// controls under a bar with the file's name, Open in Split View (where the window splits) and Close (Escape).
private struct DocumentSheet: View {
    let request: DocumentSheetRequest
    let editor: EditorController
    let navigator: Navigator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DocumentPane(name: request.name, label: request.label, editor: editor)
                #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("app:common.close") { dismiss() }
                            .accessibilityIdentifier("pdf-sheet-close")
                    }
                    if navigator.splitAllowed {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                navigator.documentSheet = nil
                                navigator.openInSplit(.file(name: request.name, label: request.label))
                            } label: {
                                IconLabel("app:split.openPage", icon: .squareSplitHorizontal)
                            }
                            .accessibilityIdentifier("pdf-sheet-split")
                        }
                    }
                }
        }
        .accessibilityIdentifier("pdf-sheet")
    }
}

/// What the two sides show, compared as one so that a swap is seen whole.
private struct PaneRoutes: Equatable {
    let leading: Pane
    let trailing: Pane?
}

/// A window's editors, each made once: the main one on first use, the split pane's when a page first opens there.
/// (`@State var editor = EditorController()` built a web view on every init of ContentView, which RootView re-inits
/// whenever the workspace or the appearance changes.)
@Observable
final class WindowEditors {
    @ObservationIgnored private(set) lazy var main = EditorController()
    var split: EditorController?
}
