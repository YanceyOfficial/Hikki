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
            let (pages, skipped) = try files.readAll()
            report.skippedFiles = skipped.count
            let rows = Dictionary(try store.allDocuments().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let synced = try store.syncedIDs()
            var fileIDs = Set<String>()
            for page in pages {
                fileIDs.insert(page.id)
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
            for (id, row) in rows where !fileIDs.contains(id) {
                if synced.contains(id) {
                    try store.deletePage(id: id)
                    report.deletedHere += 1
                } else {
                    try write(row)
                    report.exported += 1
                }
            }
            return report
        }
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
                // Files of pages no longer in the store: deleted here (or cascaded with a parent).
                let gone = try files.readAll().pages.map(\.id).filter { !live.contains($0) }
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
