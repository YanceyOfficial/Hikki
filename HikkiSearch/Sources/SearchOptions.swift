import Foundation

/// Where a search looks (⌘K's chips): everywhere, only titles, only the page's own text (body and headings), or
/// only the files attached to pages.
public enum SearchScope: String, CaseIterable, Sendable {
    case all, titles, text, files
}

/// How results are ordered (⌘K's sort menu): best match first, or most recently edited first.
public enum SearchSort: String, CaseIterable, Sendable {
    case relevance, edited
}

/// A search's filter and order together.
public struct SearchOptions: Equatable, Sendable {
    public var scope: SearchScope
    public var sort: SearchSort

    public init(scope: SearchScope = .all, sort: SearchSort = .relevance) {
        self.scope = scope
        self.sort = sort
    }

    public static let standard = SearchOptions()
}

/// A line of the search palette's list: a page, another place it matches, or the toggle under those that opens,
/// extends or folds them (VS Code's / Obsidian's results).
public enum SearchListItem: Identifiable, Equatable, Sendable {
    case page(SearchHit)
    case match(SearchHit, SearchMatch)
    case toggle(SearchHit, Toggle)

    public enum Toggle: Equatable, Sendable {
        /// Closed: "N more matches".
        case expand(count: Int)
        /// Open with the first few: "Show N more".
        case showAll(remaining: Int)
        /// Open with all of them: "Hide matches".
        case collapse
    }

    public var id: String {
        switch self {
        case .page(let hit): hit.id
        case .match(let hit, let match): "\(hit.id)#\(match.blockId)"
        case .toggle(let hit, _): "\(hit.id)#toggle"
        }
    }

    /// How many other matches an opened page shows before "Show N more".
    public static let firstMatches = 5

    /// Every line in order: each page, then — for a page with other matches — the toggle, after the matches shown
    /// when the page is `expanded` (the first few, or all of them when it is `showingAll`).
    public static func list(_ hits: [SearchHit], expanded: Set<String>, showingAll: Set<String>) -> [SearchListItem] {
        hits.flatMap { hit -> [SearchListItem] in
            let more = hit.moreMatches
            guard !more.isEmpty, hit.attachment == nil else { return [.page(hit)] }
            guard expanded.contains(hit.id) else { return [.page(hit), .toggle(hit, .expand(count: more.count))] }
            let shown = showingAll.contains(hit.id) ? more : Array(more.prefix(firstMatches))
            let toggle: Toggle = shown.count < more.count ? .showAll(remaining: more.count - shown.count) : .collapse
            return [.page(hit)] + shown.map { .match(hit, $0) } + [.toggle(hit, toggle)]
        }
    }
}
