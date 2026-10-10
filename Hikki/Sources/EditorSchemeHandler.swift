import HikkiCore
import UniformTypeIdentifiers
import WebKit

/// Serves the bundled editor (Resources/Editor, built by vite) from `hikki-editor://app/`, and user
/// assets (covers, images) from `hikki-editor://assets/<name>`.
/// A custom scheme gives the page a stable origin without file:// quirks.
final class EditorSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "hikki-editor"
    static let entryURL = URL(string: "\(scheme)://app/index.html")!

    private let root: URL? = Bundle.main.url(forResource: "Editor", withExtension: nil)
    var assets: AssetStore?

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else { return }
        let relative = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let file: URL?
        if url.host == "assets" {
            file = assets?.file(named: relative)
        } else if let root {
            let candidate = root.appending(path: relative.isEmpty ? "index.html" : relative).standardizedFileURL
            file = candidate.path.hasPrefix(root.standardizedFileURL.path) ? candidate : nil
        } else {
            fail(urlSchemeTask, "editor bundle missing — run `make editor`")
            return
        }
        guard let file, let data = try? Data(contentsOf: file) else {
            fail(urlSchemeTask, "not found: \(url.absoluteString)")
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
