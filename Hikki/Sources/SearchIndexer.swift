import Foundation
import HikkiCore
import HikkiSearch
import os

/// Feeds the search index from the store: every committed page change as it happens (a record whose title, icon
/// and edited time the index already has is skipped), and a reconcile at launch — pages whose edited time differs
/// from the index's are indexed again, pages gone from the store (deleted, or in the trash) are dropped. Each
/// page's content is read once (`ContentText.extract`) for the index and Spotlight both. The files a page attaches
/// (PDFs, images) have their text read afterwards by one background reader (`FileTextReader`), once per file:
/// kept apart from pages, so a new index layout or a trip to the trash reads nothing again. The device's Spotlight
/// index gets the same pages (`SpotlightIndex`). Work runs off the main thread; the store's observer only hands it
/// over. A failure is logged each time and shown once per run.
nonisolated final class SearchIndexer: Sendable {
    private let index: SearchIndex
    private let store: DocumentStore
    private let queue = DispatchQueue(label: "app.yancey.hikki.search-index", qos: .utility)
    private let files: FileTextReader
    private let spotlight = SpotlightIndex()
    /// Whether a failure has been shown this run.
    private let reported: OSAllocatedUnfairLock<Bool>

    init(index: SearchIndex, store: DocumentStore, assets: AssetStore) {
        self.index = index
        self.store = store
        let reported = OSAllocatedUnfairLock(initialState: false)
        self.reported = reported
        files = FileTextReader(
            index: index,
            read: { name in
                guard let kind = AttachmentText.kind(ofExtension: (name as NSString).pathExtension),
                    let url = assets.file(named: name)
                else { return .missing }
                return await AttachmentText.extract(from: url, kind: kind).map(FileTextReader.Outcome.text) ?? .unreadable
            },
            onError: { error in Self.fail("attachment indexing failed", error, reported: reported) },
            onRead: { count in Log.info("attachments read for search", category: "search", context: ["count": "\(count)"]) })
    }

    /// Starts writing changes through, then reconciles once (in that order, so nothing slips between).
    func start() {
        do {
            try store.observePageCommits { [weak self] changed, deletions, live in
                guard let self else { return }
                queue.async { [self] in apply(changed: changed, deletions: deletions, live: live) }
            }
        } catch {
            fail("search index observation failed", error)
        }
        queue.async { [self] in reconcile() }
    }

    /// Off the caller's actor; cancelling the calling task stops it (`CancellationError`).
    func search(_ query: String, options: SearchOptions = .standard) async throws -> [SearchHit] {
        try await index.search(query, options: options)
    }

    /// Settings → Spotlight: on pushes every page, off empties Spotlight.
    func setSpotlight(enabled: Bool) {
        queue.async { [self] in
            if enabled {
                do {
                    spotlight.reseed(try store.allDocuments().filter { $0.deletedAt == nil }.map(Self.document))
                } catch {
                    Log.error("spotlight seeding failed: \(error)", category: "search")
                }
            } else {
                spotlight.removeAll()
            }
        }
    }

    #if DEBUG
        func debugSpotlightQuery(_ text: String) async {
            await spotlight.debugQuery(text)
        }
    #endif

    private func reconcile() {
        do {
            let stamps = try index.stamps()
            let all = try store.allDocuments()
            let live = all.filter { $0.deletedAt == nil }
            let stale = live.filter { record in
                guard let stamp = stamps[record.id] else { return true }
                return abs(stamp.timeIntervalSince(record.updatedAt)) > 0.001
            }
            let liveIDs = Set(live.map(\.id))
            let gone = stamps.keys.filter { !liveIDs.contains($0) }
            let documents = stale.map(Self.document)
            try index.index(documents)
            try index.remove(gone)
            // Spotlight follows: every page once per format, then only what changed.
            if spotlight.isEnabled {
                if spotlight.isSeeded {
                    spotlight.index(documents)
                    spotlight.remove(gone)
                } else {
                    let staleIDs = Set(stale.map(\.id))
                    spotlight.reseed(documents + live.filter { !staleIDs.contains($0.id) }.map(Self.document))
                }
            }
            Log.info(
                "search index reconciled", category: "search",
                context: ["indexed": "\(stale.count)", "removed": "\(gone.count)", "total": "\(index.count)"])
            // Texts of files no page attaches any more go; those of pages in the trash stay (a restore reads nothing).
            let trashed = all.filter { $0.deletedAt != nil }
            let pruned = try index.pruneFileTexts(alsoKeeping: Set(trashed.flatMap { $0.contentText.assets.map(\.name) }))
            if pruned > 0 { Log.info("file texts pruned", category: "search", context: ["count": "\(pruned)"]) }
            // Every file not read yet: new ones, and those that weren't on this device last time.
            enqueueFiles(try index.unreadFiles())
        } catch {
            fail("search index reconcile failed", error)
        }
    }

    private func apply(changed: [DocumentRecord], deletions: Bool, live: Set<String>?) {
        do {
            let kept = changed.filter { $0.deletedAt == nil }
            // A record whose indexed fields didn't move (a sibling renumbered, a move) needs nothing.
            let stamps = try index.stamps(of: kept.map(\.id))
            let documents = kept.filter { stamps[$0.id] != SearchStamp(title: $0.title, icon: $0.icon, updatedAt: $0.updatedAt) }
                .map(Self.document)
            try index.index(documents)
            var gone = Set(changed.filter { $0.deletedAt != nil }.map(\.id))
            if deletions, let live {
                gone.formUnion(try index.stamps().keys.filter { !live.contains($0) })
            }
            try index.remove(gone)
            spotlight.index(documents)
            spotlight.remove(Array(gone))
            enqueueFiles(try index.unreadFiles(among: documents.flatMap { $0.attachments.map(\.name) }))
        } catch {
            fail("search index update failed", error)
        }
    }

    private func enqueueFiles(_ names: [String]) {
        guard !names.isEmpty else { return }
        let files = files
        Task.detached(priority: .utility) { await files.enqueue(names) }
    }

    /// One read of the page's content serves the index and Spotlight; only files text can be read from are listed.
    private static func document(_ record: DocumentRecord) -> SearchDocument {
        let content = record.contentText
        return SearchDocument(
            id: record.id, title: record.title, icon: record.icon,
            blocks: content.blocks.map { SearchBlock(id: $0.id, isHeading: $0.isHeading, text: $0.text) },
            attachments: content.assets.filter { AttachmentText.kind(ofExtension: ($0.name as NSString).pathExtension) != nil }
                .map { SearchAttachment(name: $0.name, label: $0.label, blockId: $0.blockId) },
            updatedAt: record.updatedAt)
    }

    private func fail(_ message: String, _ error: any Error) {
        Self.fail(message, error, reported: reported)
    }

    /// Logged every time; the user hears of it once per run (`searchIndexFailed`), not on every autosave.
    private static func fail(_ message: String, _ error: any Error, reported: OSAllocatedUnfairLock<Bool>) {
        let first = reported.withLock { reported in
            defer { reported = true }
            return !reported
        }
        if first {
            Toasts.report(.searchIndexFailed, error, category: "search", context: ["step": message])
        } else {
            Log.error("\(message): \(error)", category: "search")
        }
    }
}
