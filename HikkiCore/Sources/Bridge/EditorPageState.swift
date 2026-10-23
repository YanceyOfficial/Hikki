import Foundation

/// What an editor (web view) was last told about the pages — the page index it names links with
/// (`window.hikki.setPages`) and whether the page it shows is locked (`window.hikki.setLocked`) — so the native side
/// sends each only when it changed: a page's body saved changes neither, and the index is the whole workspace.
public struct EditorPageState: Sendable {
    /// One page as the editor's index knows it.
    public struct Entry: Equatable, Sendable {
        public let id: String
        public let title: String
        public let icon: String?

        public init(_ page: PageSummary) {
            id = page.id
            title = page.title
            icon = page.icon
        }
    }

    /// The index last sent; nil before the first.
    public private(set) var sentIndex: [Entry]?
    /// The page the editor shows and whether it was locked when last told (by its load, or by `setLocked`).
    public private(set) var shown: (docId: String, locked: Bool)?

    public init() {}

    /// The index for `pages`, or nil when the editor already has exactly that one. Marks it sent.
    public mutating func index(for pages: [PageSummary]) -> [Entry]? {
        let entries = pages.map(Entry.init)
        guard entries != sentIndex else { return nil }
        sentIndex = entries
        return entries
    }

    /// The editor reloaded (a crashed web process): it knows nothing until told again.
    public mutating func reset() {
        self = Self()
    }

    /// The editor loaded `docId` with its lock state (the load payload carries it).
    public mutating func loaded(_ docId: String?, locked: Bool) {
        shown = docId.map { ($0, locked) }
    }

    /// The lock state to send for the page shown, or nil when the editor already has it — or shows another page than
    /// `docId` (still loading it: that load carries the page's own state). `readOnly`: every page is locked (the
    /// trial is over, `Access.expired`).
    public mutating func lockChange(showing docId: String?, in tree: PageTree, readOnly: Bool = false) -> Bool? {
        guard let shown, let docId, shown.docId == docId, let page = tree.page(docId) else { return nil }
        let locked = page.isLocked || readOnly
        guard locked != shown.locked else { return nil }
        self.shown = (docId, locked)
        return locked
    }
}
