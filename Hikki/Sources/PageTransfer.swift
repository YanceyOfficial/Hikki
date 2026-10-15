import HikkiCore
import SwiftUI
import UniformTypeIdentifiers
import WebKit

// Page history (restoring a version), import and export: the app's side. The conversions run in the editor
// (editor/src/core/convert.ts), packing and history in HikkiCore (PageExport, PageHistory).

extension AppModel {
    // MARK: - History

    /// The page's kept versions, newest first.
    func versions(of pageID: String) -> [PageVersion] {
        guard let history else { return [] }
        do {
            return try history.versions(of: pageID)
        } catch {
            Log.error("page versions unreadable: \(error)", category: "history", context: ["docId": pageID])
            return []
        }
    }

    /// Puts a version back as the page (title, body, icon, cover). Editors showing the page hand over their unsaved
    /// edits first, and the page as it is now is kept as a version — restoring can itself be undone from the history.
    func restore(_ version: PageVersion, editors: [EditorController]) async {
        let id = version.pageId
        for editor in editors { await editor.flush(reason: "restore") }
        do {
            guard let current = try store.document(id: id) else { return }
            if let history { try history.snapshot(current, reason: .restore) }
            let content =
                version.content ?? .object(["type": .string("doc"), "content": .array([.object(["type": .string("paragraph")])])])
            try store.saveContent(
                Snapshot(docId: id, content: content, title: version.title, text: version.plainText, wordCount: version.wordCount))
            if current.icon != version.icon { try store.setIcon(version.icon, for: id) }
            if current.cover != version.cover { try store.setCover(version.cover, for: id) }
            Log.info("page version restored", category: "history", context: ["docId": id])
            // Every editor showing the page shows the restored version.
            NotificationCenter.default.post(name: .pageSavedInEditor, object: nil, userInfo: ["id": id])
        } catch {
            Toasts.report(.historyRestoreFailed, error, category: "history", context: ["docId": id])
        }
    }

    // MARK: - Import

    /// Files larger than this aren't read as text.
    nonisolated static let importLimit = 20 * 1024 * 1024

    /// Each Markdown / HTML / text file as a new page at the top level, or as the last children of `parentId` (files
    /// dropped on a sidebar row), converted by the editor — and for a chosen
    /// folder, each such file in it. Pictures and attachments a document links by relative path inside its folder (an
    /// export's `assets/`) come along into the workspace's assets. Returns the new pages' ids in order.
    func importFiles(_ urls: [URL], parentId: String? = nil, editor: EditorController) async -> [String] {
        var created: [String] = []
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            for file in await Self.documents(at: url) {
                if let id = await importDocument(file, parentId: parentId, editor: editor) { created.append(id) }
            }
        }
        return created
    }

    private func importDocument(_ url: URL, parentId: String?, editor: EditorController) async -> String? {
        do {
            return try await importConverted(url, parentId: parentId, editor: editor)
        } catch {
            let code: ErrorCode = (error as? ImportError) == .tooLarge ? .fileTooLarge : .importFailed
            Toasts.report(code, error, category: "import", context: ["extension": url.pathExtension.lowercased()])
            return nil
        }
    }

    nonisolated enum ImportError: Error {
        case tooLarge
    }

    /// A file, or the documents in a folder (listed off the main thread: a big folder takes a while).
    @concurrent nonisolated private static func documents(at url: URL) async -> [URL] {
        let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        return isFolder ? PageImport.documents(in: url) : [url]
    }

    /// The file's text, read off the main thread (up to `importLimit`, 20 MB).
    @concurrent nonisolated private static func readText(_ url: URL) async throws -> (text: String, bytes: Int) {
        let data = try Data(contentsOf: url)
        guard data.count <= importLimit else {
            Log.warn("import skipped: file too large", category: "import", context: ["bytes": "\(data.count)"])
            throw ImportError.tooLarge
        }
        return (String(decoding: data, as: UTF8.self), data.count)
    }

    /// The files a document links relatively, copied into the workspace's assets off the main thread; the content
    /// pointing at the copies.
    @concurrent nonisolated private static func relink(
        _ content: JSONValue, base: URL, root: URL?, assets: AssetStore
    ) async -> (content: JSONValue, copied: Int) {
        PageImport.relinkLocalFiles(in: content, base: base, root: root) { file in try assets.importCopy(of: file) }
    }

    /// One Markdown / HTML / text file as a new page under `parentId`, converted by the editor. Files it links
    /// relatively come along when they are inside `root` (the folder the user chose; the file's own folder when nil).
    func importConverted(_ url: URL, root: URL? = nil, parentId: String?, editor: EditorController) async throws -> String {
        let format = ImportFormat(fileExtension: url.pathExtension) ?? .text
        let (text, bytes) = try await Self.readText(url)
        // Only the conversion runs on the main thread (in the editor's web view).
        let page = try await editor.importDocument(text, format: format, fallbackTitle: url.deletingPathExtension().lastPathComponent)
        // Pictures beside the document (inside the chosen folder only) become the page's own.
        let (content, copied) = await Self.relink(page.content, base: url.deletingLastPathComponent(), root: root, assets: assets)
        let record = try store.create(parentId: parentId)
        try store.saveContent(
            Snapshot(docId: record.id, content: content, title: page.title, text: page.text, wordCount: page.wordCount))
        Log.info(
            "page imported", category: "import",
            context: ["docId": record.id, "format": format.rawValue, "bytes": "\(bytes)", "files": "\(copied)"])
        return record.id
    }

    // MARK: - Export

    /// The page in `format`, packed for saving: one file, or a folder with its attachments (see `PageExport`).
    func exportPackage(_ request: ExportRequest, editor: EditorController) async throws -> ExportFile {
        await editor.flush(reason: "export")
        guard let record = try store.document(id: request.pageID) else { throw ExportError.pageMissing }
        let name = PageExport.fileName(for: record.title, fallback: String(localized: "app:page.untitled"))
        switch request.format {
        case .json:
            return ExportFile(
                wrapper: PageExport.package(document: try PageExport.json(record), name: name, fileExtension: "json", assets: []),
                format: .json)
        case .markdown, .html:
            let text = try await editor.exportText(record, format: request.format == .markdown ? .markdown : .html)
            let (relinked, names) = PageExport.relinkAssets(in: text)
            let files = names.compactMap { name in assets.file(named: name).map { (name: name, file: $0) } }
            let wrapper = PageExport.package(
                document: Data(relinked.utf8), name: name, fileExtension: request.format.fileExtension, assets: files)
            return ExportFile(wrapper: wrapper, format: request.format)
        case .pdf:
            let html = try await editor.exportText(record, format: .html)
            let pdf = try await PDFExporter.render(html: html, assets: assets)
            return ExportFile(wrapper: PageExport.package(document: pdf, name: name, fileExtension: "pdf", assets: []), format: .pdf)
        }
    }

    enum ExportError: Error {
        case pageMissing
    }
}

