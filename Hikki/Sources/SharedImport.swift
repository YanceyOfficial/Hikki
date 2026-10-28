import Foundation
import HikkiCore

/// "Save to Hikki" on the website (ISSUE-224): `hikki://shared/<record>[#<key>]` opens the app, which reads the
/// published page from the public database (`PagePublisher.fetchShared`), lays it out as a document with its
/// attachments in a temporary folder — the HTML and `assets/<name>`, as an export is — and imports it as a new
/// top-level page the way File → Import does, then gives it the published cover.
extension AppModel {
    /// Saves a copy of the shared page and returns its id, nil after a failure (a toast).
    func saveSharedPage(_ target: SharedLink.Target, editor: EditorController) async -> String? {
        guard Purchases.shared.allowsWriting() else { return nil }
        let folder = FileManager.default.temporaryDirectory.appending(path: "hikki-shared-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            let shared = try await publisher.fetchShared(recordName: target.recordName, key: target.key)
            let assetsFolder = folder.appending(path: "assets")
            try FileManager.default.createDirectory(at: assetsFolder, withIntermediateDirectories: true)
            for file in shared.files where Self.isSafeAssetName(file.name) {
                try file.data.write(to: assetsFolder.appending(path: file.name), options: .atomic)
            }
            let document = folder.appending(path: "shared.html")
            try Self.sharedDocument(shared.payload).write(to: document, atomically: true, encoding: .utf8)
            guard let id = await importFiles([document], editor: editor).first else {
                Toasts.report(.sharedImportFailed, CocoaError(.fileReadCorruptFile), category: "publish")
                return nil
            }
            let cover = shared.payload.cover?.stored { name in
                guard Self.isSafeAssetName(name) else { return nil }
                let source = assetsFolder.appending(path: name)
                guard FileManager.default.fileExists(atPath: source.path()) else { return nil }
                return try? assets.importCopy(of: source)
            }
            if let cover { try? store.setCover(cover, for: id) }
            Log.info("shared page saved", category: "publish", context: ["files": "\(shared.files.count)"])
            Toasts.shared.show(.success, String(localized: "app:shared.saved"))
            return id
        } catch PagePublisher.FetchError.notFound {
            Toasts.report(.sharedPageNotFound, PagePublisher.FetchError.notFound, category: "publish")
        } catch PagePublisher.FetchError.cannotOpen {
            Toasts.report(.sharedPageCannotOpen, PagePublisher.FetchError.cannotOpen, category: "publish")
        } catch {
            Toasts.report(.sharedImportFailed, error, category: "publish")
        }
        return nil
    }

    /// An attachment's name as the payload gives it may only name a file in `assets/` — letters, digits, `.`, `-`, `_`,
    /// not hidden.
    static func isSafeAssetName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 200 && !name.hasPrefix(".")
            && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_") }
    }

    /// The page as an HTML document the import reads: its title as the document's (the import names the page by
    /// it), the exported body as published.
    static func sharedDocument(_ payload: PublishedPayload) -> String {
        let title = payload.title
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return "<!doctype html><html><head><meta charset=\"utf-8\"><title>\(title)</title></head><body>\(payload.html)</body></html>"
    }
}
