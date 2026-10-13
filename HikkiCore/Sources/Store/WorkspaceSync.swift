import Foundation

/// Storage option C: the workspace folder is the source of truth; the SQLite store is a cache rebuilt from it.
/// `reconcile()` brings the two in line. After `start()`, every committed page change is written to its file,
/// and the folder is watched: whatever another device (or iCloud) changes there is reconciled within a moment.
/// File work runs on one serial queue, off the database's.
public final class WorkspaceSync: @unchecked Sendable {
    public struct Report: Equatable, Sendable {
        public var imported = 0
        public var exported = 0
        public var deletedHere = 0
        public var skippedFiles = 0
        public var waitingForDownload = 0
        /// Remote deletions not applied because they looked like a missing/empty folder (see `reconcile`).
        public var deletionsHeldBack = 0
        /// Pages taken from the folder this pass — an open editor showing one of them reloads it.
        public var importedIDs: [String] = []
    }

    private let store: DocumentStore
    private let files: PageFiles
    /// User-initiated: the app waits on it (`flush`) when going to the background.
    private let queue = DispatchQueue(label: "app.yancey.hikki.workspace-sync", qos: .userInitiated)
    private let watchDelay: TimeInterval
    /// Called (on the sync queue) after every reconcile, including those the folder watcher runs.
    private let onReconcile: (@Sendable (Report) -> Void)?
    /// Backoff between follow-up passes while files are still downloading or unreadable.
    private let retryDelays: [TimeInterval]

    // Confined to `queue`.
    private var stamps: [String: PageFiles.Stamp] = [:]
    private var watcher: DispatchSourceFileSystemObject?
    private var pendingWatchPass: DispatchWorkItem?
    private var retry: DispatchWorkItem?
    private var retryIndex = 0
    private var started = false
    private var stopped = false

    /// `watchDelay`: how long the folder must be quiet before a watched change is reconciled (a burst of
    /// iCloud downloads becomes one pass). `retryDelays`: follow-up passes while downloads are pending.
    public init(
        store: DocumentStore, files: PageFiles, watchDelay: TimeInterval = 0.3,
        retryDelays: [TimeInterval] = [1, 2, 5, 10, 30, 60], onReconcile: (@Sendable (Report) -> Void)? = nil
    ) {
        self.store = store
        self.files = files
        self.watchDelay = watchDelay
        self.retryDelays = retryDelays
        self.onReconcile = onReconcile
    }

    /// Ends watching and write-through (the workspace moved to another folder; a new sync takes over).
    public func stop() {
        queue.sync {
            stopped = true
            watcher?.cancel()
            watcher = nil
            pendingWatchPass?.cancel()
            pendingWatchPass = nil
            retry?.cancel()
            retry = nil
        }
    }

    deinit {
        watcher?.cancel()
    }

    /// Starts writing every page change through to the folder, then reconciles once (in that order, so edits
    /// made while reconciling aren't missed; the reconcile's own imports write back identical bytes — skipped),
    /// then watches the folder.
    public func start() throws -> Report {
        try store.observePageCommits { [weak self] changed, deletions, live in
            self?.queue.async { self?.writeThrough(changed: changed, deletions: deletions, live: live) }
        }
        return try queue.sync {
            started = true
            return try reconcileOnQueue()
        }
    }

    /// Makes the store match the folder. Per page: a file without a row is imported; the newer of file and row
    /// wins; a row without a file is either deleted here (its file existed before — another device deleted
    /// it) or written out (it never had one). Same-page edits on two devices resolve to the newer for now.
    @discardableResult
    public func reconcile() throws -> Report {
        try queue.sync { try reconcileOnQueue() }
    }

