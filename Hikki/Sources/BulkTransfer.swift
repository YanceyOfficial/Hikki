import HikkiCore
import Observation
import SwiftUI

/// Bulk import and export (Settings → Workspace → Import & Export): many files and folders in as a page tree, or the
/// whole workspace out as a folder. One job at a time per app; it runs on as Settings closes and reports progress
/// (`progress`) and an ending (`summary`, `onFinish`). The planning and file work is HikkiCore's
/// (`WorkspaceImport` / `WorkspaceExport`); Markdown and HTML go through a window's editor, one page at a time —
/// any window's: the conversions don't touch the page it shows.
@Observable
final class BulkTransfer {
    enum Kind: Equatable {
        case importing, exporting
    }

    struct Progress: Equatable {
        var kind: Kind
        var done: Int
        /// 0 while the files are still being listed.
        var total: Int
    }

    struct Summary: Equatable, Identifiable {
        let id = UUID()
        var kind: Kind
        /// Pages imported or exported.
        var count: Int
        /// Files (import) or pages (export) left out, with why.
        var skipped: [WorkspaceImport.Skipped]
        var cancelled = false
        /// The job couldn't run at all (no editor to convert with, the folder can't be written).
        var failed = false
        /// The export's folder.
        var destination: URL?
    }

    private(set) var progress: Progress?
    private(set) var summary: Summary?
    var isRunning: Bool { progress != nil }

    /// Hears every ending — the app's notifications can tell the user about it away from Settings.
    @ObservationIgnored var onFinish: ((Summary) -> Void)?

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var editors: [WeakEditor] = []
    @ObservationIgnored private var debugHooksRan = false

    private struct WeakEditor {
        weak var editor: EditorController?
    }

    /// A window's editor, for converting Markdown / HTML. ContentView registers each window's.
    func register(_ editor: EditorController, model: AppModel) {
        editors.removeAll { $0.editor == nil || $0.editor === editor }
        editors.append(WeakEditor(editor: editor))
        #if DEBUG
            runDebugHooks(editor: editor, model: model)
        #endif
    }

    private var converter: EditorController? { editors.lazy.compactMap(\.editor).first { $0.isReady } }

    func cancel() {
        task?.cancel()
    }

    func dismissSummary() {
        summary = nil
    }

    enum TransferError: Error {
        case noEditor
        case pageMissing
    }

    // MARK: - Import

    /// Imports the chosen files and folders as pages at the top level (see `WorkspaceImport`).
    func startImport(_ urls: [URL], model: AppModel) {
        guard !isRunning else { return }
        summary = nil
        progress = Progress(kind: .importing, done: 0, total: 0)
        Log.info("bulk import started", category: "import", context: ["selected": "\(urls.count)"])
        task = Task {
            let scoped = urls.map { $0.startAccessingSecurityScopedResource() }
            defer { for (url, on) in zip(urls, scoped) where on { url.stopAccessingSecurityScopedResource() } }
            // Listing folders and reading page files' headers is file work: off the main thread.
            let plan = await Task.detached(priority: .userInitiated) { WorkspaceImport.plan(urls) }.value
            progress?.total = plan.items.count
            var result = Summary(kind: .importing, count: 0, skipped: plan.skipped)
            // Every page's id is settled first, so each body can link the others under their ids here.
            let store = model.store
            // A page in the trash holds its id too; a store that can't say counts as holding it.
            let (ids, links) = WorkspaceImport.assignIDs(plan.items) { id in
                do { return try store.hasDocument(matching: id) } catch { return true }
            }
            var created: [String?] = []
            for (index, item) in plan.items.enumerated() {
                if Task.isCancelled {
                    result.cancelled = true
                    break
                }
                // Under the page its folder made; at the top when that one couldn't be made.
                let parent = item.parent.flatMap { created[$0] }
                do {
                    created.append(try await importItem(item, id: ids[index], parentId: parent, links: links, model: model))
                    result.count += 1
                } catch {
                    created.append(nil)
                    result.skipped.append(Self.skipped(item, error: error))
                    Log.error("bulk import item failed: \(error)", category: "import", context: ["index": "\(created.count - 1)"])
                }
                progress?.done += 1
                await Task.yield()
            }
            finish(result)
            // The folders chosen zips were unpacked into.
            let folders = plan.temporaryFolders
            if !folders.isEmpty {
                Task.detached(priority: .utility) { for folder in folders { try? FileManager.default.removeItem(at: folder) } }
            }
        }
    }

    private func importItem(
        _ item: WorkspaceImport.Item, id: String, parentId: String?, links: [String: String], model: AppModel
    ) async throws -> String {
        switch item.source {
        case .document(let url, _):
            guard let editor = converter else { throw TransferError.noEditor }
            return try await model.importConverted(url, root: item.root, id: id, parentId: parentId, links: links, editor: editor)
        case .pageFile(let url):
            return try WorkspaceImport.importPageFile(
                at: url, root: item.root, id: id, parentId: parentId, links: links, store: model.store, assets: model.assets)
        case .folder(let name):
            return try WorkspaceImport.createFolderPage(named: name, id: id, parentId: parentId, store: model.store)
        }
    }

