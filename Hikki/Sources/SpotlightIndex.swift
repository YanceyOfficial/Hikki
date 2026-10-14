import CoreSpotlight
import Foundation
import HikkiCore
import HikkiSearch

nonisolated enum SpotlightPreferences {
    /// Settings → Editor → Spotlight (default on).
    static let enabledKey = "spotlightIndexing"
    /// The item format last pushed in full; a different `version` pushes every page again.
    static let seededKey = "spotlightSeededVersion"
    static let version = 1
}

/// The device's Spotlight index of pages (Core Spotlight), fed beside the search index by `SearchIndexer`:
/// a page found in system search opens in Hikki (`ContentView` continues the activity). Private to the device;
/// off with one switch, which also empties it.
nonisolated final class SpotlightIndex: Sendable {
    /// Core Spotlight's index is safe to call from any thread; the type just isn't marked so.
    private nonisolated(unsafe) let index = CSSearchableIndex.default()

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: SpotlightPreferences.enabledKey) as? Bool ?? true
    }

    /// Whether every page has been pushed once in the current format.
    var isSeeded: Bool {
        get { UserDefaults.standard.integer(forKey: SpotlightPreferences.seededKey) == SpotlightPreferences.version }
        set {
            UserDefaults.standard.set(newValue ? SpotlightPreferences.version : 0, forKey: SpotlightPreferences.seededKey)
        }
    }

    func index(_ documents: [SearchDocument]) {
        guard isEnabled, !documents.isEmpty, CSSearchableIndex.isIndexingAvailable() else { return }
        let untitled = String(localized: "app:page.untitled")
        let items = documents.map { SpotlightItems.item(for: $0, untitled: untitled) }
        index.indexSearchableItems(items) { error in
            if let error { Log.error("spotlight indexing failed: \(error)", category: "search") }
        }
    }

    func remove(_ ids: [String]) {
        guard !ids.isEmpty, CSSearchableIndex.isIndexingAvailable() else { return }
        index.deleteSearchableItems(withIdentifiers: ids) { error in
            if let error { Log.error("spotlight removal failed: \(error)", category: "search") }
        }
    }

    /// Everything out (the switch turned off, or the format changed).
    func removeAll() {
        isSeeded = false
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        index.deleteSearchableItems(withDomainIdentifiers: [SpotlightItems.domain]) { error in
            if let error { Log.error("spotlight clearing failed: \(error)", category: "search") }
        }
    }

    #if DEBUG
        /// What Spotlight ranks for `text` among our pages (ids only), and how many a plain title/text search finds:
        /// for judging the system's semantic matching before it gets a place in the palette.
        func debugQuery(_ text: String) async {
            CSUserQuery.prepare()
            let context = CSUserQueryContext()
            context.fetchAttributes = ["title"]
            context.enableRankedResults = true
            context.maxRankedResultCount = 10
            let query = CSUserQuery(userQueryString: text, userQueryContext: context)
            var ranked: [String] = []
            do {
                for try await response in query.responses {
                    if case .item(let item) = response { ranked.append(item.item.uniqueIdentifier) }
                }
            } catch {
                Log.error("spotlight user query failed: \(error)", category: "search")
            }
            let escaped = text.replacingOccurrences(of: "\"", with: "\\\"")
            let plain = CSSearchQuery(
                queryString: "title == \"*\(escaped)*\"cd || textContent == \"*\(escaped)*\"cd", queryContext: nil)
            var found: [String] = []
            do {
                for try await result in plain.results { found.append(result.item.uniqueIdentifier) }
            } catch {
                Log.error("spotlight search query failed: \(error)", category: "search")
            }
            Log.info(
                "spotlight query", category: "search",
                context: ["ranked": ranked.joined(separator: ","), "plain": found.joined(separator: ",")])
        }
    #endif
}
