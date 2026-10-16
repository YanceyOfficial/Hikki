import HikkiCore
import HikkiUI
import Observation
import UniformTypeIdentifiers
import WebKit

/// What every editor of a window shows the same way (Settings): each editor holds the latest and replays it when its
/// page comes up, so a second editor (the split pane) can't miss one.
struct EditorSettings: Equatable {
    var tone = ColorTone.standard
    /// Settings → Editor → Check spelling.
    var spellcheck = true
    /// Settings → AI → Review: how the page shows an AI edit (`inline`, `diff`, `bubble`).
    var aiReviewStyle = "inline"
    /// Settings → Shortcuts: the user's rebindings (the page handles the editor's own keys).
    var shortcuts = ShortcutOverrides()
}

/// Owns one long-lived WKWebView running the Tiptap bundle and mediates every bridge call.
/// Documents are swapped in place (`hikki.loadDocument`) instead of recreating the web view.
@Observable
final class EditorController {
    private(set) var isReady = false
    private(set) var activeFormats: Set<String> = []
    /// The open page's outline and size as the editor last reported them (`pageInfo`), for the inspector.
    private(set) var pageInfo: PageInfo?
    /// The heading the reader is in (block id), for the inspector's outline; nil above the first.
    private(set) var activeHeading: (docId: String, id: String?)?
    /// The text selected in the page (Ask AI offers it as context); nil when nothing is.
    private(set) var selection: EditorSelection?

    struct PageInfo: Equatable {
        var docId: String
        var headings: [OutlineHeading]
        var words: Int
        var characters: Int
    }
    @ObservationIgnored private(set) var webView: HikkiWebView!
    @ObservationIgnored private var store: DocumentStore?
    @ObservationIgnored private var assets: AssetStore?
    @ObservationIgnored private var currentDocumentID: String?
    @ObservationIgnored private var pendingDocumentID: String??
    /// A page whose title should get focus (selected) as soon as it is the loaded document.
    @ObservationIgnored private var titleFocusPageID: String?

    init() {
        webView = makeWebView()
        Self.live.removeAll { $0.editor == nil }
        Self.live.append(WeakEditor(editor: self))
        let center = NotificationCenter.default
        observers.tokens = [
            center.addObserver(forName: .pagesChangedOnDisk, object: nil, queue: .main) { [weak self] note in
                let ids = note.userInfo?["ids"] as? [String] ?? []
                MainActor.assumeIsolated { self?.reloadIfShowing(ids) }
            },
            // A page's comments changed (here, in the other editor, or from the side panel): the page shows them.
            center.addObserver(forName: .pageCommentsChanged, object: nil, queue: .main) { [weak self] note in
                let id = note.userInfo?["id"] as? String
                MainActor.assumeIsolated {
                    guard let self, id == nil || id == self.currentDocumentID else { return }
                    self.pushComments()
                }
            },
            // The same page open in another editor (split view's other side) was saved: show it here too.
            center.addObserver(forName: .pageSavedInEditor, object: nil, queue: .main) { [weak self] note in
                let id = note.userInfo?["id"] as? String
                let sender = (note.object as AnyObject?).map(ObjectIdentifier.init)
                MainActor.assumeIsolated {
                    guard let self, let id, sender != ObjectIdentifier(self) else { return }
                    self.reloadIfShowing([id])
                }
            },
        ]
    }

    #if DEBUG
        // A window's editor must go with its window (its web view is a process of its own): a missing line here after
        // closing one means something still holds it.
        deinit { Log.info("editor released", category: "bridge") }
    #endif

    /// The notification observers, removed when the editor goes.
    @ObservationIgnored private let observers = NotificationTokens()

    // MARK: - Every editor (⌘Q, backgrounding)

    private struct WeakEditor {
        weak var editor: EditorController?
    }

    /// Every editor alive, in any window.
    private static var live: [WeakEditor] = []

    /// Hands every editor's unsaved edits to the store (the app quitting or leaving the screen).
    static func flushAll(reason: String) async {
        for editor in live.compactMap(\.editor) { await editor.flush(reason: reason) }
    }

    // MARK: - Calling the page

    /// Runs a `window.hikki` call; a failure is logged under `label` (the page keeps its last state).
    @discardableResult
    private func call(_ script: String, _ arguments: [String: Any] = [:], label: String) async -> Any? {
        do {
            return try await webView.callAsyncJavaScript(script, arguments: arguments, contentWorld: .page)
        } catch {
            Log.warn("\(label) failed: \(error)", category: "bridge")
            return nil
        }
    }

