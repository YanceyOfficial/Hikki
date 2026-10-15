import Foundation
import HikkiCore
import HikkiSearch
import Observation

#if os(iOS)
    import UIKit
#endif

/// App-wide data shared by every window: the page tree, the trash, and page operations.
@Observable
final class AppModel {
    let store: DocumentStore
    let searchIndexer: SearchIndexer
    let assets: AssetStore
    let crashReporter: CrashReporter
    let workspaceStore: WorkspaceStore
    /// Settings → Import & Export: the bulk import / export job (BulkTransfer.swift).
    let bulkTransfer = BulkTransfer()
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

    init(
        store: DocumentStore, searchIndex: SearchIndex, assets: AssetStore, crashReporter: CrashReporter,
        workspaceStore: WorkspaceStore
    ) {
        self.store = store
        self.searchIndexer = SearchIndexer(index: searchIndex, store: store, assets: assets)
        // Semantic search was removed (2026-10-15): its settings go too.
        for key in ["semantic.enabled", "semantic.endpoint", "semantic.model"] { UserDefaults.standard.removeObject(forKey: key) }
        self.assets = assets
        self.crashReporter = crashReporter
        self.workspaceStore = workspaceStore
        bulkTransfer.onFinish = Self.announce
        do {
            workspace = try workspaceStore.load()
        } catch {
            Toasts.report(.workspaceOpenFailed, error, category: "workspace")
        }
        startWorkspaceSync()
        searchIndexer.start()
        purgeTrash()
        // One observation for the app (every window reads the same tree): it was a task per window, each writing it.
        observation = Task { [weak self] in await self?.observe() }
        Self.current = self
    }

    /// The app's model, for what has no window to ask (quitting: `AppDelegate`).
    static weak var current: AppModel?
    @ObservationIgnored private var observation: Task<Void, Never>?

    // MARK: Workspace folder (storage option C)

    @ObservationIgnored private var sync: WorkspaceSync?
    /// Versions of pages (Page ⋯ → Page History…), in the workspace folder; nil until the folder is known.
    @ObservationIgnored private(set) var history: PageHistory?
    /// Comment threads (`comments/<page id>.json`), in the folder too so they sync with the pages.
    @ObservationIgnored private(set) var comments: PageComments?

