import HikkiCore
import Observation
import WebKit

/// Owns one long-lived WKWebView running the Tiptap bundle and mediates every bridge call.
/// Documents are swapped in place (`hikki.loadDocument`) instead of recreating the web view.
@Observable
final class EditorController {
    private(set) var isReady = false
    private(set) var activeFormats: Set<String> = []
    @ObservationIgnored private(set) var webView: HikkiWebView!
    @ObservationIgnored private var store: DocumentStore?
    @ObservationIgnored private var currentDocumentID: String?
    @ObservationIgnored private var pendingDocumentID: String??

    init() {
        webView = makeWebView()
    }

    func attach(store: DocumentStore) {
        self.store = store
    }

    func open(documentID: String?) {
        Task { await load(documentID) }
    }

    func exec(_ command: EditorCommand) {
        guard isReady else { return }
        Task {
            do {
                _ = try await webView.callAsyncJavaScript("return window.hikki.exec(command)", arguments: ["command": command.rawValue], contentWorld: .page)
            } catch {
                Log.error("exec failed: \(error)", category: "bridge", context: ["command": command.rawValue])
            }
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
            let content: Any = try record.contentValue()?.foundationObject() ?? NSNull()
            _ = try await webView.callAsyncJavaScript(
                "window.hikki.loadDocument(doc); window.hikki.focus()",
                arguments: ["doc": ["id": id, "content": content]],
                contentWorld: .page
            )
        } catch {
            Log.error("load failed: \(error)", category: "bridge", context: ["docId": id])
        }
    }

    // MARK: - Bridge

    func handle(_ message: BridgeMessage) {
        switch message {
        case .ready(let version):
            guard version == BridgeProtocol.version else {
                Log.error("bridge protocol mismatch", category: "bridge", context: ["web": "\(version)", "native": "\(BridgeProtocol.version)"])
                return
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
        }
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

    private func makeWebView() -> HikkiWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(EditorSchemeHandler(), forURLScheme: EditorSchemeHandler.scheme)
        configuration.userContentController.addScriptMessageHandler(
            ScriptMessageProxy(owner: self), contentWorld: .page, name: "hikki"
        )
        let webView = HikkiWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = navigationDelegate
        navigationDelegate.owner = self
        #if DEBUG
            webView.isInspectable = true
        #endif
        #if os(iOS)
            webView.installKeyboardToolbar(controller: self)
        #endif
        webView.load(URLRequest(url: EditorSchemeHandler.entryURL))
        return webView
    }

    @ObservationIgnored private let navigationDelegate = NavigationDelegate()
}

/// WKUserContentController retains its handlers; this proxy keeps the controller weakly referenced.
private final class ScriptMessageProxy: NSObject, WKScriptMessageHandlerWithReply {
    weak var owner: EditorController?

    init(owner: EditorController) {
        self.owner = owner
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) async -> (Any?, String?) {
        do {
            owner?.handle(try BridgeMessage.decode(scriptMessageBody: message.body))
            return (nil, nil)
        } catch {
            Log.error("undecodable bridge message: \(error)", category: "bridge")
            return (nil, "\(error)")
        }
    }
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
