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
        let roots = build(nil, [])
        var all: [PageSummary] = []
        func walk(_ nodes: [PageNode]) {
            for node in nodes {
                all.append(node.page)
                walk(node.children)
            }
        }
        walk(roots)
        self.roots = roots
        self.byId = byId
        self.all = all
    }

    public func page(_ id: String) -> PageSummary? { byId[id] }

    /// Every live page, in tree order (depth first): the index the editor names links with. Built once with the tree
    /// (views and the editors read it on every tree change).
    public let all: [PageSummary]

    /// "Move to" choices for a page, depth-first in sidebar order with their depth: every page except the
    /// page itself and its own subtree (it can't move inside itself) and its current parent (a no-op).
    public func moveTargets(for id: String) -> [(page: PageSummary, depth: Int)] {
        let parent = byId[id]?.parentId
        var out: [(page: PageSummary, depth: Int)] = []
        func walk(_ nodes: [PageNode], _ depth: Int) {
            for node in nodes where node.id != id {
                if node.id != parent { out.append((node.page, depth)) }
                walk(node.children, depth + 1)
            }
        }
        walk(roots, 0)
        return out
    }

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

    /// The sidebar's page rows: the tree flattened depth first, a page's children following it only while it is in
    /// `expanded`. Each row holds only what the row draws (no edited time or word count), so a save that changes
    /// neither title nor icon leaves every row equal and the sidebar redraws none of them.
    public func visibleRows(expanded: Set<String>) -> [SidebarRow] {
        var rows: [SidebarRow] = []
        func walk(_ nodes: [PageNode], _ depth: Int) {
            for node in nodes {
                let open = !node.children.isEmpty && expanded.contains(node.id)
                rows.append(
                    SidebarRow(
                        id: node.id, title: node.page.title, icon: node.page.icon, depth: depth,
                        hasChildren: !node.children.isEmpty, isExpanded: open))
                if open { walk(node.children, depth + 1) }
            }
        }
        walk(roots, 0)
        return rows
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

/// Where a dragged sidebar row lands relative to the row under the pointer.
/// One page row of the sidebar's tree (`PageTree.visibleRows`): plain values, compared to skip redrawing a row.
public struct SidebarRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let icon: String?
    public let depth: Int
    public let hasChildren: Bool
    public let isExpanded: Bool
}

public enum DropZone: Equatable, Sendable {
    case before, inside, after

    /// Top quarter → before, bottom quarter → after, the middle → nest inside.
    public init(y: Double, height: Double) {
        if y < height * 0.25 {
            self = .before
        } else if y > height * 0.75 {
            self = .after
        } else {
            self = .inside
        }
    }
}

extension PageTree {
    public struct MoveDestination: Equatable, Sendable {
        public var parentId: String?
        public var index: Int
    }

    /// The `DocumentStore.move` arguments for dropping `dragged` onto `target`, or nil when the drop
    /// is invalid (onto itself or into its own subtree).
    public func destination(dropping dragged: String, onto target: String, zone: DropZone) -> MoveDestination? {
        guard dragged != target, page(dragged) != nil, let targetPage = page(target) else { return nil }
        // The target (or the parent it would land under) must not be inside the dragged subtree.
        if path(to: target).contains(where: { $0.id == dragged }) { return nil }
        switch zone {
        case .inside:
            return MoveDestination(parentId: target, index: Int.max)
        case .before, .after:
            let siblings = children(of: targetPage.parentId).filter { $0 != dragged }
            guard let position = siblings.firstIndex(of: target) else { return nil }
            return MoveDestination(parentId: targetPage.parentId, index: zone == .before ? position : position + 1)
        }
    }

    /// Child ids of `parentId` (nil = top level) in sidebar order.
    public func children(of parentId: String?) -> [String] {
        func find(_ nodes: [PageNode]) -> [PageNode]? {
            for node in nodes {
                if node.id == parentId { return node.children }
                if let found = find(node.children) { return found }
            }
            return nil
        }
        let nodes = parentId == nil ? roots : (find(roots) ?? [])
        return nodes.map(\.id)
    }
}
