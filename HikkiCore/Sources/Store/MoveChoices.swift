import Foundation

/// One row of the Move to picker (Notion's "Move page to…"): a page the moved page may go inside, as the picker draws
/// it — in the tree (top-level pages, a disclosure for their children) or as a search result (with its path).
public struct MoveChoice: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let icon: String?
    /// Indentation in the tree; 0 for every search result.
    public let depth: Int
    /// It has children the page may move into (its own subtree never counts), so the tree offers a disclosure.
    public let hasChildren: Bool
    public let isExpanded: Bool
    /// Where the page is now: shown, but picking it would change nothing.
    public let isCurrentParent: Bool
    /// Search results: the titles above it, root first (empty in the tree and at the top level).
    public let path: [String]
}

extension PageTree {
    /// The Move to picker's rows for moving `id`. Without a query: the top-level pages, the children of those in
    /// `expanded` under them. With one: every page whose title holds each of its words (no case, no accents — "cafe"
    /// finds Café), titles starting with the query first, then in sidebar order. Never the page itself or anything
    /// inside it — a page can't move into its own subtree.
    public func moveChoices(for id: String, query: String = "", expanded: Set<String> = []) -> [MoveChoice] {
        let parent = page(id)?.parentId
        let terms = Self.moveFold(query).split(whereSeparator: \.isWhitespace).map(String.init)
        var rows: [MoveChoice] = []
        if terms.isEmpty {
            func walk(_ nodes: [PageNode], _ depth: Int) {
                for node in nodes where node.id != id {
                    let movable = node.children.contains { $0.id != id }
                    let open = movable && expanded.contains(node.id)
                    rows.append(
                        MoveChoice(
                            id: node.id, title: node.page.title, icon: node.page.icon, depth: depth, hasChildren: movable,
                            isExpanded: open, isCurrentParent: node.id == parent, path: []))
                    if open { walk(node.children, depth + 1) }
                }
            }
            walk(roots, 0)
            return rows
        }
        let whole = terms.joined(separator: " ")
        var leading: [MoveChoice] = []
        func search(_ nodes: [PageNode], _ path: [String]) {
            for node in nodes where node.id != id {
                let title = Self.moveFold(node.page.title)
                if terms.allSatisfy({ title.contains($0) }) {
                    let row = MoveChoice(
                        id: node.id, title: node.page.title, icon: node.page.icon, depth: 0, hasChildren: false,
                        isExpanded: false, isCurrentParent: node.id == parent, path: path)
                    if title.hasPrefix(whole) { leading.append(row) } else { rows.append(row) }
                }
                search(node.children, path + [node.page.title])
            }
        }
        search(roots, [])
        return leading + rows
    }

    /// Whether the page shows at the top level (no parent, or one that isn't there): Move to's "top level" is a no-op.
    public func isTopLevel(_ id: String) -> Bool {
        roots.contains { $0.id == id }
    }

    /// Case and accents don't matter (as in search, `SearchQuery.fold`).
    static func moveFold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