    /// Notion-like: a version per editing session (10 quiet minutes apart), all of the last day, then one a day for
    /// 30 days. DEBUG: `HIKKI_HISTORY_INTERVAL=<seconds>` shortens the session (UI tests).
    static var historyPolicy: PageHistoryPolicy {
        var policy = PageHistoryPolicy()
        #if DEBUG
            if let value = ProcessInfo.processInfo.environment["HIKKI_HISTORY_INTERVAL"], let seconds = TimeInterval(value) {
                policy.interval = seconds
            }
        #endif
        return policy
    }

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
            // Page history lives in the folder too (`history/<page id>/`), so versions sync with the pages.
            let history = PageHistory(root: folder, policy: Self.historyPolicy, device: Self.deviceName)
            self.history = history
            comments = PageComments(root: folder, author: Self.authorName, device: Self.deviceKind)
            // Every pass — launch, activation, or the folder watcher noticing another device — tells open
            // editors which pages came from disk, so one showing such a page reloads it.
            // The losing side of a conflict becomes a page of its own, titled in the app's language; a page
            // another device replaces is kept in its history first; a page deleted here takes its history along.
            let options = WorkspaceSync.Options(
                device: Self.deviceName,
                conflictTitle: { title, source in
                    let title = title.isEmpty ? String(localized: "app:page.untitled") : title
                    return String(localized: "app:sync.conflictedCopy \(title) \(source)")
                },
                willReplace: { row in
                    do {
                        try history.recordBeforeReplace(row)
                    } catch {
                        Log.warn("page version not kept: \(error)", category: "history", context: ["docId": row.id])
                    }
                },
                onDeleted: { ids in
                    for id in ids { try? history.forget(pageID: id) }
                })
            let sync = WorkspaceSync(store: store, files: PageFiles(root: folder), options: options) { [weak self] report in
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
                    Toasts.report(.workspaceSyncFailed, error, category: "workspace")
                    Task { @MainActor in self?.syncError = error.localizedDescription }
                }
            }
        } catch {
            Toasts.report(.workspaceUnavailable, error, category: "workspace")
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
                Toasts.report(.workspaceSyncFailed, error, category: "workspace")
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
                "skippedFiles": "\(report.skippedFiles)", "conflictCopies": "\(report.conflictCopies)",
            ])
    }

    /// This device's user-visible name (conflicted copies and page versions say where they came from).
    static var deviceName: String? {
        #if os(macOS)
            Host.current().localizedName
        #else
            UIDevice.current.name
        #endif
    }

    /// The kind of device a comment was written on ("Mac", "iPhone", "iPad").
    static var deviceKind: String {
        #if os(macOS)
            "Mac"
        #else
            UIDevice.current.model
        #endif
    }

    /// The name comments carry: the user's full name where the system has one (macOS); none on iOS ("You").
    static var authorName: String? {
        #if os(macOS)
            let name = NSFullUserName()
            return name.isEmpty ? nil : name
        #else
            return nil
        #endif
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
            Toasts.report(.workspaceSaveFailed, error, category: "workspace")
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
            Toasts.report(.workspaceSaveFailed, error, category: "workspace")
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
            Toasts.report(.workspaceSaveFailed, error, category: "workspace")
        }
    }

    /// Keeps `tree` and `trash` in sync with the database for the lifetime of the calling task (`observation`).
    private func observe() async {
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
        perform("create page", code: .pageCreateFailed) { try store.create(parentId: parentId).id }
    }

    /// A page with a title and plain lines already in it (Home's quick notes).
    func createPage(_ note: QuickNote, parentId: String? = nil) -> String? {
        perform("create page", code: .pageCreateFailed) {
            let record = try store.create(parentId: parentId)
            try store.saveContent(
                Snapshot(docId: record.id, content: note.content, title: note.title, text: note.text, wordCount: note.wordCount))
            return record.id
        }
    }

    func setFavorite(_ favorite: Bool, id: String) {
        perform("set favorite", id, code: .pageUpdateFailed) { try store.setFavorite(favorite, for: id) }
    }

    func setLocked(_ locked: Bool, id: String) {
        perform("set locked", id, code: .pageUpdateFailed) { try store.setLocked(locked, for: id) }
    }

    func duplicate(id: String) {
        perform("duplicate", id, code: .pageCreateFailed) { try store.duplicate(id: id) }
    }

    func moveToTrash(id: String) {
        perform("move to trash", id, code: .pageDeleteFailed) { try store.moveToTrash(id: id) }
    }

    func restore(id: String) {
        perform("restore", id, code: .pageRestoreFailed) { try store.restore(id: id) }
    }

    /// Sidebar drag and drop. Returns false when the drop is invalid (onto itself / its own subtree).
    @discardableResult
    func movePage(_ dragged: String, onto target: String, zone: DropZone) -> Bool {
        guard let destination = tree.destination(dropping: dragged, onto: target, zone: zone) else { return false }
        return perform("move page", dragged, code: .pageMoveFailed) {
            try store.move(id: dragged, toParent: destination.parentId, at: destination.index)
        } != nil
    }

    /// Drop onto a section header: to the end of the top level.
    @discardableResult
    func movePageToTopLevel(_ dragged: String) -> Bool {
        perform("move page", dragged, code: .pageMoveFailed) { try store.move(id: dragged, toParent: nil, at: .max) } != nil
    }

    func deletePermanently(id: String) {
        perform("delete permanently", id, code: .pageDeleteFailed) { try store.deletePermanently(id: id) }
        comments?.removeAll(pageId: id)
    }

    /// Deletes what has been in the trash longer than Settings → Keep deleted pages allows (at launch and when the
    /// app comes back to the front). Other devices follow through the workspace folder.
    func purgeTrash(now: Date = .now) {
        let days = TrashPreferences.keepDays
        guard days > 0, let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now) else { return }
        if let count = perform("purge trash", nil, code: .trashEmptyFailed, { try store.purgeTrash(deletedBefore: cutoff) }), count > 0 {
            Log.info("trash purged", category: "store", context: ["pages": "\(count)", "days": "\(days)"])
        }
    }

    func emptyTrash() {
        perform("empty trash", code: .trashEmptyFailed) { try store.emptyTrash() }
    }

    /// ⌘K's search, off the main thread: the index may be busy writing (a page saved, an attachment read), and
    /// typing must never wait for it.
    func search(_ query: String, options: SearchOptions = .standard) async -> [SearchHit] {
        let indexer = searchIndexer
        return await Task.detached(priority: .userInitiated) {
            do {
                return try indexer.search(query, options: options)
            } catch {
                Toasts.report(.searchFailed, error, category: "store")
                return []
            }
        }.value
    }

    /// Home: this device's writing activity over the last `days` days, and the workspace's totals.
    func activity(days: Int) -> [DailyActivity] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
        return perform("load activity") { try store.activity(since: start) } ?? []
    }

    func stats() -> WorkspaceStats {
        perform("load stats") { try store.stats() } ?? WorkspaceStats(pages: 0, words: 0)
    }

    /// A bulk import or export ended (Settings → Workspace): a toast says how it went, wherever the user is now.
    private static func announce(_ summary: BulkTransfer.Summary) {
        let importing = summary.kind == .importing
        let context = ["count": String(summary.count), "skipped": String(summary.skipped.count)]
        if summary.failed {
            Toasts.report(importing ? .importFailed : .exportFailed, category: "transfer", context: context)
        } else if !summary.cancelled {
            if importing, !summary.skipped.isEmpty { Toasts.report(.importPartial, category: "transfer", context: context) }
            let count = summary.count.formatted()
            Toasts.shared.show(
                .success,
                importing
                    ? String(localized: "app:toast.imported \(count)") : String(localized: "app:toast.exported \(count)"))
        }
    }

    /// Runs a store change; a failure is logged and — given its `code` — shown to the user (a toast with the code).
    /// Without a code (background reads: activity, stats) it is only logged.
    @discardableResult
    private func perform<T>(_ action: String, _ id: String? = nil, code: ErrorCode? = nil, _ body: () throws -> T) -> T? {
        do {
            return try body()
        } catch {
            var context = ["action": action]
            if let id { context["docId"] = id }
            if let code {
                Toasts.report(code, error, category: "store", context: context)
            } else {
                Log.error("\(action) failed: \(Incident.describe(error))", category: "store", context: context)
            }
            return nil
        }
    }
}

extension Notification.Name {
    /// Pages the workspace sync imported from the folder; `userInfo["ids"]` is `[String]`.
    static let pagesChangedOnDisk = Notification.Name("app.yancey.hikki.pagesChangedOnDisk")
}

/// Settings → Workspace → Keep deleted pages: how many days a page stays in the trash (0 = until emptied).
enum TrashPreferences {
    static let keepDaysKey = "trash.keepDays"
    static let choices = [7, 30, 90, 0]
    static let defaultDays = 30

    static var keepDays: Int {
        UserDefaults.standard.object(forKey: keepDaysKey) as? Int ?? defaultDays
    }

    /// When a page trashed at `deletedAt` goes for good, or nil when nothing is purged.
    static func purgeDate(for deletedAt: Date) -> Date? {
        keepDays > 0 ? Calendar.current.date(byAdding: .day, value: keepDays, to: deletedAt) : nil
    }
}
