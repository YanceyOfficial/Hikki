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
    }

    @ObservationIgnored private var diskChanges: (any NSObjectProtocol)?

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

    func attach(store: DocumentStore, assets: AssetStore) {
        self.store = store
        self.assets = assets
        uploads = AssetUploads(store: assets)
        schemeHandler.assets = assets
    }

    @ObservationIgnored private var uploads: AssetUploads?

    /// An attachment to show in Quick Look (ContentView's `.quickLookPreview`), opened from the editor.
    var previewURL: URL?

    /// A page link was clicked in the editor (ContentView routes it); the block to land on, if any.
    @ObservationIgnored var onOpenPage: ((String, String?) -> Void)?

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

    private func callScrollToBlock(_ blockID: String) async {
        do {
            _ = try await webView.callAsyncJavaScript(
                "window.hikki.scrollToBlock(id)", arguments: ["id": blockID], contentWorld: .page)
        } catch {
            Log.warn("scrollToBlock failed: \(error)", category: "bridge")
        }
    }

    func open(documentID: String?) {
        Task { await load(documentID) }
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
            Log.error("flush failed: \(error)", category: "bridge", context: ["reason": reason])
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
        guard isReady else { return }
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

    private func applySpellcheck() async {
        do {
            _ = try await webView.callAsyncJavaScript(
                "window.hikki.setSpellcheck(on)", arguments: ["on": spellcheck], contentWorld: .page)
        } catch {
            Log.warn("setSpellcheck failed: \(error)", category: "bridge")
        }
    }

    /// Height of the toolbar the page runs under, so fixed panels in the page (find) sit below it.
    @ObservationIgnored private var topInset: CGFloat = 0

    func setTopInset(_ top: CGFloat) {
        guard top != topInset else { return }
        topInset = top
        guard isReady else { return }
        Task { await applyInsets() }
    }

    private func applyInsets() async {
        do {
            _ = try await webView.callAsyncJavaScript(
                "window.hikki.setInsets({ top })", arguments: ["top": Double(topInset)], contentWorld: .page)
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
            if titleFocusPageID == id {
                titleFocusPageID = nil
                await callFocusTitle()
            }
            if let pending = pendingBlock, pending.pageID == id {
                pendingBlock = nil
                await callScrollToBlock(pending.blockID)
            }
        } catch {
            Log.error("load failed: \(error)", category: "bridge", context: ["docId": id])
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
            Task {
                await applyLocale()
                await applyTone()
                await applySpellcheck()
                await applyInsets()
                await applyPages()
                await load(pending ?? nil)
            }
        case .changed(let snapshot):
            save(snapshot)
        case .activeFormats(let active):
            activeFormats = Set(active)
        case .log(let level, let message, let context):
            Log.write(level, message, category: "web", context: context)
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
        case .openAsset(let url):
            // Attachments open in Quick Look, never inside the web view (an HTML file must not run there).
            guard let name = AssetStore.name(fromURL: url), let file = assets?.file(named: name) else {
                throw BridgeError.invalidPayload("openAsset: unknown asset")
            }
            previewURL = file
        case .openPage(let id, let block):
            onOpenPage?(id, block)
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
        case .suggestReading(let text):
            // Short selections only: a reading is for a word or phrase, and the tokenizer runs on the main thread.
            return text.count <= 80 ? JapaneseReading.hiragana(for: text) : nil
        }
        return nil
    }

    private func save(_ snapshot: Snapshot) {
        do {
            if try store?.saveContent(snapshot) == false {
                Log.warn("save skipped: document no longer exists", category: "store", context: ["docId": snapshot.docId])
            }
        } catch {
            Log.error("save failed: \(error)", category: "store", context: ["docId": snapshot.docId])
        }
    }

    fileprivate func webContentProcessDidTerminate() {
        Log.error("web content process terminated; reloading editor", category: "bridge", context: ["docId": currentDocumentID ?? "-"])
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
        do {
            let reply = try owner?.handle(try BridgeMessage.decode(scriptMessageBody: message.body))
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
        // Only the bundled editor may load in the web view (not an asset: an uploaded HTML file must never
        // become the page); links open in the system browser.
        if let url = navigationAction.request.url, url.scheme == EditorSchemeHandler.scheme {
            return url.host == "app" ? .allow : .cancel
        }
        if let url = navigationAction.request.url, navigationAction.navigationType == .linkActivated {
            #if os(iOS)
                await UIApplication.shared.open(url)
            #else
                NSWorkspace.shared.open(url)
            #endif
        }
        return .cancel
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Log.error("editor navigation failed: \(error)", category: "bridge")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Log.error("editor provisional navigation failed: \(error)", category: "bridge")
    }
}
