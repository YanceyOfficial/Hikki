import HikkiCore
import UniformTypeIdentifiers
import WebKit

/// Serves the bundled editor (Resources/Editor, built by vite) from `hikki-editor://app/`.
/// A custom scheme gives the page a stable origin without file:// quirks.
final class EditorSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "hikki-editor"
    static let entryURL = URL(string: "\(scheme)://app/index.html")!

    private let root: URL? = Bundle.main.url(forResource: "Editor", withExtension: nil)

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, let root else {
            fail(urlSchemeTask, "editor bundle missing — run `make editor`")
            return
        }
        let relative = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let file = root.appending(path: relative.isEmpty ? "index.html" : relative).standardizedFileURL
        guard file.path.hasPrefix(root.standardizedFileURL.path), let data = try? Data(contentsOf: file) else {
            fail(urlSchemeTask, "not found: \(url.path)")
            return
        }
        let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
            "Content-Type": mime,
            "Content-Length": "\(data.count)",
        ])!
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}

    private func fail(_ task: any WKURLSchemeTask, _ reason: String) {
        Log.error("scheme handler: \(reason)", category: "bridge")
        task.didFailWithError(URLError(.fileDoesNotExist))
    }
}