    /// `call`, once the page is up (before that, the state is replayed on ready).
    private func send(_ script: String, _ arguments: [String: Any] = [:], label: String) {
        guard isReady else { return }
        Task { _ = await call(script, arguments, label: label) }
    }

    // MARK: - Comments

    /// The workspace's comment store (`comments/<page id>.json`), set by ContentView once the folder is known.
    @ObservationIgnored var comments: (() -> PageComments?) = { nil }
    /// This device's name, shown on comments written elsewhere ("on iPhone").
    @ObservationIgnored var deviceName: String?

    /// Sends the open page's threads to the page (after loading it, after a change here or elsewhere).
    func pushComments() {
        guard isReady, let id = currentDocumentID else { return }
        let threads = (try? comments()?.threads(of: id)) ?? []
        let payload: [[String: Any]] = threads.map { thread in
            [
                "id": thread.id, "quote": thread.quote, "resolved": thread.resolvedAt != nil,
                "comments": thread.comments.map { comment in
                    [
                        "id": comment.id, "body": comment.body, "author": comment.author ?? NSNull(),
                        "device": comment.device ?? NSNull(), "createdAt": comment.createdAt.timeIntervalSince1970 * 1000,
                        "editedAt": comment.editedAt.map { $0.timeIntervalSince1970 * 1000 } ?? NSNull(),
                    ] as [String: Any]
                },
            ]
        }
        send(
            "window.hikki.setComments(docId, threads, device)",
            ["docId": id, "threads": payload, "device": deviceName ?? NSNull()], label: "setComments")
    }

    /// A thread picked in the side panel: opened in the page, its passage in view.
    func openComment(_ threadId: String) {
        send("window.hikki.openComment(id)", ["id": threadId], label: "openComment")
    }

    /// A comment change from the page, into the store; every editor showing the page (and the side panel) hears.
    private func applyComment(pageId: String, _ change: (PageComments) throws -> Void) {
        guard let store = comments() else { return }
        do {
            try change(store)
            Log.info("comment changed", category: "comments", context: ["docId": pageId])
        } catch {
            Toasts.report(.commentFailed, error, category: "comments", context: ["docId": pageId])
        }
        NotificationCenter.default.post(name: .pageCommentsChanged, object: nil, userInfo: ["id": pageId])
    }

    /// Another device changed the open page (the workspace folder): show the new version in place. The editor
    /// declines while it holds unsaved edits — those win and are saved over it.
    func reloadIfShowing(_ ids: [String]) {
        guard isReady, pendingDocumentID == nil, let id = currentDocumentID, ids.contains(id) else { return }
        Task {
            do {
                guard let record = try store?.document(id: id), currentDocumentID == id else { return }
                let applied = try await webView.callAsyncJavaScript(
                    "return window.hikki.reload(page)", arguments: ["page": try PagePayload.make(from: record)], contentWorld: .page)
                if applied as? Bool == true {
                    pageState.loaded(id, locked: record.isLocked)
                    loaded = (id, try LoadedContent(record))
                }
                Log.info(
                    "open page changed on disk", category: "bridge", context: ["docId": id, "applied": "\(applied as? Bool ?? false)"])
            } catch {
                Log.error("reload failed: \(error)", category: "bridge", context: ["docId": id])
            }
        }
    }

    /// `history`: the workspace's page history (nil until a workspace is open) — saves keep versions through it.
    func attach(store: DocumentStore, assets: AssetStore, history: @escaping () -> PageHistory?) {
        self.store = store
        self.assets = assets
        self.history = history
        uploads = AssetUploads(store: assets)
        schemeHandler.assets = assets
    }

    @ObservationIgnored private var history: () -> PageHistory? = { nil }

    // MARK: - Import / export (editor/src/core/convert.ts)

    enum ConversionError: Error {
        case editorNotReady
        case unexpectedResult
    }

    /// The page as a Markdown or HTML document, written by the editor in its own schema.
    func exportText(_ record: DocumentRecord, format: ExportFormat) async throws -> String {
        guard isReady else { throw ConversionError.editorNotReady }
        let result = try await webView.callAsyncJavaScript(
            "return window.hikki.exportPage(page, format)",
            arguments: ["page": try PagePayload.make(from: record), "format": format.rawValue], contentWorld: .page)
        guard let text = result as? String else { throw ConversionError.unexpectedResult }
        return text
    }

