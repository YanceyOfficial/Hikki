import Foundation
import HikkiCore
import HikkiSearch
import Observation
import Security

/// Settings → Search → Semantic search. Hikki only reads and writes vectors: the model runs in Ollama (or anything
/// that speaks the OpenAI-compatible embeddings API), so a better model is a new name here, not new code.
enum SemanticPreferences {
    static let enabledKey = "semantic.enabled"
    static let endpointKey = "semantic.endpoint"
    static let modelKey = "semantic.model"
    static let defaultEndpoint = "http://localhost:11434/v1"
    static let defaultModel = "qllama/multilingual-e5-small"
    /// Keychain account of the optional API key (OpenAI and other hosted endpoints; Ollama needs none), one per
    /// origin: a key is only ever sent back to the scheme, host and port it was entered for — editing the address
    /// (half-typed hosts included) never carries it somewhere else.
    static func apiKeyAccount(for endpoint: String) -> String? {
        URL(string: endpoint.trimmingCharacters(in: .whitespaces)).flatMap(OpenAICompatibleEmbeddings.origin(of:))
            .map { "semantic.apiKey|\($0)" }
    }

    static func apiKey(for endpoint: String) -> String? {
        apiKeyAccount(for: endpoint).flatMap(Keychain.read)
    }

    /// The provider the settings describe, or nil when semantic search is off or the address isn't a URL.
    static func provider(_ defaults: UserDefaults = .standard) -> OpenAICompatibleEmbeddings? {
        guard defaults.bool(forKey: enabledKey) else { return nil }
        let endpoint = (defaults.string(forKey: endpointKey) ?? defaultEndpoint).trimmingCharacters(in: .whitespaces)
        let model = (defaults.string(forKey: modelKey) ?? defaultModel).trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: endpoint), url.scheme == "http" || url.scheme == "https", url.host() != nil,
            !model.isEmpty
        else { return nil }
        return OpenAICompatibleEmbeddings(baseURL: url, model: model, apiKey: apiKey(for: endpoint))
    }
}

/// A generic password in the app's Keychain items (the semantic search API key).
nonisolated enum Keychain {
    private static let service = "app.yancey.hikki"

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account, kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Stores `value`, or removes the item when it's empty.
    static func write(_ value: String, for account: String) {
        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(match as CFDictionary)
        guard !value.isEmpty else { return }
        var item = match
        item[kSecValueData as String] = Data(value.utf8)
        let status = SecItemAdd(item as CFDictionary, nil)
        if status != errSecSuccess { Log.warn("keychain write failed", category: "semantic", context: ["status": "\(status)"]) }
    }
}

/// Where the embedding of pages stands, for Settings.
nonisolated enum SemanticStatus: Equatable, Sendable {
    case off
    /// Embedding pages: `done` of `total` in this pass.
    case working(done: Int, total: Int)
    /// Every page embedded.
    case ready(pages: Int)
    case failed(EmbeddingError)
}

/// Semantic search for the app: the indexer's status for Settings and the query's vector for ⌘K.
@Observable
final class SemanticSearch {
    private(set) var status: SemanticStatus = .off
    @ObservationIgnored let indexer: SemanticIndexer
    @ObservationIgnored private var provider: OpenAICompatibleEmbeddings?

    init(indexer: SemanticIndexer) {
        self.indexer = indexer
        let report: @Sendable (SemanticStatus) -> Void = { [weak self] status in
            Task { @MainActor in self?.status = status }
        }
        Task { await indexer.onStatus(report) }
        reconfigure()
    }

    var isEnabled: Bool { provider != nil }

    /// Settings changed (on/off, address, model, key): the indexer starts over with the new provider — a new model
    /// re-embeds every page, the same one only what changed.
    func reconfigure() {
        provider = SemanticPreferences.provider()
        if provider == nil { status = .off }
        let provider = provider
        Task { await indexer.configure(provider) }
    }

    /// The query's vector, or nil (off, or the model can't be reached — word search carries on alone).
    func queryVector(_ text: String) async -> [Float]? {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let provider, !query.isEmpty else { return nil }
        return try? await provider.embed([query], kind: .query).first
    }

    /// The models the configured endpoint offers.
    func availableModels() async throws -> [String] {
        let defaults = UserDefaults.standard
        let endpoint = defaults.string(forKey: SemanticPreferences.endpointKey) ?? SemanticPreferences.defaultEndpoint
        guard let url = URL(string: endpoint.trimmingCharacters(in: .whitespaces)), url.host() != nil else {
            throw EmbeddingError.unreachable
        }
        return try await OpenAICompatibleEmbeddings(
            baseURL: url, model: "", apiKey: SemanticPreferences.apiKey(for: endpoint)
        ).models()
    }
}

