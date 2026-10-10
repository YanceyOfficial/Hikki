import HikkiCore
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

    init() {
        webView = makeWebView()
    }

    func attach(store: DocumentStore, assets: AssetStore) {
        self.store = store
        self.assets = assets
        schemeHandler.assets = assets
    }

    func open(documentID: String?) {
        Task { await load(documentID) }
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
            Log.info("editor ready", category: "bridge")
            let pending = pendingDocumentID ?? currentDocumentID
            pendingDocumentID = nil
            currentDocumentID = nil
            Task { await load(pending ?? nil) }
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
        webView.load(URLRequest(url: EditorSchemeHandler.entryURL))
        return webView
    }

    @ObservationIgnored private let navigationDelegate = NavigationDelegate()
    @ObservationIgnored private let uiDelegate = EditorUIDelegate()
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

/// `<input type="file">` (cover upload): iOS presents the system picker itself, but a macOS WKWebView
/// does nothing unless the UI delegate shows an open panel.
private final class EditorUIDelegate: NSObject, WKUIDelegate {
    #if os(macOS)
        func webView(
            _ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo
        ) async -> [URL]? {
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = parameters.allowsMultipleSelection
            panel.canChooseDirectories = false
            panel.allowedContentTypes = [.image]
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
        // Only the bundled editor may load in the web view; links open in the system browser.
        if navigationAction.request.url?.scheme == EditorSchemeHandler.scheme { return .allow }
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
