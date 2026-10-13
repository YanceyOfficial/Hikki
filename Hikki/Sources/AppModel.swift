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
    /// What the last pass over the workspace folder found (Settings → Storage shows it).
    private(set) var lastSync: SyncStatus?
    /// Why the folder isn't being synced at all (unresolvable bookmark, a failed first pass); nil while it works.
    private(set) var syncError: String?

    struct SyncStatus: Equatable, Sendable {
        var at: Date
        var report: WorkspaceSync.Report
    }

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
        startWorkspaceSync()
    }

    // MARK: Workspace folder (storage option C)

    @ObservationIgnored private var sync: WorkspaceSync?

    /// The folder the workspace lives in (access held for the session).
    @ObservationIgnored private var workspaceFolder: URL?
    /// `updatedAt` of the identity last read from or written to the folder: a newer one (another device
    /// renamed the workspace) replaces ours.
    @ObservationIgnored private var identityUpdatedAt: Date?

    /// The workspace folder is the source of truth: reconcile with it, then write every page change through.
    /// Access to a picked folder is held for the session. Runs once per launch (and after onboarding, or when
    /// the folder changes).
    func startWorkspaceSync() {
        guard let workspace, sync == nil else { return }
        let appRoot = workspaceStore.url.deletingLastPathComponent()
        do {
            let folder = try WorkspaceFolder.url(for: workspace, appRoot: appRoot)
            _ = folder.startAccessingSecurityScopedResource()  // released when the app quits or the folder changes
            workspaceFolder = folder
            syncIdentity()
            assets.useWorkspaceFolder(folder)
            let assets = assets
            Task.detached(priority: .utility) { assets.copyLegacyAssets() }
            // Every pass — launch, activation, or the folder watcher noticing another device — tells open
            // editors which pages came from disk, so one showing such a page reloads it.
            let sync = WorkspaceSync(store: store, files: PageFiles(root: folder)) { [weak self] report in
                let ids = report.importedIDs
                Task { @MainActor in
                    self?.lastSync = SyncStatus(at: .now, report: report)
                    guard !ids.isEmpty else { return }
                    NotificationCenter.default.post(name: .pagesChangedOnDisk, object: nil, userInfo: ["ids": ids])
                }
            }
            self.sync = sync
            Task.detached(priority: .utility) { [weak self] in
                do {
                    let report = try sync.start()
                    Self.log("workspace sync started", report)
                    Task { @MainActor in
                        self?.lastSync = SyncStatus(at: .now, report: report)
                        self?.syncError = nil
                    }
                } catch {
                    Log.error("workspace sync failed to start: \(error)", category: "workspace")
                    Task { @MainActor in self?.syncError = error.localizedDescription }
                }
            }
        } catch {
            Log.error("workspace folder unavailable: \(error)", category: "workspace")
            syncError = error.localizedDescription
        }
    }

    /// Settings → Storage → Change folder: the workspace moves to (or joins) another folder. Local pages are
    /// written there and the folder's pages imported; nothing is deleted on either side. A folder that already
    /// holds a workspace lends its name and icon.
    func changeLocation(to url: URL) throws {
        guard var workspace else { return }
        let bookmark = try FolderBookmark.make(for: url)
        workspace.location = .folder(bookmark: bookmark, displayName: FolderBookmark.displayName(for: url))
        sync?.stop()
        sync = nil
        workspaceFolder?.stopAccessingSecurityScopedResource()
        workspaceFolder = nil
        identityUpdatedAt = nil
        // Pages synced with the old folder aren't synced with this one: write them all out, import its own.
        try store.unmarkAllSynced()
        try workspaceStore.save(workspace)
        self.workspace = workspace
        Log.info("workspace location changed", category: "workspace")
        startWorkspaceSync()
    }

    /// Keeps the identity in the folder (`workspace.json`) and this device's record in step: a folder without
    /// one gets ours; a newer one — renamed or re-iconed on another device — replaces ours. Nothing is written
    /// while iCloud still has to deliver the folder's own.
    private func syncIdentity() {
        guard let workspace, let folder = workspaceFolder else { return }
        do {
            if let identity = try WorkspaceFolder.readIdentity(in: folder) {
                guard identity.updatedAt > (identityUpdatedAt ?? .distantPast) else { return }
                identityUpdatedAt = identity.updatedAt
                let joined = identity.applied(to: workspace)
                if joined != workspace {
                    try workspaceStore.save(joined)
                    self.workspace = joined
                    Log.info("workspace identity adopted from folder", category: "workspace")
                }
            } else if !WorkspaceFolder.identityIsDownloading(in: folder) {
                try writeIdentity()
            }
        } catch {
            Log.error("workspace identity sync failed: \(error)", category: "workspace")
        }
    }

    private func writeIdentity() throws {
        guard let workspace, let folder = workspaceFolder else { return }
        let identity = WorkspaceIdentity(workspace)
        try WorkspaceFolder.writeIdentity(identity, in: folder)
        identityUpdatedAt = identity.updatedAt
    }

    /// Picks up what other devices changed (app activation). Cheap when nothing did.
    func reconcileWorkspace() {
        guard let sync else { return }
        syncIdentity()
        Task.detached(priority: .utility) {
            do {
                Self.log("workspace reconciled", try sync.reconcile())
            } catch {
                Log.error("workspace reconcile failed: \(error)", category: "workspace")
            }
        }
    }

    /// Waits for queued file writes (before the app goes to the background).
    func flushWorkspace() {
        sync?.flush()
    }

    nonisolated private static func log(_ message: String, _ report: WorkspaceSync.Report) {
        Log.info(
            message, category: "workspace",
            context: [
                "imported": "\(report.imported)", "exported": "\(report.exported)", "deletedHere": "\(report.deletedHere)",
                "skippedFiles": "\(report.skippedFiles)",
            ])
    }

    func createWorkspace(name: String, location: Workspace.Location) {
        let workspace = Workspace(name: name, location: location)
        do {
            try workspaceStore.save(workspace)
            self.workspace = workspace
            let kind = if case .folder = location { "folder" } else { "device" }
            Log.info("workspace created", category: "workspace", context: ["location": kind])
            startWorkspaceSync()
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
            try writeIdentity()
            Log.info("workspace renamed", category: "workspace")
        } catch {
            Log.error("workspace save failed: \(error)", category: "workspace")
        }
    }

    /// Settings → General → Icon (nil: back to the name's initial).
    func setWorkspaceIcon(_ icon: WorkspaceIcon?) {
        guard var workspace, workspace.icon != icon else { return }
        workspace.icon = icon
        do {
            try workspaceStore.save(workspace)
            self.workspace = workspace
            try writeIdentity()
            Log.info(
                "workspace icon set", category: "workspace",
                context: ["kind": icon.map { if case .image = $0 { "image" } else { "emoji" } } ?? "none"])
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

    func setLocked(_ locked: Bool, id: String) {
        perform("set locked", id) { try store.setLocked(locked, for: id) }
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

    /// Home: this device's writing activity over the last `days` days, and the workspace's totals.
    func activity(days: Int) -> [DailyActivity] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
        return perform("load activity") { try store.activity(since: start) } ?? []
    }

    func stats() -> WorkspaceStats {
        perform("load stats") { try store.stats() } ?? WorkspaceStats(pages: 0, words: 0)
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

extension Notification.Name {
    /// Pages the workspace sync imported from the folder; `userInfo["ids"]` is `[String]`.
    static let pagesChangedOnDisk = Notification.Name("app.yancey.hikki.pagesChangedOnDisk")
}
