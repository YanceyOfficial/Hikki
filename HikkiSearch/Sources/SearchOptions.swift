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
