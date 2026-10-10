import Foundation
import HikkiCore
import Observation

/// App-wide data shared by every window: the page tree, the trash, and page operations.
@Observable
final class AppModel {
    let store: DocumentStore
    let assets: AssetStore
    let crashReporter: CrashReporter
    let workspaceStore: WorkspaceStore
    /// nil until onboarding creates one (first launch).
    private(set) var workspace: Workspace?
    private(set) var tree = PageTree([])
    private(set) var trash: [PageSummary] = []

    init(store: DocumentStore, assets: AssetStore, crashReporter: CrashReporter, workspaceStore: WorkspaceStore) {
        self.store = store
        self.assets = assets
        self.crashReporter = crashReporter
        self.workspaceStore = workspaceStore
        do {
            workspace = try workspaceStore.load()
        } catch {
            Log.error("workspace load failed: \(error)", category: "workspace")
        }
    }

    func createWorkspace(name: String, location: Workspace.Location) {
        let workspace = Workspace(name: name, location: location)
        do {
            try workspaceStore.save(workspace)
            self.workspace = workspace
            let kind = if case .folder = location { "folder" } else { "device" }
            Log.info("workspace created", category: "workspace", context: ["location": kind])
        } catch {
            Log.error("workspace save failed: \(error)", category: "workspace")
        }
    }

    /// Renames the workspace; blank names are ignored. The location binding is untouched.
    func renameWorkspace(_ raw: String) {
        guard var workspace, let name = Workspace.normalizedName(raw), name != workspace.name else { return }
        workspace.name = name
        do {
            try workspaceStore.save(workspace)
            self.workspace = workspace
            Log.info("workspace renamed", category: "workspace")
        } catch {
            Log.error("workspace save failed: \(error)", category: "workspace")
        }
    }

    /// Keeps `tree` and `trash` in sync with the database for the lifetime of the calling task.
    func observe() async {
        await withDiscardingTaskGroup { group in
            group.addTask { await self.observePages() }
            group.addTask { await self.observeTrash() }
        }
    }

    private func observePages() async {
        do {
            for try await pages in store.observePages() { tree = PageTree(pages) }
        } catch {
            Log.error("page observation failed: \(error)", category: "store")
        }
    }

    private func observeTrash() async {
        do {
            for try await pages in store.observeTrash() { trash = pages }
        } catch {
            Log.error("trash observation failed: \(error)", category: "store")
        }
    }

    // MARK: - Page operations (errors are logged; the UI keeps showing the last good state)

    func createPage(parentId: String? = nil) -> String? {
        perform("create page") { try store.create(parentId: parentId).id }
    }

    func setFavorite(_ favorite: Bool, id: String) {
        perform("set favorite", id) { try store.setFavorite(favorite, for: id) }
    }

    func duplicate(id: String) {
        perform("duplicate", id) { try store.duplicate(id: id) }
    }

    func moveToTrash(id: String) {
        perform("move to trash", id) { try store.moveToTrash(id: id) }
    }

    func restore(id: String) {
        perform("restore", id) { try store.restore(id: id) }
    }

    /// Sidebar drag and drop. Returns false when the drop is invalid (onto itself / its own subtree).
    @discardableResult
    func movePage(_ dragged: String, onto target: String, zone: DropZone) -> Bool {
        guard let destination = tree.destination(dropping: dragged, onto: target, zone: zone) else { return false }
        return perform("move page", dragged) { try store.move(id: dragged, toParent: destination.parentId, at: destination.index) } != nil
    }

    /// Drop onto a section header: to the end of the top level.
    @discardableResult
    func movePageToTopLevel(_ dragged: String) -> Bool {
        perform("move page", dragged) { try store.move(id: dragged, toParent: nil, at: .max) } != nil
    }

    func deletePermanently(id: String) {
        perform("delete permanently", id) { try store.deletePermanently(id: id) }
    }

    func emptyTrash() {
        perform("empty trash") { try store.emptyTrash() }
    }

    func search(_ query: String) -> [SearchHit] {
        perform("search") { try store.search(query) } ?? []
    }

    var exportableFiles: [URL] {
        Log.files + crashReporter.reports
    }

    @discardableResult
    private func perform<T>(_ action: String, _ id: String? = nil, _ body: () throws -> T) -> T? {
        do {
            return try body()
        } catch {
            Log.error("\(action) failed: \(error)", category: "store", context: id.map { ["docId": $0] })
            return nil
        }
    }
}