    private static func skipped(_ item: WorkspaceImport.Item, error: any Error) -> WorkspaceImport.Skipped {
        let name =
            switch item.source {
            case .document(let url, _), .pageFile(let url): url.lastPathComponent
            case .folder(let name): name
            }
        if case AppModel.ImportError.tooLarge = error { return .init(name: name, reason: .tooLarge) }
        if let error = error as? PageFiles.PageFileError, case .unsupportedFormat = error { return .init(name: name, reason: .newerFormat) }
        return .init(name: name, reason: .failed)
    }

    // MARK: - Export

    /// Writes every live page into a new folder inside `destination` (see `WorkspaceExport`).
    func startExport(_ format: WorkspaceExport.Format, to destination: URL, model: AppModel) {
        guard !isRunning else { return }
        summary = nil
        progress = Progress(kind: .exporting, done: 0, total: 0)
        Log.info("bulk export started", category: "export", context: ["format": format.rawValue])
        task = Task {
            let scoped = destination.startAccessingSecurityScopedResource()
            defer { if scoped { destination.stopAccessingSecurityScopedResource() } }
            var result = Summary(kind: .exporting, count: 0, skipped: [])
            let untitled = String(localized: "app:page.untitled")
            let folder: URL
            let entries: [WorkspaceExport.Entry]
            do {
                // Unsaved typing goes in first.
                for editor in editors.compactMap(\.editor) { await editor.flush(reason: "export") }
                folder = try WorkspaceExport.makeFolder(in: destination, workspace: model.workspace?.name ?? "Hikki")
                entries = WorkspaceExport.plan(try model.store.pages(), fileExtension: format.fileExtension, fallback: untitled)
                if format != .json, converter == nil { throw TransferError.noEditor }
            } catch {
                Log.error("bulk export failed: \(error)", category: "export")
                result.failed = true
                finish(result)
                return
            }
            result.destination = folder
            progress?.total = entries.count
            var copied = Set<String>()
            for entry in entries {
                if Task.isCancelled {
                    result.cancelled = true
                    break
                }
                do {
                    let (data, names) = try await document(for: entry, format: format, model: model)
                    let fresh = names.filter { copied.insert($0).inserted }
                    let assets = model.assets
                    // Writing and copying attachments (videos can be large) happen off the main thread.
                    try await Task.detached(priority: .userInitiated) {
                        try WorkspaceExport.write(data, entry: entry, in: folder)
                        for name in fresh { _ = try? WorkspaceExport.copyAsset(name, from: assets, to: folder) }
                    }.value
                    result.count += 1
                } catch {
                    let title = model.tree.page(entry.id)?.title ?? ""
                    result.skipped.append(.init(name: title.isEmpty ? untitled : title, reason: .failed))
                    Log.error("bulk export page failed: \(error)", category: "export", context: ["docId": entry.id])
                }
                progress?.done += 1
                await Task.yield()
            }
            finish(result)
        }
    }

    private func document(for entry: WorkspaceExport.Entry, format: WorkspaceExport.Format, model: AppModel) async throws -> (
        data: Data, assets: [String]
    ) {
        guard let record = try model.store.document(id: entry.id) else { throw TransferError.pageMissing }
        switch format {
        case .json:
            return try WorkspaceExport.pageFile(record)
        case .markdown, .html:
            guard let editor = converter else { throw TransferError.noEditor }
            let text = try await editor.exportText(record, format: format == .markdown ? .markdown : .html)
            return WorkspaceExport.document(text: text, entry: entry, format: format)
        }
    }

    private func finish(_ result: Summary) {
        progress = nil
        task = nil
        summary = result
        Log.info(
            "bulk transfer finished", category: result.kind == .importing ? "import" : "export",
            context: [
                "count": "\(result.count)", "skipped": "\(result.skipped.count)", "cancelled": "\(result.cancelled)",
                "failed": "\(result.failed)",
            ])
        onFinish?(result)
    }

    // MARK: - Debug

    #if DEBUG
        /// `HIKKI_BULK_IMPORT=<path>|<path>…` imports those files / folders, `HIKKI_BULK_EXPORT=<format>|<folder>`
        /// exports the workspace into that folder — once the editor is up (UI tests: the pickers run out of process).
        private func runDebugHooks(editor: EditorController, model: AppModel) {
            let environment = ProcessInfo.processInfo.environment
            guard !debugHooksRan, environment["HIKKI_BULK_IMPORT"] != nil || environment["HIKKI_BULK_EXPORT"] != nil else { return }
            debugHooksRan = true
            Task {
                for _ in 0..<150 where !editor.isReady { try? await Task.sleep(for: .milliseconds(100)) }
                if let paths = environment["HIKKI_BULK_IMPORT"] {
                    startImport(paths.split(separator: "|").map { URL(filePath: String($0)) }, model: model)
                    while isRunning { try? await Task.sleep(for: .milliseconds(100)) }
                }
                if let value = environment["HIKKI_BULK_EXPORT"] {
                    let parts = value.split(separator: "|", maxSplits: 1).map(String.init)
                    if parts.count == 2, let format = WorkspaceExport.Format(rawValue: parts[0]) {
                        startExport(format, to: URL(filePath: parts[1]), model: model)
                    }
                }
            }
        }
    #endif
}