    /// A file's text as a new page's title and body (always fitting the schema).
    func importDocument(_ text: String, format: ImportFormat, fallbackTitle: String) async throws -> ImportedPage {
        guard isReady else { throw ConversionError.editorNotReady }
        let result = try await webView.callAsyncJavaScript(
            "return window.hikki.importDocument(text, format, fallbackTitle)",
            arguments: ["text": text, "format": format.rawValue, "fallbackTitle": fallbackTitle], contentWorld: .page)
        guard let result else { throw ConversionError.unexpectedResult }
        return try ImportedPage.decode(scriptResult: result)
    }

    @ObservationIgnored private var uploads: AssetUploads?

    /// An attachment to show in Quick Look (ContentView's `.quickLookPreview`), opened from the editor.
    var previewURL: URL?

    /// A PDF attachment was clicked (ContentView opens it in a viewer pane): the asset's name and the file's own name.
    @ObservationIgnored var onOpenDocument: ((String, String) -> Void)?

    /// The file behind an asset name (the viewer pane reads it).
    func assetFile(named name: String) -> URL? { assets?.file(named: name) }

    /// A page link was clicked in the editor (ContentView routes it); the block to land on, if any.
    @ObservationIgnored var onOpenPage: ((String, String?) -> Void)?
    /// A page dropped on the page's right edge (split view); nil where there is no split view (iPhone).
    @ObservationIgnored var onOpenInSplit: ((String) -> Void)?
    /// `splitDropHover`: a page held over the edge would replace the right side (or no longer).
    @ObservationIgnored var onSplitDropHover: ((Bool) -> Void)?

    // MARK: - Pages and lock

    /// The workspace's pages as last pushed (the index links are named with, the open page's lock).
    @ObservationIgnored private var tree: PageTree?
    /// What the page was last told of them, so a body save sends nothing.
    @ObservationIgnored private var pageState = EditorPageState()
    /// Where to land as soon as its page is the loaded document: a block (a link to a block) or a search
    /// result's words.
    @ObservationIgnored private var pendingArrival: (pageID: String, arrival: Arrival)?

    private enum Arrival {
        case block(String)
        case text(terms: [String], blockID: String?)
    }

    /// The pages changed (any window, any device): the page's link index when a title or icon changed, and its lock
    /// when the open page was locked or unlocked — each editor hears for its own page.
    func setPages(_ tree: PageTree) {
        self.tree = tree
        guard isReady else { return }
        sendPageIndex()
        sendLockIfChanged()
    }

    private func sendPageIndex() {
        if let arguments = pageIndexArguments() { send("window.hikki.setPages(pages)", arguments, label: "setPages") }
    }

    /// The index to send, or nil when the page already has it.
    private func pageIndexArguments() -> [String: Any]? {
        guard let tree, let entries = pageState.index(for: tree.all) else { return nil }
        return ["pages": entries.map { ["id": $0.id, "title": $0.title, "icon": $0.icon ?? NSNull()] as [String: Any] }]
    }

    /// The open page was locked or unlocked while shown (`window.hikki.setLocked`; a page load carries its own).
    private func sendLockIfChanged() {
        guard isReady, pendingDocumentID == nil, let tree,
            let locked = pageState.lockChange(showing: currentDocumentID, in: tree)
        else { return }
        send("window.hikki.setLocked(locked)", ["locked": locked], label: "setLocked")
    }

    /// Scrolls to a block — now if its page is loaded, otherwise right after that page loads.
    func scrollToBlock(_ blockID: String, in pageID: String) {
        if isReady, currentDocumentID == pageID, pendingDocumentID == nil {
            send("window.hikki.scrollToBlock(id)", ["id": blockID], label: "scrollToBlock")
        } else {
            pendingArrival = (pageID, .block(blockID))
        }
    }

    /// A search result: scrolls to the block its match is in, the (folded) terms selected there — now if the page
    /// is loaded, otherwise right after it loads.
    func revealText(_ terms: [String], at blockID: String?, in pageID: String) {
        if isReady, currentDocumentID == pageID, pendingDocumentID == nil {
            Task { await callRevealText(terms, at: blockID) }
        } else {
            pendingArrival = (pageID, .text(terms: terms, blockID: blockID))
        }
    }

