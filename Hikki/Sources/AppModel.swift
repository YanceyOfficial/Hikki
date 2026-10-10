import Foundation
import HikkiCore
import Observation

/// App-wide data shared by every window: the page tree, the trash, and page operations.
@Observable
final class AppModel {
    let store: DocumentStore
    let assets: AssetStore
    let crashReporter: CrashReporter
    private(set) var tree = PageTree([])
    private(set) var trash: [PageSummary] = []

    init(store: DocumentStore, assets: AssetStore, crashReporter: CrashReporter) {
        self.store = store
        self.assets = assets
        self.crashReporter = crashReporter
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

    func moveToTrash(id: String) {
        perform("move to trash", id) { try store.moveToTrash(id: id) }
    }

    func restore(id: String) {
        perform("restore", id) { try store.restore(id: id) }
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
