import Foundation
import HikkiCore
import HikkiSearch

/// Feeds the search index from the store: every committed page change as it happens, and a reconcile at launch —
/// pages whose edited time differs from the index's are indexed again, pages gone from the store (deleted, or in
/// the trash) are dropped. The files a page attaches (PDFs, images) have their text read afterwards, one at a
/// time at low priority, and only once per file. The device's Spotlight index gets the same pages (`SpotlightIndex`).
/// Work runs off the main thread; the store's observer only hands it over.
nonisolated final class SearchIndexer: Sendable {
    private let index: SearchIndex
    private let store: DocumentStore
    private let assets: AssetStore
    private let queue = DispatchQueue(label: "app.yancey.hikki.search-index", qos: .utility)
    private let attachments: AttachmentReader
    private let spotlight = SpotlightIndex()

    init(index: SearchIndex, store: DocumentStore, assets: AssetStore) {
        self.index = index
        self.store = store
        self.assets = assets
        attachments = AttachmentReader(index: index, assets: assets)
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

    func search(_ query: String, options: SearchOptions = .standard) throws -> [SearchHit] {
        try index.search(query, options: options)
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
            let live = try store.allDocuments().filter { $0.deletedAt == nil }
            let stale = live.filter { record in
                guard let stamp = stamps[record.id] else { return true }
                return abs(stamp.timeIntervalSince(record.updatedAt)) > 0.001
            }
            let liveIDs = Set(live.map(\.id))
            let gone = stamps.keys.filter { !liveIDs.contains($0) }
            try index.index(stale.map(Self.document))
            try index.remove(gone)
            // Spotlight follows: every page once per format, then only what changed.
            if spotlight.isEnabled {
                if spotlight.isSeeded {
                    spotlight.index(stale.map(Self.document))
                    spotlight.remove(gone)
                } else {
                    spotlight.reseed(live.map(Self.document))
                }
            }
            Log.info(
                "search index reconciled", category: "search",
                context: ["indexed": "\(stale.count)", "removed": "\(gone.count)", "total": "\(index.count)"])
            // Every live page's attachments are looked at: a file read earlier is skipped, a new one read.
            readAttachments(of: live)
        } catch {
            Log.error("search index reconcile failed: \(error)", category: "search")
        }
    }

    private func apply(changed: [DocumentRecord], deletions: Bool, live: Set<String>?) {
        do {
            let kept = changed.filter { $0.deletedAt == nil }
            try index.index(kept.map(Self.document))
            var gone = Set(changed.filter { $0.deletedAt != nil }.map(\.id))
            if deletions, let live {
                gone.formUnion(try index.stamps().keys.filter { !live.contains($0) })
            }
            try index.remove(gone)
            spotlight.index(kept.map(Self.document))
            spotlight.remove(Array(gone))
            readAttachments(of: kept)
        } catch {
            Log.error("search index update failed: \(error)", category: "search")
        }
    }

    private func readAttachments(of records: [DocumentRecord]) {
        let jobs = records.map { record in
            AttachmentReader.Job(pageId: record.id, references: record.assetReferences)
        }
        guard jobs.contains(where: { !$0.references.isEmpty }) else { return }
        let attachments = attachments
        Task.detached(priority: .utility) { await attachments.process(jobs) }
    }

    private static func document(_ record: DocumentRecord) -> SearchDocument {
        SearchDocument(
            id: record.id, title: record.title, icon: record.icon, headings: record.headings, text: record.plainText,
            blocks: record.textBlocks.map { SearchBlock(id: $0.id, isHeading: $0.isHeading, text: $0.text) },
            updatedAt: record.updatedAt)
    }
}

/// Reads attached files' text into the index, one file at a time (an actor: jobs queue up behind each other).
/// A page's attachments that are no longer in it are dropped; a file attached to several pages is read once.
/// A file that isn't on this device yet (iCloud) is left for a later pass.
private actor AttachmentReader {
    struct Job: Sendable {
        var pageId: String
        var references: [AssetReference]
    }

    private let index: SearchIndex
    private let assets: AssetStore

    init(index: SearchIndex, assets: AssetStore) {
        self.index = index
        self.assets = assets
    }

    func process(_ jobs: [Job]) async {
        var read = 0
        for job in jobs {
            do {
                let wanted = job.references.filter {
                    AttachmentText.kind(ofExtension: ($0.name as NSString).pathExtension) != nil
                }
                let known = try index.attachmentNames(of: job.pageId)
                try index.removeAttachments(known.subtracting(wanted.map(\.name)), of: job.pageId)
                for reference in wanted where !known.contains(reference.name) {
                    guard let text = await text(of: reference) else { continue }
                    try index.index(attachments: [
                        SearchAttachment(name: reference.name, pageId: job.pageId, label: reference.label, text: text)
                    ])
                    read += 1
                }
            } catch {
                Log.error("attachment indexing failed: \(error)", category: "search", context: ["docId": job.pageId])
            }
        }
        if read > 0 { Log.info("attachments read for search", category: "search", context: ["count": "\(read)"]) }
    }

    /// Text read earlier for the same file, else from the file; nil when the file isn't here (yet) or unreadable.
    private func text(of reference: AssetReference) async -> String? {
        if let known = try? index.attachmentText(named: reference.name) { return known }
        guard let kind = AttachmentText.kind(ofExtension: (reference.name as NSString).pathExtension),
            let url = assets.file(named: reference.name)
        else { return nil }
        return await AttachmentText.extract(from: url, kind: kind)
    }
}