    private func reconcileOnQueue() throws -> Report {
        var report = Report()
        let listing = try files.scan(known: stamps)
        stamps = listing.stamps
        report.skippedFiles = listing.skipped.count
        report.waitingForDownload = listing.placeholders.count
        // Ask iCloud for pages that aren't on this device yet; they're imported on a later pass.
        for placeholder in listing.placeholders {
            try? FileManager.default.startDownloadingUbiquitousItem(at: placeholder)
        }
        let rows = Dictionary(try store.allDocuments().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let synced = try store.syncedIDs()
        let read = Dictionary(listing.pages.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for (id, stamp) in listing.stamps.sorted(by: { $0.key < $1.key }) {
            let row = rows[id]
            if row == nil, synced.contains(id) {
                // Synced here and the row is gone: deleted on this device, its file removal still queued
                // behind this pass. Finish it rather than bring the page back.
                try files.delete(id)
                try store.unmarkSynced([id])
                stamps[id] = nil
                continue
            }
            // A file unchanged since the last pass is only read again when the store lost its row.
            guard let page = read[id] ?? (row == nil ? try? files.read(id) : nil) else {
                if let row, row.updatedAt > stamp.updatedAt.addingTimeInterval(0.001) {
                    try write(row)  // edited here; write-through missed it (e.g. it failed)
                    report.exported += 1
                }
                continue
            }
            if let row {
                if page.updatedAt > row.updatedAt.addingTimeInterval(0.001) {
                    try store.importPage(try page.record())
                    report.imported += 1
                    report.importedIDs.append(id)
                } else if row.updatedAt > page.updatedAt.addingTimeInterval(0.001) {
                    try write(row)
                    report.exported += 1
                } else {
                    try store.markSynced([id])
                }
            } else {
                try store.importPage(try page.record())
                report.imported += 1
                report.importedIDs.append(id)
            }
        }
        // Rows the folder has no trace of: deleted elsewhere if they were synced, otherwise never written.
        let missing = rows.keys.filter { !listing.present.contains($0) }
        let deletedElsewhere = missing.filter { synced.contains($0) }
        for id in missing where !synced.contains(id) {
            guard let row = rows[id] else { continue }
            try write(row)
            report.exported += 1
        }
        if Self.deletionLooksSafe(deletedElsewhere.count, synced: synced.count, folderExists: listing.folderExists) {
            for id in deletedElsewhere { try store.deletePage(id: id) }
            report.deletedHere = deletedElsewhere.count
        } else if !deletedElsewhere.isEmpty {
            // Fail closed: a missing or mostly-empty folder (iCloud still syncing, a moved bookmark) must
            // never empty the workspace. Keep everything; the next pass decides again.
            report.deletionsHeldBack = deletedElsewhere.count
            Log.error(
                "workspace reconcile held back deletions", category: "workspace",
                context: ["count": "\(deletedElsewhere.count)", "synced": "\(synced.count)"])
        }
        ensureWatching()
        scheduleDownloadRetry(after: report)
        onReconcile?(report)
        return report
    }

    /// iCloud fills placeholders in later, and a half-downloaded file reads as corrupt: while any are left,
    /// pass again after a while (backing off). The folder watcher usually gets there first, but kqueue
    /// events don't arrive reliably from iOS file-provider folders; this doesn't depend on them.
    private func scheduleDownloadRetry(after report: Report) {
        retry?.cancel()
        retry = nil
        guard started, !stopped, report.waitingForDownload > 0 || report.skippedFiles > 0 else {
            retryIndex = 0
            return
        }
        if report.imported > 0 { retryIndex = 0 }  // progress: start the backoff over
        let delay = retryDelays[min(retryIndex, retryDelays.count - 1)]
        retryIndex += 1
        let pass = DispatchWorkItem { [weak self] in
            guard let self, !stopped else { return }
            retry = nil
            do {
                _ = try reconcileOnQueue()
            } catch {
                Log.error("workspace download retry failed: \(error)", category: "workspace")
            }
        }
        retry = pass
        queue.asyncAfter(deadline: .now() + delay, execute: pass)
    }

    /// Remote deletions are applied only when the folder exists and they're a small part of what was synced —
    /// at most a quarter (and always up to 3), so ordinary deletes on another device still come through.
    static func deletionLooksSafe(_ count: Int, synced: Int, folderExists: Bool) -> Bool {
        guard folderExists else { return false }
        return count <= max(3, synced / 4)
    }

    /// Blocks until queued file writes are done (tests, and before backgrounding).
    public func flush() {
        queue.sync {}
    }

    // MARK: - Write-through

    private func writeThrough(changed: [DocumentRecord], deletions: Bool, live: Set<String>?) {
        guard !stopped else { return }
        do {
            for record in changed { try write(record) }
            if deletions, let live {
                // Files of pages deleted here (or cascaded with a parent): only pages this device has synced —
                // a file another device just added isn't in the store yet, and must not be taken for one.
                let synced = try store.syncedIDs()
                let gone = try files.scan(known: stamps).present.filter { synced.contains($0) && !live.contains($0) }
                for id in gone {
                    try files.delete(id)
                    stamps[id] = nil
                }
                try store.unmarkSynced(gone)
            }
            ensureWatching()  // the first page written may have just created the folder
        } catch {
            Log.error("workspace write-through failed: \(error)", category: "workspace")
        }
    }

    /// Writes the page's file unless it already holds exactly these bytes (no churn for iCloud), and records it
    /// as synced.
    private func write(_ record: DocumentRecord) throws {
        let page = try PageFile(record: record)
        if try files.read(record.id) != page { try files.write(page) }
        stamps[record.id] = files.stamp(of: record.id, updatedAt: record.updatedAt)
        try store.markSynced([record.id])
    }

    // MARK: - Watching the folder

    /// Watches `pages/` once `start()` ran and the folder exists (a later pass retries if it didn't yet). Every
    /// entry change — an iCloud download, another device's atomic write, a deletion, this device's own
    /// writes — schedules a pass; unchanged files cost a stat, not a read.
    private func ensureWatching() {
        guard started, !stopped, watcher == nil else { return }
        let descriptor = open(files.directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .delete, .rename], queue: queue)
        source.setEventHandler { [weak self, unowned source] in
            guard let self else { return }
            if !source.data.isDisjoint(with: [.delete, .rename]) {
                // The folder itself went away or moved: stop; the next activation pass watches it again.
                source.cancel()
                watcher = nil
                return
            }
            scheduleWatchPass()
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }

    private func scheduleWatchPass() {
        pendingWatchPass?.cancel()
        let pass = DispatchWorkItem { [weak self] in
            guard let self else { return }
            pendingWatchPass = nil
            do {
                _ = try reconcileOnQueue()
            } catch {
                Log.error("workspace watch pass failed: \(error)", category: "workspace")
            }
        }
        pendingWatchPass = pass
        queue.asyncAfter(deadline: .now() + watchDelay, execute: pass)
    }
}
