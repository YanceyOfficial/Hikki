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
        /// Conflicted copies made this pass: the losing side of a page two devices changed at once, kept as a page.
        public var conflictCopies = 0
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
    private let fileVersions: any FileVersionStore
    private let device: String?
    private let conflictTitle: ConflictCopy.Title
    private let willReplace: (@Sendable (DocumentRecord) -> Void)?
    private let onDeleted: (@Sendable ([String]) -> Void)?

    /// How conflicts are resolved and who hears about replaced and deleted pages.
    public struct Options: Sendable {
        /// iCloud's conflict versions of page files.
        public var fileVersions: any FileVersionStore
        /// This device's name, for the title of a conflicted copy of an edit made here.
        public var device: String?
        public var conflictTitle: ConflictCopy.Title
        /// Called (on the sync queue) before a page from the folder replaces a different row (page history keeps it).
        public var willReplace: (@Sendable (DocumentRecord) -> Void)?
        /// Called (on the sync queue) with the pages deleted here whose files were removed (their history goes too).
        public var onDeleted: (@Sendable ([String]) -> Void)?

        public init(
            fileVersions: any FileVersionStore = UbiquitousFileVersions(), device: String? = nil,
            conflictTitle: @escaping ConflictCopy.Title = ConflictCopy.defaultTitle,
            willReplace: (@Sendable (DocumentRecord) -> Void)? = nil, onDeleted: (@Sendable ([String]) -> Void)? = nil
        ) {
            self.fileVersions = fileVersions
            self.device = device
            self.conflictTitle = conflictTitle
            self.willReplace = willReplace
            self.onDeleted = onDeleted
        }
    }

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
        retryDelays: [TimeInterval] = [1, 2, 5, 10, 30, 60], options: Options = Options(),
        onReconcile: (@Sendable (Report) -> Void)? = nil
    ) {
        self.store = store
        self.files = files
        self.watchDelay = watchDelay
        self.retryDelays = retryDelays
        fileVersions = options.fileVersions
        device = options.device
        conflictTitle = options.conflictTitle
        willReplace = options.willReplace
        onDeleted = options.onDeleted
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
    /// it) or written out (it never had one). Conflicts lose nothing: when iCloud kept several versions of a page
    /// file, or the row and the file both changed since they last agreed, the newest wins as the page and every
    /// other version becomes a sibling page, a "conflicted copy".
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
        let bases = try store.syncBases()
        var read = Dictionary(listing.pages.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // Imports are collected and written parents-first at the end: a row's parent is a foreign key, and
        // the folder lists children before their parents as often as not.
        var imports: [PageFile] = []
        // iCloud's conflicts, for every file read this pass (a conflict arrives as a change to the file).
        for page in listing.pages {
            if let winner = try resolveFileConflicts(of: page, report: &report, copies: &imports) { read[page.id] = winner }
        }
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
                let fileNewer = page.updatedAt > row.updatedAt.addingTimeInterval(0.001)
                let rowNewer = row.updatedAt > page.updatedAt.addingTimeInterval(0.001)
                if fileNewer || rowNewer, let base = bases[id], row.updatedAt > base.addingTimeInterval(0.001),
                    page.updatedAt > base.addingTimeInterval(0.001), let local = try? PageFile(record: row),
                    ConflictCopy.differ(local, page)
                {
                    // Both sides changed since they last agreed (this device's edit never reached the file): the
                    // newer wins, the other is kept as a conflicted copy.
                    let loser = fileNewer ? local : page
                    let url = try files.url(for: id)
                    let source = fileNewer ? device : fileVersions.currentDevice(at: url)
                    imports.append(try conflictCopy(of: loser, device: source, report: &report))
                    Log.warn("page changed here and in the folder; conflicted copy kept", category: "workspace", context: ["id": id])
                }
                if fileNewer {
                    imports.append(page)
                } else if rowNewer {
                    try write(row)
                    report.exported += 1
                } else {
                    try store.markSynced(id, at: row.updatedAt)
                }
            } else {
                imports.append(page)
            }
        }
        let ordered = Self.parentsFirst(imports, inStore: Set(rows.keys), inFolder: listing.present)
        for page in ordered.ready {
            if let willReplace, let row = rows[page.id], let local = try? PageFile(record: row), ConflictCopy.differ(local, page) {
                willReplace(row)
            }
            try store.importPage(try page.record())
            report.imported += 1
            report.importedIDs.append(page.id)
        }
        if ordered.waiting > 0 {
            // Their parents are still on their way (placeholders, half-written files): next pass.
            report.waitingForDownload += ordered.waiting
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

    /// iCloud kept other versions of the page's file (two devices saved it at once): the newest (by its edited
    /// time) becomes the file, every other version that says something different becomes a conflicted copy,
    /// and the conflicts are marked resolved. Returns the winner, or nil when the file had no conflicts.
    private func resolveFileConflicts(of page: PageFile, report: inout Report, copies: inout [PageFile]) throws -> PageFile? {
        let url = try files.url(for: page.id)
        let others = fileVersions.conflicts(at: url)
        guard !others.isEmpty else { return nil }
        var candidates: [(page: PageFile, device: String?, modified: Date)] = [
            (page, fileVersions.currentDevice(at: url), .distantFuture)
        ]
        for version in others {
            guard let data = version.contents, let other = try? PageFiles.decode(data), other.id == page.id else { continue }
            candidates.append((other, version.device, version.modified ?? .distantPast))
        }
        // Newest edit wins; on a tie, the current file.
        let winnerIndex =
            candidates.indices.max { a, b in
                (candidates[a].page.updatedAt, candidates[a].modified) < (candidates[b].page.updatedAt, candidates[b].modified)
            } ?? 0
        let winner = candidates[winnerIndex].page
        var kept = [winner]
        for (index, candidate) in candidates.enumerated() where index != winnerIndex {
            guard kept.allSatisfy({ ConflictCopy.differ($0, candidate.page) }) else { continue }  // same words: nothing to keep
            copies.append(try conflictCopy(of: candidate.page, device: candidate.device, report: &report))
            kept.append(candidate.page)
        }
        if winnerIndex != 0 {
            try files.write(winner)
            stamps[winner.id] = files.stamp(of: winner.id, updatedAt: winner.updatedAt)
        }
        try fileVersions.resolveConflicts(at: url)
        Log.warn(
            "page file had conflicting versions; resolved", category: "workspace",
            context: ["id": page.id, "versions": "\(candidates.count)", "copies": "\(kept.count - 1)"])
        return winner
    }

    /// Writes the losing version of a page as a page of its own and returns it, to import.
    private func conflictCopy(of loser: PageFile, device: String?, report: inout Report) throws -> PageFile {
        let copy = ConflictCopy.make(
            from: loser, source: ConflictCopy.source(device: device, date: loser.updatedAt), title: conflictTitle)
        try files.write(copy)
        stamps[copy.id] = files.stamp(of: copy.id, updatedAt: copy.updatedAt)
        report.conflictCopies += 1
        return copy
    }

    /// The pages to import, parents before children, so every row's parent exists when it is written. A page
    /// whose parent the folder still has to deliver waits for a later pass; one whose parent exists nowhere
    /// (not in the store, no trace in the folder) goes to the top level rather than never arriving.
    static func parentsFirst(_ pages: [PageFile], inStore: Set<String>, inFolder: Set<String>) -> (ready: [PageFile], waiting: Int) {
        let byID = Dictionary(pages.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var depth: [String: Int] = [:]
        var waiting = 0
        var ready: [PageFile] = []
        /// Levels above the store's rows: 0 for a top-level page or one whose parent is already a row.
        func level(of page: PageFile, seen: Set<String>) -> Int? {
            if let known = depth[page.id] { return known }
            guard let parentID = page.parentId else { return 0 }
            if inStore.contains(parentID) && byID[parentID] == nil { return 0 }
            if let parent = byID[parentID], !seen.contains(parentID) {
                guard let above = level(of: parent, seen: seen.union([page.id])) else { return nil }
                depth[page.id] = above + 1
                return above + 1
            }
            // Not a row, not in this import: nil while the folder still has a trace of it (downloading, unreadable).
            return inFolder.contains(parentID) ? nil : 0
        }
        var levelled: [(PageFile, Int)] = []
        for page in pages {
            if let n = level(of: page, seen: []) {
                var page = page
                if n == 0, let parentID = page.parentId, !inStore.contains(parentID), byID[parentID] == nil {
                    Log.warn("imported page's parent is missing; placed at the top level", category: "workspace", context: ["id": page.id])
                    page.parentId = nil
                }
                levelled.append((page, n))
            } else {
                waiting += 1
            }
        }
        ready = levelled.sorted { ($0.1, $0.0.id) < ($1.1, $1.0.id) }.map(\.0)
        return (ready, waiting)
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
                if !gone.isEmpty { onDeleted?(Array(gone)) }
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
        try store.markSynced(record.id, at: record.updatedAt)
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
