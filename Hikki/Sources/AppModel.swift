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
    /// The losing side of a conflict becomes a page of its own, titled in the app's language.
    nonisolated static let conflictTitle: ConflictCopy.Title = { title, source in
        let title = title.isEmpty ? String(localized: "app:page.untitled") : title
        return String(localized: "app:sync.conflictedCopy \(title) \(source)")
    }

    let store: DocumentStore
    let searchIndexer: SearchIndexer
    /// Every date in the pages: Home's Upcoming and the reminders' notifications (Reminders.swift).
    let reminders: Reminders
    let assets: AssetStore
    let crashReporter: CrashReporter
    let workspaceStore: WorkspaceStore
    /// Settings → Import & Export: the bulk import / export job (BulkTransfer.swift).
    let bulkTransfer = BulkTransfer()
    /// nil until onboarding creates one (first launch).
    private(set) var workspace: Workspace?
    private(set) var tree = PageTree([])
    /// The store's pages have come in once (an empty tree before that means "not read yet", not "no pages").
    private(set) var treeLoaded = false
    private(set) var trash: [PageSummary] = []
    /// What the last pass over the workspace folder found (Settings → Storage shows it).
    private(set) var lastSync: SyncStatus?
    /// Why the folder isn't being synced at all (unresolvable bookmark, a failed first pass); nil while it works.
    private(set) var syncError: String?
    /// How iCloud is doing, for a workspace kept there (`Workspace.Location.cloud`); nil otherwise.
    private(set) var cloudStatus: CloudSync.Status?
    /// Each page's latest edit — typed, saved, in iCloud — for the editor's save indicator (SyncIndicator.swift).
    /// A `let`, so nothing reading the model observes it; only the indicator does.
    let pageSync = PageSyncTracker()

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
        self.reminders = Reminders(store: store)
        // Semantic search was removed (2026-10-15): its settings go too.
        for key in ["semantic.enabled", "semantic.endpoint", "semantic.model"] { UserDefaults.standard.removeObject(forKey: key) }
        self.assets = assets
        self.crashReporter = crashReporter
        self.workspaceStore = workspaceStore
        bulkTransfer.onFinish = Self.announce
        // A page saved in an editor: its file is followed up to iCloud — once the write-through has written it, so
        // a folder scan that read the file before can't vouch for this save.
        pageSync.onSaved = { [weak self] id, at in
            guard let self, let cloud = self.cloud else { return }
            if let sync = self.sync {
                sync.afterQueuedWrites { cloud.noteSaved(pageID: id, at: at) }
            } else {
                cloud.noteSaved(pageID: id, at: at)
            }
        }
        do {
            workspace = try workspaceStore.load()
        } catch {
            Toasts.report(.workspaceOpenFailed, error, category: "workspace")
        }
        startWorkspaceSync()
        searchIndexer.start()
        reminders.start()
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
    /// The workspace in iCloud (CloudKit): the folder's files carried to the user's other devices.
    @ObservationIgnored private var cloud: CloudSync?
    /// iCloud was just turned on: the account the device uses now may take the workspace (`CloudMirror.releaseAccount`).
    @ObservationIgnored private var adoptsCloudAccount = false
    /// Looks over the folder now and then for what `WorkspaceSync` doesn't write (history, comments, chats, assets).
    @ObservationIgnored private var cloudScan: Task<Void, Never>?
    /// Versions of pages (Page ⋯ → Page History…), in the workspace folder; nil until the folder is known.
    @ObservationIgnored private(set) var history: PageHistory?
    /// Comment threads (`comments/<page id>.json`), in the folder too so they sync with the pages.
    @ObservationIgnored private(set) var comments: PageComments?
    /// Each page's AI conversation (`ai/<page id>.json`), in the folder too.
    @ObservationIgnored private(set) var chats: PageChats?
    /// Excalidraw's Library (`drawings/library.json`), in the folder too.
    @ObservationIgnored private(set) var drawingLibrary: DrawingLibrary?

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
    /// The workspace folder as Ask AI's file tools reach it (nil until it is known).
    var filesFolder: URL? { workspaceFolder }
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
            #if os(macOS)
                if case .folder = workspace.location, WorkspaceFolder.accessDenied(at: folder) {
                    askForFolderAccess(folder)
                    return
                }
            #endif
            if case .folder = workspace.location {
                // iCloud Drive folders are retired: the folder's files move into the app, then sync through iCloud.
                if moveFolderWorkspace(from: folder, appRoot: appRoot) { return }
            }
            workspaceFolder = folder
            syncIdentity()
            assets.useWorkspaceFolder(folder)
            let assets = assets
            Task.detached(priority: .utility) { assets.copyLegacyAssets() }
            sweepAssets(in: folder)
            // Page history lives in the folder too (`history/<page id>/`), so versions sync with the pages.
            let history = PageHistory(root: folder, policy: Self.historyPolicy, device: Self.deviceName)
            self.history = history
            let comments = PageComments(root: folder, author: Self.authorName, device: Self.deviceKind)
            self.comments = comments
            let chats = PageChats(root: folder)
            self.chats = chats
            drawingLibrary = DrawingLibrary(root: folder)
            let retention = AIPreferences.chatRetention
            Task.detached(priority: .utility) { chats.prune(retention) }
            // Every pass — launch, activation, or the folder watcher noticing another device — tells open
            // editors which pages came from disk, so one showing such a page reloads it.
            // The losing side of a conflict becomes a page of its own, titled in the app's language; a page
            // another device replaces is kept in its history first; a page deleted here takes its history along.
            let cloud: CloudSync? =
                if case .cloud = workspace.location, Self.cloudAllowed { makeCloudSync(folder: folder, appRoot: appRoot) } else { nil }
            self.cloud = cloud
            if cloud == nil { pageSync.setCloud(.off) }
            let options = WorkspaceSync.Options(
                device: Self.deviceName,
                conflictTitle: Self.conflictTitle,
                willReplace: { row in
                    do {
                        try history.recordBeforeReplace(row)
                    } catch {
                        Log.warn("page version not kept: \(error)", category: "history", context: ["docId": row.id])
                    }
                },
                // Every page deleted for good here — emptied or purged trash, subpages that went with a parent too.
                onDeleted: { ids in
                    for id in ids {
                        try? history.forget(pageID: id)
                        comments.removeAll(pageId: id)
                        chats.removeAll(pageId: id)
                    }
                },
                didWrite: { cloud?.noteLocalChanges() })
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
                    cloud?.start()
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

    #if os(macOS)
        /// The workspace's folder is there but the sandbox keeps it shut (a bookmark from before the Mac app was
        /// sandboxed, or a revoked grant): only the user picking it again opens it, and only then can it move into the
        /// app. Until then nothing syncs.
        private func askForFolderAccess(_ folder: URL) {
            folder.stopAccessingSecurityScopedResource()
            Toasts.report(.workspaceFolderAccess, category: "workspace", actionTitle: "app:workspace.chooseFolderAgain") {
                [weak self] in
                FolderAccessPanel.choose(startingAt: folder) { url in
                    do {
                        try self?.grantFolderAccess(url, was: folder)
                    } catch {
                        Toasts.report(.workspaceUnavailable, error, category: "workspace")
                    }
                }
            }
            syncError = ErrorCode.workspaceFolderAccess.message
        }

        /// The folder picked again (or another one with the workspace in it): its new bookmark opens it, and it
        /// moves into the app as any folder workspace does.
        func grantFolderAccess(_ url: URL, was folder: URL) throws {
            guard var workspace else { return }
            let bookmark = try FolderBookmark.make(for: url)
            workspace.location = .folder(bookmark: bookmark, displayName: FolderBookmark.displayName(for: url))
            try workspaceStore.save(workspace)
            self.workspace = workspace
            Log.info("workspace folder access granted again", category: "workspace")
            startWorkspaceSync()
        }
    #endif

    /// The CloudKit side of the workspace: what arrives is written into the folder, then the folder reconciles (and
    /// open editors reload) as for any change on disk.
    private func makeCloudSync(folder: URL, appRoot: URL) -> CloudSync {
        let mirror = CloudMirror(
            root: folder, stateURL: appRoot.appending(path: "cloud-state.json"),
            options: .init(device: Self.deviceName, conflictTitle: Self.conflictTitle))
        if adoptsCloudAccount {
            mirror.releaseAccount()
            adoptsCloudAccount = false
        }
        // A new `CloudSync` counts its uploads from nothing; a late copy from the one before is dropped.
        let generation = pageSync.resetUploads()
        let cloud = CloudSync(
            mirror: mirror,
            onReceived: { [weak self] in Task { @MainActor in self?.cloudReceived() } },
            onStatus: { [weak self] status in
                Task { @MainActor in
                    self?.cloudStatus = status
                    self?.pageSync.setCloud(status.cloud)
                }
            },
            onUploads: { [weak self] uploads in
                Task { @MainActor in self?.pageSync.apply(uploads, generation: generation) }
            })
        cloudStatus = .starting
        pageSync.setCloud(.on)
        cloudScan?.cancel()
        cloudScan = Task { [weak cloud] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                cloud?.noteLocalChanges(after: 0)
            }
        }
        return cloud
    }

    private func cloudReceived() {
        // workspace.json may be another device's (a second device joining takes the workspace's name and icon).
        identityUpdatedAt = nil
        reconcileWorkspace(fetch: false)
    }

    /// Where the workspace lives, as the sidebar, Settings and a page's facts name it.
    var locationName: String {
        switch workspace?.location {
        case .cloud?: String(localized: "app:location.icloud")
        case .folder(_, let name)?: name
        case .device?, nil: String(localized: "app:onboarding.location.device")
        }
    }

    /// iCloud's state in words: "Synced 2 min ago", "Syncing…", "Not signed in to iCloud"…
    var cloudStatusText: String {
        switch cloudStatus {
        case .synced(let at)?: String(localized: "app:cloud.synced \(at.formatted(.relative(presentation: .named)))")
        case .syncing?, .starting?, nil: String(localized: "app:cloud.syncing")
        case .noAccount?: String(localized: "app:cloud.noAccount")
        case .accountChanged?: String(localized: "app:cloud.accountChanged")
        case .quotaFull?: String(localized: "app:cloud.quotaFull")
        case .failed(let code)?: String(localized: "app:cloud.failed \(code)")
        }
    }

    /// Settings → Storage: keep the workspace in iCloud, or on this device only. Nothing is deleted either way —
    /// turned off, the pages stay here (and in iCloud as they were).
    func setICloud(_ on: Bool) {
        guard var workspace else { return }
        let location: Workspace.Location = on ? .cloud : .device
        guard workspace.location != location else { return }
        workspace.location = location
        stopWorkspaceSync()
        adoptsCloudAccount = on
        do {
            try workspaceStore.save(workspace)
            self.workspace = workspace
            Log.info("workspace iCloud \(on ? "on" : "off")", category: "workspace")
        } catch {
            Toasts.report(.workspaceSaveFailed, error, category: "workspace")
        }
        startWorkspaceSync()
    }

    private func stopWorkspaceSync() {
        sync?.stop()
        sync = nil
        cloud?.stop()
        cloud = nil
        cloudScan?.cancel()
        cloudScan = nil
        cloudStatus = nil
        pageSync.setCloud(.off)
        workspaceFolder?.stopAccessingSecurityScopedResource()
        workspaceFolder = nil
        identityUpdatedAt = nil
    }

    /// A workspace in an iCloud Drive folder (before CloudKit) moves into the app: every file of the folder is
    /// copied in — the folder itself is left as it was — and the workspace syncs through iCloud from then on.
    /// Not while iCloud Drive still has files of it to download (it asks for them, and the move waits for a later
    /// launch or activation; the folder keeps syncing meanwhile). Returns whether it moved.
    private func moveFolderWorkspace(from folder: URL, appRoot: URL) -> Bool {
        guard var workspace else { return false }
        let local = appRoot.appending(path: "Workspace", directoryHint: .isDirectory)
        do {
            let copied = try WorkspaceFolder.copyContents(of: folder, into: local)
            folder.stopAccessingSecurityScopedResource()
            workspace.location = .cloud
            // The pages were synced with the old folder, not this one: a first pass compares them all again.
            try store.unmarkAllSynced()
            try workspaceStore.save(workspace)
            self.workspace = workspace
            Log.info("workspace moved from its folder into iCloud", category: "workspace", context: ["files": "\(copied)"])
            startWorkspaceSync()
            return true
        } catch WorkspaceFolder.CopyError.stillDownloading(let count) {
            Log.info("workspace folder still downloading; move later", category: "workspace", context: ["files": "\(count)"])
            return false
        } catch {
            Toasts.report(.workspaceMoveFailed, error, category: "workspace")
            return false
        }
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
    /// A run on its own data folder (UI tests, demos: `HIKKI_DATA_DIR`) never syncs with the device's iCloud account —
    /// its pages would land in the user's own workspace there — unless `HIKKI_CLOUD=1`.
    static var cloudAllowed: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["HIKKI_DATA_DIR"] == nil || environment["HIKKI_CLOUD"] == "1"
    }

    /// Whether the workspace syncs through iCloud (and so has something to pull).
    var syncsWithCloud: Bool {
        if case .cloud? = workspace?.location { true } else { false }
    }

    /// Pull to refresh: what waits here goes up, what other devices saved comes down (arrivals reconcile the
    /// folder as they land), then the folder is compared once more.
    func refreshFromCloud() async {
        Log.info("cloud refresh pulled", category: "cloud")
        guard let cloud else { return }
        cloud.retryHeldBack()
        await cloud.sendNow()
        await cloud.fetchNow()
        reconcileWorkspace(fetch: false)
    }

    func reconcileWorkspace(fetch: Bool = true) {
        guard let sync else { return }
        if fetch, let cloud {
            // Back in the app: files waiting after "storage full" are tried again too.
            cloud.retryHeldBack()
            cloud.noteLocalChanges(after: 0)
            Task { await cloud.fetchNow() }
        }
        syncIdentity()
        Task.detached(priority: .utility) {
            do {
                Self.log("workspace reconciled", try sync.reconcile())
            } catch {
                Toasts.report(.workspaceSyncFailed, error, category: "workspace")
            }
        }
    }

    /// Waits for queued file writes, then sends what iCloud hasn't got yet (before the app goes to the background).
    func flushWorkspace() async {
        sync?.flush()
        await cloud?.sendNow()
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
            let kind = if case .cloud = location { "cloud" } else { "device" }
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
            for try await pages in store.observePages() {
                tree = PageTree(pages)
                if !treeLoaded { treeLoaded = true }
            }
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
    /// Attachments no page, version, comment or chat names any more leave the folder (`AssetSweep`), once a day.
    private func sweepAssets(in folder: URL) {
        let key = "assets.sweptAt"
        if let last = UserDefaults.standard.object(forKey: key) as? Date, Date.now.timeIntervalSince(last) < 86_400 { return }
        let store = store
        Task.detached(priority: .background) {
            let rows: [String]
            do {
                rows = try store.allDocuments().flatMap { [$0.content, $0.icon, $0.cover].compactMap { $0 } }
            } catch {
                Log.warn("asset sweep skipped: \(error)", category: "assets")
                return
            }
            guard let removed = AssetSweep.sweep(root: folder, rows: rows) else { return }
            Log.info("unused assets removed", category: "assets", context: ["count": "\(removed.count)"])
            await MainActor.run { UserDefaults.standard.set(Date.now, forKey: key) }
        }
    }

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

    /// ⌘K's search, off the main thread and beside the index's writes (WAL), so typing never waits for a save or an
    /// attachment being read. Cancelling the calling task (a newer query) stops it; that is no failure.
    func search(_ query: String, options: SearchOptions = .standard) async -> [SearchHit] {
        do {
            return try await searchIndexer.search(query, options: options)
        } catch is CancellationError {
            return []
        } catch {
            if Task.isCancelled { return [] }
            Toasts.report(.searchFailed, error, category: "search")
            return []
        }
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
