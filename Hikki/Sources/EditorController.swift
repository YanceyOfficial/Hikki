import HikkiCore
import HikkiUI
import Observation
import UniformTypeIdentifiers
import WebKit

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
        diskChanges = NotificationCenter.default.addObserver(forName: .pagesChangedOnDisk, object: nil, queue: .main) {
            [weak self] note in
            let ids = note.userInfo?["ids"] as? [String] ?? []
            MainActor.assumeIsolated { self?.reloadIfShowing(ids) }
        }
        // A page's comments changed (here, in the other editor, or from the side panel): the page shows them.
        commentChanges = NotificationCenter.default.addObserver(forName: .pageCommentsChanged, object: nil, queue: .main) {
            [weak self] note in
            let id = note.userInfo?["id"] as? String
            MainActor.assumeIsolated {
                guard let self, id == nil || id == self.currentDocumentID else { return }
                self.pushComments()
            }
        }
        // The same page open in another editor (split view's other side) was saved: show it here too.
        siblingSaves = NotificationCenter.default.addObserver(forName: .pageSavedInEditor, object: nil, queue: .main) {
            [weak self] note in
            let id = note.userInfo?["id"] as? String
            let sender = (note.object as AnyObject?).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                guard let self, let id, sender != ObjectIdentifier(self) else { return }
                self.reloadIfShowing([id])
            }
        }
    }

    @ObservationIgnored private var diskChanges: (any NSObjectProtocol)?
    @ObservationIgnored private var siblingSaves: (any NSObjectProtocol)?
    @ObservationIgnored private var commentChanges: (any NSObjectProtocol)?

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
        Task {
            do {
                _ = try await webView.callAsyncJavaScript(
                    "window.hikki.setComments(docId, threads, device)",
                    arguments: ["docId": id, "threads": payload, "device": deviceName ?? NSNull()], contentWorld: .page)
            } catch {
                Log.warn("setComments failed: \(error)", category: "bridge")
            }
        }
    }

    /// A thread picked in the side panel: opened in the page, its passage in view.
    func openComment(_ threadId: String) {
        guard isReady else { return }
        Task {
            _ = try? await webView.callAsyncJavaScript(
                "window.hikki.openComment(id)", arguments: ["id": threadId], contentWorld: .page)
        }
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

    /// Pages the editor names links with (`window.hikki.setPages`), kept to resend after a reload.
    @ObservationIgnored private var pages: [[String: Any]] = []
    /// A block to scroll to as soon as its page is the loaded document (a link to a block).
    @ObservationIgnored private var pendingBlock: (pageID: String, blockID: String)?

    func setPages(_ summaries: [PageSummary]) {
        pages = summaries.map { ["id": $0.id, "title": $0.title, "icon": $0.icon ?? NSNull()] }
        guard isReady else { return }
        Task { await applyPages() }
    }

    private func applyPages() async {
        do {
            _ = try await webView.callAsyncJavaScript(
                "window.hikki.setPages(pages)", arguments: ["pages": pages], contentWorld: .page)
        } catch {
            Log.warn("setPages failed: \(error)", category: "bridge")
        }
    }

    /// Scrolls to a block — now if its page is loaded, otherwise right after that page loads.
    func scrollToBlock(_ blockID: String, in pageID: String) {
        if isReady, currentDocumentID == pageID, pendingDocumentID == nil {
            Task { await callScrollToBlock(blockID) }
        } else {
            pendingBlock = (pageID, blockID)
        }
    }

    /// The inspector's outline: a heading of the open page.
    /// The inspector's outline: the heading to the top of the page, marked there as the one being read.
    func scrollToHeading(_ blockID: String) {
        guard isReady, currentDocumentID != nil else { return }
        Task {
            do {
                _ = try await webView.callAsyncJavaScript(
                    "window.hikki.jumpToHeading(id)", arguments: ["id": blockID], contentWorld: .page)
            } catch {
                Log.warn("jumpToHeading failed: \(error)", category: "bridge")
            }
        }
    }

    /// Whether the page draws its own hover outline rail (off while the inspector shows the outline).
    @ObservationIgnored private var outlineRailVisible = true

    func setOutlineRail(_ visible: Bool) {
        guard visible != outlineRailVisible else { return }
        outlineRailVisible = visible
        guard isReady else { return }
        Task { await applyOutlineRail() }
    }

    private func applyOutlineRail() async {
        do {
            _ = try await webView.callAsyncJavaScript(
                "window.hikki.setOutlineRail(visible)", arguments: ["visible": outlineRailVisible], contentWorld: .page)
        } catch {
            Log.warn("setOutlineRail failed: \(error)", category: "bridge")
        }
    }

    private func callScrollToBlock(_ blockID: String) async {
        do {
            _ = try await webView.callAsyncJavaScript(
                "window.hikki.scrollToBlock(id)", arguments: ["id": blockID], contentWorld: .page)
        } catch {
            Log.warn("scrollToBlock failed: \(error)", category: "bridge")
        }
    }

    func open(documentID: String?, scrollTop: Double? = nil) {
        Task {
            await load(documentID)
            if let scrollTop, scrollTop > 0, let id = documentID, currentDocumentID == id {
                await restoreScroll(scrollTop)
            }
        }
    }

    /// Where the open page was last scrolled (the editor reports it), for a tab to come back to.
    @ObservationIgnored private(set) var lastScroll: (docId: String, top: Double)?

    private func restoreScroll(_ top: Double) async {
        do {
            _ = try await webView.callAsyncJavaScript(
                "window.hikki.restoreScroll(top)", arguments: ["top": top], contentWorld: .page)
        } catch {
            Log.warn("restoreScroll failed: \(error)", category: "bridge")
        }
    }

    /// AI on the selection: the request goes to the app's AI service; its events come back through `sendAIEvent`.
    @ObservationIgnored var onAIRequest: ((AIRequestPayload) -> Void)?
    @ObservationIgnored var onAICancel: ((String) -> Void)?

    /// One event of an AI request's answer, to the page (`window.hikki.aiEvent`).
    func sendAIEvent(_ event: [String: Any]) {
        guard isReady else { return }
        Task {
            do {
                _ = try await webView.callAsyncJavaScript(
                    "window.hikki.aiEvent(event)", arguments: ["event": event], contentWorld: .page)
            } catch {
                Log.warn("aiEvent failed: \(error)", category: "bridge")
            }
        }
    }

    /// Selects the page title for typing — now if that page is loaded, otherwise right after it loads.
    func focusTitle(of id: String) {
        if isReady, currentDocumentID == id, pendingDocumentID == nil {
            Task { await callFocusTitle() }
        } else {
            titleFocusPageID = id
        }
    }

    private func callFocusTitle() async {
        do {
            _ = try await webView.callAsyncJavaScript("window.hikki.focusTitle()", contentWorld: .page)
        } catch {
            Log.warn("focusTitle failed: \(error)", category: "bridge")
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

    /// Blurs the editor in JS (so ProseMirror's focus state stays truthful), then resigns the native first
    /// responder as a fallback in case the page is unresponsive.
    /// The caret into the body (the iPhone's Edit button).
    func focusBody() {
        Task {
            do {
                _ = try await webView.callAsyncJavaScript("window.hikki.focus()", contentWorld: .page)
            } catch {
                Log.warn("focus failed: \(error)", category: "bridge")
            }
        }
    }

    func dismissKeyboard() {
        Task {
            do {
                _ = try await webView.callAsyncJavaScript("window.hikki.blur()", contentWorld: .page)
            } catch {
                Log.warn("blur failed: \(error)", category: "bridge")
            }
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

    // MARK: - Locale

    /// The app's resolved language (e.g. "zh-Hans"), so the editor UI matches the native chrome.
    static var appLocale: String { Bundle.main.preferredLocalizations.first ?? "en" }

    private func applyLocale() async {
        do {
            _ = try await webView.callAsyncJavaScript(
                "window.hikki.setLocale(locale)", arguments: ["locale": Self.appLocale], contentWorld: .page)
        } catch {
            Log.warn("setLocale failed: \(error)", category: "bridge")
        }
    }

    // MARK: - Find, spelling, insets

    /// Edit → Find… / Find and Replace… / Find Next / Find Previous (mirrors FindMode in the editor).
    enum FindMode: String { case find, replace, next, previous }

    func find(_ mode: FindMode) {
        guard isReady else {
            Log.warn("find before the editor was ready", category: "bridge", context: ["mode": mode.rawValue])
            return
        }
        Task {
            do {
                _ = try await webView.callAsyncJavaScript(
                    "window.hikki.find(mode)", arguments: ["mode": mode.rawValue], contentWorld: .page)
            } catch {
                Log.warn("find failed: \(error)", category: "bridge")
            }
        }
    }

    /// Settings → Editor → Check spelling; sent on ready and whenever it changes.
    @ObservationIgnored private var spellcheck = true

    func setSpellcheck(_ on: Bool) {
        spellcheck = on
        guard isReady else { return }
        Task { await applySpellcheck() }
    }

    @ObservationIgnored private var autoFocus = true

    /// Whether a new, empty page takes the caret when it loads — off for the split pane's editor, so its page
    /// loading never takes the keyboard from the page being typed in beside it.
    func setAutoFocus(_ on: Bool) {
        autoFocus = on
        guard isReady else { return }
        Task { await applyAutoFocus() }
    }

    private func applyAutoFocus() async {
        do {
            _ = try await webView.callAsyncJavaScript(
                "window.hikki.setAutoFocus(on)", arguments: ["on": autoFocus], contentWorld: .page)
        } catch {
            Log.warn("setAutoFocus failed: \(error)", category: "bridge")
        }
    }

    @ObservationIgnored private var aiReviewStyle = "inline"

    /// Settings → AI → Review: how the page shows an AI edit (`inline`, `diff`, `bubble`).
    func setAIReviewStyle(_ style: String) {
        aiReviewStyle = style
        guard isReady else { return }
        Task { await applyAIReviewStyle() }
    }

    private func applyAIReviewStyle() async {
        do {
            _ = try await webView.callAsyncJavaScript(
                "window.hikki.setAIReviewStyle(style)", arguments: ["style": aiReviewStyle], contentWorld: .page)
        } catch {
            Log.warn("setAIReviewStyle failed: \(error)", category: "bridge")
        }
    }

    private func applySpellcheck() async {
        do {
            _ = try await webView.callAsyncJavaScript(
                "window.hikki.setSpellcheck(on)", arguments: ["on": spellcheck], contentWorld: .page)
        } catch {
            Log.warn("setSpellcheck failed: \(error)", category: "bridge")
        }
    }

    /// What a page dropped on the page's right edge does (split view): open it beside, replace the right side, show it
    /// here (the right side's own editor), or nothing (iPhone). `editor/src/extensions/split-drop.ts`.
    enum SplitDropMode: String { case off, open, replace, here }

    @ObservationIgnored private var splitDrop = SplitDropMode.off

    func setSplitDrop(_ mode: SplitDropMode) {
        guard splitDrop != mode else { return }
        splitDrop = mode
        guard isReady else { return }
        Task { await applySplitDrop() }
    }

    private func applySplitDrop() async {
        do {
            _ = try await webView.callAsyncJavaScript(
                "window.hikki.setSplitDrop(mode)", arguments: ["mode": splitDrop.rawValue], contentWorld: .page)
        } catch {
            Log.warn("setSplitDrop failed: \(error)", category: "bridge")
        }
    }

    /// Settings → Shortcuts: the user's rebindings (`ShortcutStore`), sent on ready and whenever they change.
    func updateShortcuts() {
        guard isReady else { return }
        Task { await applyShortcuts() }
    }

    private func applyShortcuts() async {
        do {
            _ = try await webView.callAsyncJavaScript(
                "window.hikki.setShortcuts(overrides)", arguments: ["overrides": ShortcutStore.shared.editorPayload],
                contentWorld: .page)
        } catch {
            Log.warn("setShortcuts failed: \(error)", category: "bridge")
        }
    }

    /// The open page was locked or unlocked while shown (`window.hikki.setLocked`; a page load carries its own).
    func setLocked(_ locked: Bool) {
        guard isReady else { return }
        Task {
            do {
                _ = try await webView.callAsyncJavaScript(
                    "window.hikki.setLocked(locked)", arguments: ["locked": locked], contentWorld: .page)
            } catch {
                Log.warn("setLocked failed: \(error)", category: "bridge")
            }
        }
    }

    /// Height of the toolbar the page runs under, so fixed panels in the page (find) sit below it; and of the bar
    /// floating over its foot (iPhone, keyboard down), so a bottom sheet (comments) keeps its field above it.
    @ObservationIgnored private var topInset: CGFloat = 0
    @ObservationIgnored private var bottomInset: CGFloat = 0

    func setInsets(top: CGFloat, bottom: CGFloat) {
        guard top != topInset || bottom != bottomInset else { return }
        topInset = top
        bottomInset = bottom
        guard isReady else { return }
        Task { await applyInsets() }
    }

    private func applyInsets() async {
        do {
            _ = try await webView.callAsyncJavaScript(
                "window.hikki.setInsets({ top, bottom })",
                arguments: ["top": Double(topInset), "bottom": Double(bottomInset)], contentWorld: .page)
        } catch {
            Log.warn("setInsets failed: \(error)", category: "bridge")
        }
    }

    // MARK: - Color tone

    /// The tone the editor should paint in (Settings → Appearance); sent on ready and whenever it changes.
    @ObservationIgnored private var tone = ColorTone.standard

    func setTone(_ tone: ColorTone) {
        self.tone = tone
        guard isReady else { return }
        Task { await applyTone() }
    }

    private func applyTone() async {
        do {
            _ = try await webView.callAsyncJavaScript(
                "window.hikki.setTone(tone)", arguments: ["tone": tone.rawValue], contentWorld: .page)
        } catch {
            Log.warn("setTone failed: \(error)", category: "bridge")
        }
    }

    // MARK: - Loading

    private func load(_ id: String?) async {
        guard isReady else {
            pendingDocumentID = .some(id)
            return
        }
        await flush(reason: "switch")
        currentDocumentID = id
        guard let id else { return }
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
            pushComments()
            if titleFocusPageID == id {
                titleFocusPageID = nil
                await callFocusTitle()
            }
            if let pending = pendingBlock, pending.pageID == id {
                pendingBlock = nil
                await callScrollToBlock(pending.blockID)
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
            if !outlineRailVisible { Task { await applyOutlineRail() } }
            // Cold start of the bundle (web content process + parse + first render); IDs/timings only.
            let elapsed = loadStartedAt.map { Int(Date.now.timeIntervalSince($0) * 1000) } ?? -1
            Log.info("editor ready", category: "bridge", context: ["ms": "\(elapsed)"])
            let pending = pendingDocumentID ?? currentDocumentID
            pendingDocumentID = nil
            currentDocumentID = nil
            Task {
                await applyLocale()
                await applyTone()
                await applySpellcheck()
                await applyAIReviewStyle()
                await applyAutoFocus()
                await applyShortcuts()
                await applySplitDrop()
                await applyInsets()
                await applyPages()
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
            if try store?.saveContent(snapshot) == false {
                Log.warn("save skipped: document no longer exists", category: "store", context: ["docId": snapshot.docId])
            } else {
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

/// Text selected in a page (`selection` bridge message).
struct EditorSelection: Equatable {
    let docId: String
    let text: String
}