    #if DEBUG
        /// `HIKKI_DEBUG_AI_EDIT`: selects `words` and runs "Improve writing" on them, as the selection menu would; tries
        /// again while the page is still loading.
        func debugImprove(_ words: String, attempts: Int = 10) {
            Task {
                for _ in 0..<attempts {
                    if isReady,
                        await call("return window.hikki.demoAI([words], 'improve')", ["words": words.lowercased()], label: "debugImprove")
                            as? Bool == true
                    {
                        return
                    }
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }
    #endif

    private func callRevealText(_ terms: [String], at blockID: String?) async {
        await call(
            "window.hikki.revealText(terms, block)", ["terms": terms, "block": blockID ?? NSNull()], label: "revealText")
    }

    /// The inspector's outline: the heading to the top of the page, marked there as the one being read.
    func scrollToHeading(_ blockID: String) {
        guard currentDocumentID != nil else { return }
        send("window.hikki.jumpToHeading(id)", ["id": blockID], label: "jumpToHeading")
    }

    /// Whether the page draws its own hover outline rail (off while the inspector shows the outline).
    @ObservationIgnored private var outlineRailVisible = true

    func setOutlineRail(_ visible: Bool) {
        guard visible != outlineRailVisible else { return }
        outlineRailVisible = visible
        send("window.hikki.setOutlineRail(visible)", ["visible": visible], label: "setOutlineRail")
    }

    func open(documentID: String?, scrollTop: Double? = nil) {
        Task {
            await load(documentID)
            if let scrollTop, scrollTop > 0, let id = documentID, currentDocumentID == id {
                await call("window.hikki.restoreScroll(top)", ["top": scrollTop], label: "restoreScroll")
            }
        }
    }

    /// Where the open page was last scrolled (the editor reports it), for a tab to come back to.
    @ObservationIgnored private(set) var lastScroll: (docId: String, top: Double)?

    /// AI on the selection: the request goes to the app's AI service; its events come back through `sendAIEvent`.
    @ObservationIgnored var onAIRequest: ((AIRequestPayload) -> Void)?
    @ObservationIgnored var onAICancel: ((String) -> Void)?

    /// One event of an AI request's answer, to the page (`window.hikki.aiEvent`).
    func sendAIEvent(_ event: [String: Any]) {
        send("window.hikki.aiEvent(event)", ["event": event], label: "aiEvent")
    }

    /// Selects the page title for typing — now if that page is loaded, otherwise right after it loads.
    func focusTitle(of id: String) {
        if isReady, currentDocumentID == id, pendingDocumentID == nil {
            send("window.hikki.focusTitle()", label: "focusTitle")
        } else {
            titleFocusPageID = id
        }
    }

    func exec(_ command: EditorCommand) {
        guard isReady else { return }
        Task {
            do {
                _ = try await webView.callAsyncJavaScript(
                    "return window.hikki.exec(command)", arguments: ["command": command.rawValue], contentWorld: .page)
            } catch {
                Log.error("exec failed: \(error)", category: "bridge", context: ["command": command.rawValue])
            }
        }
    }

    /// The caret into the body (the iPhone's Edit button).
    func focusBody() {
        Task { _ = await call("window.hikki.focus()", label: "focus") }
    }

    /// Blurs the editor in JS (so ProseMirror's focus state stays truthful), then resigns the native first responder
    /// as a fallback in case the page is unresponsive.
    func dismissKeyboard() {
        Task {
            _ = await call("window.hikki.blur()", label: "blur")
            #if os(iOS)
                webView.endEditing(true)
            #endif
        }
    }

    /// Pulls the editor's current state synchronously from JS and saves it (scene backgrounding, doc switch).
    func flush(reason: String) async {
        guard isReady, currentDocumentID != nil else { return }
        do {
            guard let result = try await webView.callAsyncJavaScript("return window.hikki.flush()", contentWorld: .page),
                !(result is NSNull)
            else { return }
            save(try Snapshot.decode(scriptResult: result))
        } catch {
            Toasts.report(.pageSaveFailed, error, category: "bridge", context: ["reason": reason])
        }
    }

    // MARK: - Settings, find, insets

    /// The app's resolved language (e.g. "zh-Hans"), so the editor UI matches the native chrome.
    static var appLocale: String { Bundle.main.preferredLocalizations.first ?? "en" }

    /// The window's settings (ContentView keeps them current); sent as they change and replayed on ready.
    @ObservationIgnored private(set) var settings = EditorSettings()

    func apply(_ new: EditorSettings) {
        let old = settings
        settings = new
        guard isReady else { return }
        Task { await sendSettings(changedFrom: old) }
    }

    /// Each setting that differs from `old` (all of them with nil: the page just came up).
    private func sendSettings(changedFrom old: EditorSettings?) async {
        let new = settings
        if new.tone != old?.tone { await call("window.hikki.setTone(tone)", ["tone": new.tone.rawValue], label: "setTone") }
        if new.spellcheck != old?.spellcheck {
            await call("window.hikki.setSpellcheck(on)", ["on": new.spellcheck], label: "setSpellcheck")
        }
        if new.aiReviewStyle != old?.aiReviewStyle {
            await call("window.hikki.setAIReviewStyle(style)", ["style": new.aiReviewStyle], label: "setAIReviewStyle")
        }
        if new.shortcuts != old?.shortcuts {
            await call(
                "window.hikki.setShortcuts(overrides)", ["overrides": ShortcutStore.editorPayload(new.shortcuts)],
                label: "setShortcuts")
        }
    }

    /// Edit → Find… / Find and Replace… / Find Next / Find Previous (mirrors FindMode in the editor).
    enum FindMode: String { case find, replace, next, previous }

    func find(_ mode: FindMode) {
        guard isReady else {
            Log.warn("find before the editor was ready", category: "bridge", context: ["mode": mode.rawValue])
            return
        }
        send("window.hikki.find(mode)", ["mode": mode.rawValue], label: "find")
    }

    @ObservationIgnored private var autoFocus = true

    /// Whether a new, empty page takes the caret when it loads — off for the split pane's editor, so its page
    /// loading never takes the keyboard from the page being typed in beside it.
    func setAutoFocus(_ on: Bool) {
        autoFocus = on
        send("window.hikki.setAutoFocus(on)", ["on": on], label: "setAutoFocus")
    }

    /// What a page dropped on the page's right edge does (split view): open it beside, replace the right side, show it
    /// here (the right side's own editor), or nothing (iPhone). `editor/src/extensions/split-drop.ts`.
    enum SplitDropMode: String { case off, open, replace, here }

    @ObservationIgnored private var splitDrop = SplitDropMode.off

    func setSplitDrop(_ mode: SplitDropMode) {
        guard splitDrop != mode else { return }
        splitDrop = mode
        send("window.hikki.setSplitDrop(mode)", ["mode": mode.rawValue], label: "setSplitDrop")
    }

    /// Height of the toolbar the page runs under, so fixed panels in the page (find) sit below it; and of the bar
    /// floating over its foot (iPhone, keyboard down), so a bottom sheet (comments) keeps its field above it.
    @ObservationIgnored private var topInset: CGFloat = 0
    @ObservationIgnored private var bleedTop = false
    @ObservationIgnored private var bottomInset: CGFloat = 0

    /// `bleed` (iPhone): the scroll view has no top inset and the page makes that room itself (a cover fills it).
    func setInsets(top: CGFloat, bottom: CGFloat, bleed: Bool = false) {
        guard top != topInset || bottom != bottomInset || bleed != bleedTop else { return }
        topInset = top
        bottomInset = bottom
        bleedTop = bleed
        send("window.hikki.setInsets({ top, bottom, bleed })", insetArguments, label: "setInsets")
    }

    private var insetArguments: [String: Any] {
        ["top": Double(topInset), "bottom": Double(bottomInset), "bleed": bleedTop]
    }

    /// Everything the page is told besides its document, in order, when it comes up (first load, a crashed web
    /// process reloaded).
    private func replayState() async {
        await call("window.hikki.setLocale(locale)", ["locale": Self.appLocale], label: "setLocale")
        await sendSettings(changedFrom: nil)
        await call("window.hikki.setAutoFocus(on)", ["on": autoFocus], label: "setAutoFocus")
        await call("window.hikki.setSplitDrop(mode)", ["mode": splitDrop.rawValue], label: "setSplitDrop")
        await call("window.hikki.setInsets({ top, bottom, bleed })", insetArguments, label: "setInsets")
        if !outlineRailVisible {
            await call("window.hikki.setOutlineRail(visible)", ["visible": false], label: "setOutlineRail")
        }
        if let arguments = pageIndexArguments() { await call("window.hikki.setPages(pages)", arguments, label: "setPages") }
    }

    // MARK: - Loading

    private func load(_ id: String?) async {
        guard isReady else {
            pendingDocumentID = .some(id)
            return
        }
        await flush(reason: "switch")
        currentDocumentID = id
        guard let id else {
            pageState.loaded(nil, locked: false)
            return
        }
        do {
            guard let record = try store?.document(id: id) else {
                Log.warn("open: document missing", category: "store", context: ["docId": id])
                return
            }
            _ = try await webView.callAsyncJavaScript(
                "window.hikki.loadDocument(page)",
                arguments: ["page": try PagePayload.make(from: record)],
                contentWorld: .page
            )
            loaded = (id, try LoadedContent(record))
            // The payload carried the page's lock; one set while it loaded goes now.
            pageState.loaded(id, locked: record.isLocked)
            sendLockIfChanged()
            pushComments()
            if titleFocusPageID == id {
                titleFocusPageID = nil
                await call("window.hikki.focusTitle()", label: "focusTitle")
            }
            if let pending = pendingArrival, pending.pageID == id {
                pendingArrival = nil
                switch pending.arrival {
                case .block(let blockID):
                    await call("window.hikki.scrollToBlock(id)", ["id": blockID], label: "scrollToBlock")
                case .text(let terms, let blockID): await callRevealText(terms, at: blockID)
                }
            }
        } catch {
            Toasts.report(.pageLoadFailed, error, category: "bridge", context: ["docId": id])
        }
    }

    // MARK: - Bridge

    /// Returns the reply for messages that expect one (WKScriptMessageHandlerWithReply).
    func handle(_ message: BridgeMessage) throws -> Any? {
        switch message {
        case .ready(let version):
            guard version == BridgeProtocol.version else {
                Log.error(
                    "bridge protocol mismatch", category: "bridge", context: ["web": "\(version)", "native": "\(BridgeProtocol.version)"])
                return nil
            }
            isReady = true
            // Cold start of the bundle (web content process + parse + first render); IDs/timings only.
            let elapsed = loadStartedAt.map { Int(Date.now.timeIntervalSince($0) * 1000) } ?? -1
            Log.info("editor ready", category: "bridge", context: ["ms": "\(elapsed)"])
            let pending = pendingDocumentID ?? currentDocumentID
            pendingDocumentID = nil
            currentDocumentID = nil
            // A fresh page knows nothing yet: everything is sent again.
            pageState.reset()
            Task {
                await replayState()
                await load(pending ?? nil)
            }
        case .changed(let snapshot):
            save(snapshot)
        case .activeFormats(let active):
            activeFormats = Set(active)
        case .pageInfo(let docId, let headings, let words, let characters):
            pageInfo = PageInfo(docId: docId, headings: headings, words: words, characters: characters)
        case .activeHeading(let docId, let id):
            activeHeading = (docId, id)
        case .commentCreate(let docId, let threadId, let quote, let body):
            applyComment(pageId: docId) { try $0.create(pageId: docId, threadId: threadId, quote: quote, body: body) }
        case .commentReply(let docId, let threadId, let body):
            applyComment(pageId: docId) { try $0.reply(pageId: docId, threadId: threadId, body: body) }
        case .commentResolve(let docId, let threadId, let resolved):
            applyComment(pageId: docId) { try $0.setResolved(resolved, pageId: docId, threadId: threadId) }
        case .commentDelete(let docId, let threadId, let commentId):
            applyComment(pageId: docId) { try $0.delete(pageId: docId, threadId: threadId, commentId: commentId) }
        case .commentEdit(let docId, let threadId, let commentId, let body):
            applyComment(pageId: docId) { try $0.edit(pageId: docId, threadId: threadId, commentId: commentId, body: body) }
        case .selection(let docId, let text):
            selection = text.isEmpty ? nil : EditorSelection(docId: docId, text: text)
        case .scroll(let docId, let top):
            lastScroll = (docId, top)
        case .aiRequest(let payload):
            onAIRequest?(payload)
        case .aiCancel(let id):
            onAICancel?(id)
        case .log(let level, let message, let context):
            Log.write(level, message, category: "web", context: context)
        case .toast(let kind, let message):
            let kinds: [String: ToastView.Kind] = ["success": .success, "info": .info, "warning": .warning, "error": .error]
            Toasts.shared.show(kinds[kind] ?? .info, message)
        case .reportError(let number, let detail, let context):
            var fields = context ?? [:]
            if let detail { fields["detail"] = String(detail.prefix(500)) }
            Toasts.report(ErrorCode(number: number) ?? .unknown, category: "editor", context: fields)
        case .setIcon(let docId, let icon):
            try store?.setIcon(icon, for: docId)
        case .setCover(let docId, let cover):
            try store?.setCover(cover, for: docId)
        case .saveAsset(let fileExtension, let data):
            guard let assets else { throw BridgeError.invalidPayload("asset store not attached") }
            let url = try assets.save(data, fileExtension: fileExtension)
            Log.info("asset saved", category: "store", context: ["bytes": "\(data.count)", "ext": fileExtension])
            return url
        case .beginUpload(let fileExtension, let size):
            guard let uploads else { throw BridgeError.invalidPayload("asset store not attached") }
            return try uploads.begin(fileExtension: fileExtension, size: size)
        case .uploadChunk(let id, let data):
            try uploads?.append(id, data)
        case .finishUpload(let id):
            guard let uploads else { throw BridgeError.invalidPayload("asset store not attached") }
            let url = try uploads.finish(id)
            Log.info("upload saved", category: "store", context: ["ext": (url as NSString).pathExtension])
            return url
        case .cancelUpload(let id):
            uploads?.cancel(id)
        case .openAsset(let url, let label):
            // Attachments open natively, never inside the web view (an HTML file must not run there): a PDF in the
            // viewer pane, anything else in Quick Look.
            guard let name = AssetStore.name(fromURL: url), let file = assets?.file(named: name) else {
                throw BridgeError.invalidPayload("openAsset: unknown asset")
            }
            if file.pathExtension.lowercased() == "pdf", let onOpenDocument {
                onOpenDocument(name, label ?? file.lastPathComponent)
            } else {
                previewURL = file
            }
        case .openPage(let id, let block):
            onOpenPage?(id, block)
        case .openInSplit(let id):
            onOpenInSplit?(id)
        case .splitDropHover(let active):
            onSplitDropHover?(active)
        case .openLink(let url):
            // Clicked in the page: only web/mail/phone links leave the app; nothing else is opened.
            guard let target = URL(string: url), let scheme = target.scheme?.lowercased(),
                ["http", "https", "mailto", "tel"].contains(scheme)
            else { throw BridgeError.invalidPayload("openLink: unsupported URL") }
            #if os(iOS)
                UIApplication.shared.open(target)
            #else
                NSWorkspace.shared.open(target)
            #endif
        case .linkPreview:
            return nil  // answered by the message proxy (it needs the network)
        case .suggestReading(let text):
            // Short selections only: a reading is for a word or phrase, and the tokenizer runs on the main thread.
            guard text.count <= 80, let segments = JapaneseReading.segments(for: text) else { return nil }
            return segments.map { ["text": $0.text, "reading": $0.reading ?? NSNull()] as [String: Any] }
        }
        return nil
    }

    /// The title and body the page last had here — loaded, reloaded or saved. A save finding the stored page changed
    /// since (another device's version came in while this editor held unsaved edits, or the page beside it saved)
    /// keeps that version as a conflicted copy before writing (`DocumentStore.saveContent(_:loaded:)`).
    @ObservationIgnored private var loaded: (id: String, content: LoadedContent)?

    private func save(_ snapshot: Snapshot) {
        // Page history: the first save of an editing session keeps the page as it was (PageHistory's policy).
        if let history = history(), let store {
            do {
                try history.recordBeforeEdit(pageID: snapshot.docId, newTitle: snapshot.title, newContent: snapshot.content) {
                    try store.document(id: snapshot.docId)
                }
            } catch {
                Log.warn("page version not kept: \(error)", category: "history", context: ["docId": snapshot.docId])
            }
        }
        do {
            let base = loaded?.id == snapshot.docId ? loaded?.content : nil
            if try store?.saveContent(snapshot, loaded: base, conflictTitle: AppModel.conflictTitle) == false {
                Log.warn("save skipped: document no longer exists", category: "store", context: ["docId": snapshot.docId])
            } else {
                loaded = (snapshot.docId, LoadedContent(snapshot))
                NotificationCenter.default.post(name: .pageSavedInEditor, object: self, userInfo: ["id": snapshot.docId])
            }
        } catch {
            Toasts.report(.pageSaveFailed, error, category: "store", context: ["docId": snapshot.docId])
        }
    }

    fileprivate func webContentProcessDidTerminate() {
        Toasts.report(.editorCrashed, category: "bridge", context: ["docId": currentDocumentID ?? "-"])
        isReady = false
        pendingDocumentID = .some(currentDocumentID)
        loadStartedAt = .now
        webView.load(URLRequest(url: EditorSchemeHandler.entryURL))
    }

    // MARK: - Web view setup

    @ObservationIgnored private let schemeHandler = EditorSchemeHandler()

    private func makeWebView() -> HikkiWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: EditorSchemeHandler.scheme)
        configuration.userContentController.addScriptMessageHandler(
            ScriptMessageProxy(owner: self), contentWorld: .page, name: "hikki"
        )
        let webView = HikkiWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = navigationDelegate
        webView.uiDelegate = uiDelegate
        navigationDelegate.owner = self
        #if DEBUG
            webView.isInspectable = true
        #endif
        // No white flash behind the page in dark mode while the bundle loads.
        #if os(iOS)
            webView.isOpaque = false
            webView.backgroundColor = .clear
            webView.scrollView.backgroundColor = .clear
        #else
            webView.underPageBackgroundColor = .clear
            webView.setValue(false, forKey: "drawsBackground")
        #endif
        #if os(iOS)
            webView.installKeyboardToolbar(controller: self)
        #endif
        loadStartedAt = .now
        webView.load(URLRequest(url: EditorSchemeHandler.entryURL))
        return webView
    }

