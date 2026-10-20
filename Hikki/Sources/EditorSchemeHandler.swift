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
        let isAsset = url.host == "assets"
        let file: URL?
        if isAsset {
            file = assets?.file(named: relative)
        } else if let root {
            let candidate = root.appending(path: relative.isEmpty ? "index.html" : relative).standardizedFileURL
            file = candidate.path.hasPrefix(root.standardizedFileURL.path) ? candidate : nil
        } else {
            fail(urlSchemeTask, "editor bundle missing — run `make editor`")
            return
        }
        guard let file, let handle = try? FileHandle(forReadingFrom: file),
            let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize
        else {
            fail(urlSchemeTask, "not found: \(url.absoluteString)")
            return
        }
        defer { try? handle.close() }
        let range = ByteRange.parse(urlSchemeTask.request.value(forHTTPHeaderField: "Range"), size: size)
        var headers = [
            "Content-Type": Self.mimeType(for: file, isAsset: isAsset),
            "Accept-Ranges": "bytes",
            "Content-Length": "\(range.count)",
        ]
        if isAsset {
            // Assets are data, never documents: even if loaded directly they get no scripts or plugins.
            headers["Content-Security-Policy"] = "sandbox; default-src 'none'"
            headers["X-Content-Type-Options"] = "nosniff"
            // The editor reads a drawing's pictures back with fetch (another host of the scheme: cross-origin). Only
            // the editor's own origin may — never a page embedded in it.
            headers["Access-Control-Allow-Origin"] = "\(Self.scheme)://app"
        }
        let partial = range.count != size
        if partial { headers["Content-Range"] = "bytes \(range.lowerBound)-\(range.upperBound - 1)/\(size)" }
        let response = HTTPURLResponse(url: url, statusCode: partial ? 206 : 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        urlSchemeTask.didReceive(response)
        // Streamed in chunks: a video isn't read into memory whole.
        do {
            try handle.seek(toOffset: UInt64(range.lowerBound))
            var remaining = range.count
            while remaining > 0 {
                let chunk = try handle.read(upToCount: min(remaining, 1 << 20)) ?? Data()
                if chunk.isEmpty { break }
                urlSchemeTask.didReceive(chunk)
                remaining -= chunk.count
            }
            urlSchemeTask.didFinish()
        } catch {
            fail(urlSchemeTask, "read failed: \(url.lastPathComponent)")
        }
    }

    /// Media and images by type; any other asset (an attachment) as inert bytes.
    static func mimeType(for file: URL, isAsset: Bool) -> String {
        let type = UTType(filenameExtension: file.pathExtension)
        if isAsset, let kind = AssetStore.kind(ofExtension: file.pathExtension), kind == .file {
            return "application/octet-stream"
        }
        return type?.preferredMIMEType ?? "application/octet-stream"
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}

    private func fail(_ task: any WKURLSchemeTask, _ reason: String) {
        Log.error("scheme handler: \(reason)", category: "bridge")
        task.didFailWithError(URLError(.fileDoesNotExist))
    }
}