/// An export, for `.fileExporter`: a single file or a folder (the page's document and its `assets/`).
struct ExportFile: FileDocument, @unchecked Sendable {
    static let readableContentTypes: [UTType] = [.data]
    /// The save panel only writes a type the document declares: with just `.data` (the default, from the readable
    /// types) it saved the file without an extension.
    static var writableContentTypes: [UTType] { PageExport.writableContentTypes }
    let wrapper: FileWrapper
    let format: PageExport.Format

    init(wrapper: FileWrapper, format: PageExport.Format) {
        self.wrapper = wrapper
        self.format = format
    }

    init(configuration: ReadConfiguration) throws {
        wrapper = configuration.file
        format = .json
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { wrapper }

    /// What the save panel offers: a folder, or the document's own type.
    var contentType: UTType { wrapper.isDirectory ? .folder : format.contentType }

    /// The name the save panel starts with (without the extension it adds itself).
    var defaultFilename: String {
        let name = wrapper.preferredFilename ?? ""
        return wrapper.isDirectory ? name : (name as NSString).deletingPathExtension
    }
}

/// Renders an exported HTML page to PDF in an offscreen web view (light, unstyled by the app: the export's own
/// minimal stylesheet), with its attachments beside it so pictures show. One tall page — WebKit's `createPDF`.
@MainActor
enum PDFExporter {
    static func render(html: String, assets: AssetStore) async throws -> Data {
        let folder = FileManager.default.temporaryDirectory.appending(
            path: "hikki-export-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder.appending(path: "assets"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let (relinked, names) = PageExport.relinkAssets(in: html)
        for name in names {
            if let file = assets.file(named: name) {
                try? FileManager.default.copyItem(at: file, to: folder.appending(path: "assets/\(name)"))
            }
        }
        let page = folder.appending(path: "page.html")
        try Data(relinked.utf8).write(to: page)
        let configuration = WKWebViewConfiguration()
        // Nothing runs in the export: it is a document to print, not a page.
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 794, height: 1123), configuration: configuration)  // A4 at 96 dpi
        #if os(iOS)
            webView.overrideUserInterfaceStyle = .light
        #else
            webView.appearance = NSAppearance(named: .aqua)
        #endif
        let loader = Loader()
        webView.navigationDelegate = loader
        try await loader.load(page, in: webView, readAccess: folder)
        return try await webView.pdf()
    }

    private final class Loader: NSObject, WKNavigationDelegate {
        private var continuation: CheckedContinuation<Void, any Error>?

        func load(_ url: URL, in webView: WKWebView, readAccess: URL) async throws {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                webView.loadFileURL(url, allowingReadAccessTo: readAccess)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            continuation?.resume()
            continuation = nil
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            continuation?.resume(throwing: error)
            continuation = nil
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
            continuation?.resume(throwing: error)
            continuation = nil
        }

        /// Only the export itself loads; links in it don't navigate.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            navigationAction.request.url?.isFileURL == true ? .allow : .cancel
        }
    }
}
