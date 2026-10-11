import Foundation

/// Storage option C, step 2: the workspace folder is the source of truth; the SQLite store is a cache rebuilt
/// from it. `reconcile()` brings the two in line (launch, app activation); after `start()`, every committed page
/// change is written to its file. File work runs on one serial queue, off the database's.
public final class WorkspaceSync: @unchecked Sendable {
    public struct Report: Equatable, Sendable {
        public var imported = 0
        public var exported = 0
        public var deletedHere = 0
        public var skippedFiles = 0
        public var waitingForDownload = 0
        /// Remote deletions not applied because they looked like a missing/empty folder (see `reconcile`).
        public var deletionsHeldBack = 0
    }

    private let store: DocumentStore
    private let files: PageFiles
    private let queue = DispatchQueue(label: "app.yancey.hikki.workspace-sync", qos: .utility)

    public init(store: DocumentStore, files: PageFiles) {
        self.store = store
        self.files = files
    }

    /// Starts writing every page change through to the folder, then reconciles once (in that order, so edits
    /// made while reconciling aren't missed; the reconcile's own imports write back identical bytes — skipped).
    public func start() throws -> Report {
        try store.observePageCommits { [weak self] changed, deletions, live in
            self?.queue.async { self?.writeThrough(changed: changed, deletions: deletions, live: live) }
        }
        return try reconcile()
    }

    /// Makes the store match the folder. Per page: a file without a row is imported; the newer of file and row
    /// wins; a row without a file is either deleted here (its file existed before — another device deleted
    /// it) or written out (it never had one). Same-page edits on two devices resolve to the newer for now.
    @discardableResult
    public func reconcile() throws -> Report {
        try queue.sync {
            var report = Report()
            let listing = try files.scan()
            report.skippedFiles = listing.skipped.count
            report.waitingForDownload = listing.placeholders.count
            // Ask iCloud for pages that aren't on this device yet; they're imported on a later pass.
            for placeholder in listing.placeholders {
                try? FileManager.default.startDownloadingUbiquitousItem(at: placeholder)
            }
            let rows = Dictionary(try store.allDocuments().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let synced = try store.syncedIDs()
            for page in listing.pages {
                if let row = rows[page.id] {
                    if page.updatedAt > row.updatedAt.addingTimeInterval(0.001) {
                        try store.importPage(try page.record())
                        report.imported += 1
                    } else if row.updatedAt > page.updatedAt.addingTimeInterval(0.001) {
                        try write(row)
                        report.exported += 1
                    } else {
                        try store.markSynced([page.id])
                    }
                } else {
                    try store.importPage(try page.record())
                    report.imported += 1
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
            return report
        }
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
        do {
            for record in changed { try write(record) }
            if deletions, let live {
                // Files of pages deleted here (or cascaded with a parent): only pages this device has synced —
                // a file another device just added isn't in the store yet, and must not be taken for one.
                let synced = try store.syncedIDs()
                let gone = try files.scan().present.filter { synced.contains($0) && !live.contains($0) }
                for id in gone { try files.delete(id) }
                try store.unmarkSynced(gone)
            }
        } catch {
            Log.error("workspace write-through failed: \(error)", category: "workspace")
        }
    }

    /// Writes the page's file unless it already holds exactly these bytes (no churn for iCloud), and records it
    /// as synced.
    private func write(_ record: DocumentRecord) throws {
        let page = try PageFile(record: record)
        if try files.read(record.id) != page { try files.write(page) }
        try store.markSynced([record.id])
    }
}
