import Foundation

/// The sidebar's page hierarchy, built in memory from the flat summary list.
public struct PageNode: Identifiable, Equatable, Sendable {
    public var page: PageSummary
    public var children: [PageNode]
    public var id: String { page.id }
}

public struct PageTree: Equatable, Sendable {
    public let roots: [PageNode]
    private let byId: [String: PageSummary]

    /// `pages` must already be in sibling order (as `DocumentStore.pages()` returns them).
    /// Pages whose parent is missing (e.g. trashed separately) are shown at the top level.
    public init(_ pages: [PageSummary]) {
        let byId = Dictionary(pages.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var children: [String?: [PageSummary]] = [:]
        for page in pages {
            let parent = page.parentId.flatMap { byId[$0] != nil ? $0 : nil }
            children[parent, default: []].append(page)
        }
        func build(_ parent: String?, _ visited: Set<String>) -> [PageNode] {
            (children[parent] ?? []).compactMap { page in
                guard !visited.contains(page.id) else { return nil }  // cycle guard
                return PageNode(page: page, children: build(page.id, visited.union([page.id])))
            }
        }
        self.roots = build(nil, [])
        self.byId = byId
    }

    public func page(_ id: String) -> PageSummary? { byId[id] }

    /// Root → … → the page itself.
    public func path(to id: String) -> [PageSummary] {
        var path: [PageSummary] = []
        var current = byId[id]
        var seen = Set<String>()
        while let page = current, seen.insert(page.id).inserted {
            path.insert(page, at: 0)
            current = page.parentId.flatMap { byId[$0] }
        }
        return path
    }

    /// Favorites, most recently favorited first.
    public var favorites: [PageSummary] {
        byId.values.filter(\.isFavorite).sorted { ($0.favoritedAt ?? .distantPast) > ($1.favoritedAt ?? .distantPast) }
    }

    /// Most recently edited pages (Home).
    public func recent(limit: Int) -> [PageSummary] {
        Array(byId.values.sorted { $0.updatedAt > $1.updatedAt }.prefix(limit))
    }
}