    @ObservationIgnored private let navigationDelegate = NavigationDelegate()
    @ObservationIgnored private let uiDelegate = EditorUIDelegate()
    @ObservationIgnored private var loadStartedAt: Date?
}

/// Block-based notification observers, removed when their owner (and so this) goes.
nonisolated private final class NotificationTokens: @unchecked Sendable {
    nonisolated(unsafe) var tokens: [any NSObjectProtocol] = []

    deinit {
        for token in tokens { NotificationCenter.default.removeObserver(token) }
    }
}

/// WKUserContentController retains its handlers; this proxy keeps the controller weakly referenced.
private final class ScriptMessageProxy: NSObject, WKScriptMessageHandlerWithReply {
    weak var owner: EditorController?

    init(owner: EditorController) {
        self.owner = owner
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) async -> (
        Any?, String?
    ) {
        // Embedded pages get `window.webkit.messageHandlers` too: only the editor's own page is listened to.
        let frame = message.frameInfo
        guard
            BridgeProtocol.trustsFrame(
                isMainFrame: frame.isMainFrame, scheme: frame.securityOrigin.protocol,
                editorScheme: EditorSchemeHandler.scheme)
        else {
            Log.warn("bridge message from an untrusted frame dropped", category: "bridge")
            return (nil, "untrusted frame")
        }
        do {
            let decoded = try BridgeMessage.decode(scriptMessageBody: message.body)
            // A link card's details come from the network: answered here, off the main actor's synchronous path.
            if case .linkPreview(let url) = decoded {
                guard let target = URL(string: url), let preview = try? await LinkPreview.fetch(target) else { return (nil, nil) }
                let reply: [String: Any] = [
                    "title": preview.title ?? NSNull(), "description": preview.description ?? NSNull(),
                    "icon": preview.icon ?? NSNull(),
                ]
                return (reply, nil)
            }
            let reply = try owner?.handle(decoded)
            return (reply, nil)
        } catch {
            Log.error("bridge message failed: \(error)", category: "bridge")
            return (nil, "\(error)")
        }
    }
}

