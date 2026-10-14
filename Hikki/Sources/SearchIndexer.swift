import Foundation
import HikkiCore
import HikkiSearch

/// Feeds the search index from the store: every committed page change as it happens, and a reconcile at launch —
/// pages whose edited time differs from the index's are indexed again, pages gone from the store (deleted, or in
/// the trash) are dropped. Work runs on its own queue; the store's observer only hands it over.
nonisolated final class SearchIndexer: Sendable {
    private let index: SearchIndex
    private let store: DocumentStore
    private let queue = DispatchQueue(label: "app.yancey.hikki.search-index", qos: .utility)

    init(index: SearchIndex, store: DocumentStore) {
        self.index = index
        self.store = store
    }

    /// Starts writing changes through, then reconciles once (in that order, so nothing slips between).
    func start() {
        do {
            try store.observePageCommits { [weak self] changed, deletions, live in
                self?.queue.async { self?.apply(changed: changed, deletions: deletions, live: live) }
            }
        } catch {
            Log.error("search index observation failed: \(error)", category: "search")
        }
        queue.async { [self] in reconcile() }
    }

    func search(_ query: String) throws -> [SearchHit] {
        try index.search(query)
    }

    private func reconcile() {
        do {
            let stamps = try index.stamps()
            let live = try store.allDocuments().filter { $0.deletedAt == nil }
            let stale = live.filter { record in
                guard let stamp = stamps[record.id] else { return true }
                return abs(stamp.timeIntervalSince(record.updatedAt)) > 0.001
            }
            let liveIDs = Set(live.map(\.id))
            let gone = stamps.keys.filter { !liveIDs.contains($0) }
            try index.index(stale.map(Self.document))
            try index.remove(gone)
            Log.info(
                "search index reconciled", category: "search",
                context: ["indexed": "\(stale.count)", "removed": "\(gone.count)", "total": "\(index.count)"])
        } catch {
            Log.error("search index reconcile failed: \(error)", category: "search")
        }
    }

    private func apply(changed: [DocumentRecord], deletions: Bool, live: Set<String>?) {
        do {
            try index.index(changed.filter { $0.deletedAt == nil }.map(Self.document))
            var gone = Set(changed.filter { $0.deletedAt != nil }.map(\.id))
            if deletions, let live {
                gone.formUnion(try index.stamps().keys.filter { !live.contains($0) })
            }
            try index.remove(gone)
        } catch {
            Log.error("search index update failed: \(error)", category: "search")
        }
    }

    private static func document(_ record: DocumentRecord) -> SearchDocument {
        SearchDocument(
            id: record.id, title: record.title, icon: record.icon, headings: record.headings, text: record.plainText,
            updatedAt: record.updatedAt)
    }
}