/// Embeds pages for semantic search, off the main thread. A page is embedded once it has been left alone for
/// `quietPeriod` (typing doesn't send a request per keystroke), and a pass at launch and after a settings change
/// catches up every page whose edited time differs from its vectors' (`backfill`). Only passages whose text changed
/// are sent; the rest keep their vectors. When the model can't be reached the pass stops and retries later.
actor SemanticIndexer {
    static let quietPeriod: Duration = .seconds(30)
    static let retryAfter: Duration = .seconds(300)
    /// Passages per request.
    static let batchSize = 16

    private let index: SearchIndex
    private let store: DocumentStore
    private var provider: (any EmbeddingProvider)?
    private var pending = Set<String>()
    private var quiet: Task<Void, Never>?
    private var retry: Task<Void, Never>?
    private var pass: Task<Void, Never>?
    private var report: (@Sendable (SemanticStatus) -> Void)?
    private let quietPeriod: Duration

    init(index: SearchIndex, store: DocumentStore, quietPeriod: Duration = SemanticIndexer.quietPeriod) {
        self.index = index
        self.store = store
        self.quietPeriod = quietPeriod
    }

    func onStatus(_ report: @escaping @Sendable (SemanticStatus) -> Void) {
        self.report = report
    }

    func configure(_ provider: (any EmbeddingProvider)?) {
        self.provider = provider
        quiet?.cancel()
        retry?.cancel()
        pass?.cancel()
        pending.removeAll()
        guard let provider else {
            report?(.off)
            return
        }
        do {
            if try index.useEmbeddingModel(provider.identity) {
                Log.info("semantic index reset for a new model", category: "semantic")
            }
        } catch {
            Log.error("semantic index model switch failed: \(error)", category: "semantic")
        }
        backfill()
    }

    /// Pages were edited: embed them once they've been quiet for a while.
    func pagesChanged(_ ids: [String]) {
        guard provider != nil, !ids.isEmpty else { return }
        pending.formUnion(ids)
        quiet?.cancel()
        let delay = quietPeriod
        quiet = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.flushPending()
        }
    }

    /// Every live page whose vectors are missing or older than the page.
    func backfill() {
        guard provider != nil else { return }
        pass?.cancel()
        pass = Task { [weak self] in await self?.runBackfill() }
    }

    /// Waits for the running pass (tests).
    func idle() async {
        await pass?.value
    }

    private func flushPending() async {
        let ids = pending
        pending.removeAll()
        let records = ids.compactMap { try? store.document(id: $0) }.filter { $0.deletedAt == nil }
        await embed(records, total: records.count)
    }

    private func runBackfill() async {
        do {
            let stamps = try index.embeddingStamps()
            let stale = try store.allDocuments()
                .filter { record in
                    guard record.deletedAt == nil else { return false }
                    guard let stamp = stamps[record.id] else { return true }
                    return abs(stamp.timeIntervalSince(record.updatedAt)) > 0.001
                }
                .sorted { $0.updatedAt > $1.updatedAt }
            Log.info("semantic backfill", category: "semantic", context: ["stale": "\(stale.count)"])
            await embed(stale, total: stale.count)
        } catch {
            Log.error("semantic backfill failed: \(error)", category: "semantic")
        }
    }

    private func embed(_ records: [DocumentRecord], total: Int) async {
        guard let provider else { return }
        var done = 0
        if total > 0 { report?(.working(done: 0, total: total)) }
        for record in records {
            if Task.isCancelled { return }
            do {
                try await embed(record, with: provider)
                done += 1
                report?(.working(done: done, total: total))
            } catch let error as EmbeddingError {
                Log.warn("embedding failed", category: "semantic", context: ["error": "\(error)", "docId": record.id])
                report?(.failed(error))
                scheduleRetry()
                return
            } catch {
                Log.error("embedding store failed: \(error)", category: "semantic", context: ["docId": record.id])
            }
        }
        report?(.ready(pages: index.embeddedCount))
    }

    private func embed(_ record: DocumentRecord, with provider: any EmbeddingProvider) async throws {
        let chunks = Chunker.chunks(title: record.title, headings: record.headings, text: record.plainText)
        let known = try index.passageVectors(of: record.id)
        let missing = chunks.filter { known[$0.hash] == nil }
        var vectors = known
        for start in stride(from: 0, to: missing.count, by: Self.batchSize) {
            let batch = Array(missing[start..<min(start + Self.batchSize, missing.count)])
            let embedded = try await provider.embed(batch.map(\.text), kind: .passage)
            for (chunk, vector) in zip(batch, embedded) { vectors[chunk.hash] = vector }
        }
        try index.storeEmbeddings(
            pageId: record.id, updatedAt: record.updatedAt,
            passages: chunks.compactMap { chunk in vectors[chunk.hash].map { (chunk, $0) } })
    }

    private func scheduleRetry() {
        retry?.cancel()
        retry = Task { [weak self] in
            try? await Task.sleep(for: Self.retryAfter)
            guard !Task.isCancelled else { return }
            await self?.backfill()
        }
    }
}