/// `<input type="file">` (covers, media, attachments): iOS presents the system picker itself, but a macOS WKWebView
/// does nothing unless the UI delegate shows an open panel.
private final class EditorUIDelegate: NSObject, WKUIDelegate {
    /// A link inside an embed that wants a new window (target=_blank, window.open): the system browser gets it.
    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url, url.scheme == "https" || url.scheme == "http" {
            #if os(iOS)
                UIApplication.shared.open(url)
            #else
                NSWorkspace.shared.open(url)
            #endif
        }
        return nil
    }

    #if os(macOS)
        func webView(
            _ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo
        ) async -> [URL]? {
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = parameters.allowsMultipleSelection
            panel.canChooseDirectories = false
            // Images (covers), video, audio and any attachment: the page and the asset store check types.
            let response: NSApplication.ModalResponse
            if let window = webView.window {
                response = await panel.beginSheetModal(for: window)
            } else {
                response = panel.runModal()
            }
            return response == .OK ? panel.urls : nil
        }
    #endif
}

private final class NavigationDelegate: NSObject, WKNavigationDelegate {
    weak var owner: EditorController?

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        owner?.webContentProcessDidTerminate()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        // The rules live in EditorNavigationPolicy (HikkiCore, tested): the bundled editor as the page, https /
        // about: in an embed's frame, clicked links to the system, nothing else.
        let url = navigationAction.request.url
        switch EditorNavigationPolicy.decide(
            url: url, isMainFrame: navigationAction.targetFrame?.isMainFrame,
            isLinkClick: navigationAction.navigationType == .linkActivated, editorScheme: EditorSchemeHandler.scheme)
        {
        case .load:
            return .allow
        case .openOutside:
            if let url {
                #if os(iOS)
                    await UIApplication.shared.open(url)
                #else
                    NSWorkspace.shared.open(url)
                #endif
            }
            return .cancel
        case .cancel:
            return .cancel
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Log.error("editor navigation failed: \(error)", category: "bridge")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Log.error("editor provisional navigation failed: \(error)", category: "bridge")
    }
}

extension Notification.Name {
    /// An editor saved a page (`userInfo["id"]`, the editor as `object`): another editor showing it reloads.
    static let pageSavedInEditor = Notification.Name("app.yancey.hikki.pageSavedInEditor")
    /// A page's comments changed (`userInfo["id"]`; none: any page — the app came back and other devices may have
    /// written): editors showing it and the side panel reload them.
    static let pageCommentsChanged = Notification.Name("app.yancey.hikki.pageCommentsChanged")
}
