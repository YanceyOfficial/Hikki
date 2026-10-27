import Foundation

/// One change Ask AI proposes to the open page, reviewed card by card (approve, skip, edit). It names blocks by their
/// ids; the editor applies it and reports how it went (`aiChange`). Kept with the answer that proposed it
/// (`ChatTurn.changes`), so the cards come back with the conversation. Page text: never logged.
public struct AIPageChange: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// `block`'s text becomes `html`.
        case rewrite
        /// A new block of `blockType` with `html`, after `after` (nil: at the top of the page).
        case insert
        /// `block` goes after `after` (nil: to the top).
        case move
        /// `block` is removed.
        case delete
    }

    public enum Status: String, Codable, Sendable {
        case pending, approved, skipped
        /// Approved, then the caret put there to change it further.
        case edited
        /// The page changed where it applies (or it never fit the page): no longer offered.
        case stale

        /// Whether the change was looked at (it goes from the cards to the reviewed stack).
        public var isReviewed: Bool { self != .pending }
    }

    public var id: String
    public var kind: Kind
    public var block: String?
    public var after: String?
    public var html: String?
    /// For an insert: paragraph, heading1, heading2 or heading3 (inside a list, a new item).
    public var blockType: String?
    /// What changes, in a few words (the card's title).
    public var title: String
    public var why: String?
    public var status: Status
    /// The block's text before and after the review (plain text, for the reviewed stack's diff).
    public var beforeText: String?
    public var afterText: String?
    /// When it was reviewed (the reviewed stack's order).
    public var reviewedAt: Date?

    public init(
        id: String, kind: Kind, block: String? = nil, after: String? = nil, html: String? = nil, blockType: String? = nil,
        title: String, why: String? = nil, status: Status = .pending, beforeText: String? = nil, afterText: String? = nil,
        reviewedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.block = block
        self.after = after
        self.html = html
        self.blockType = blockType
        self.title = title
        self.why = why
        self.status = status
        self.beforeText = beforeText
        self.afterText = afterText
        self.reviewedAt = reviewedAt
    }

    /// What a card shows of the change before it is reviewed: an insert's new text (added), a rewrite's words as a
    /// diff of the block's text against the new one (removals struck, additions marked), a block to delete struck
    /// through, a moved block as it reads — from `beforeText` / `afterText`, filled when the change is proposed from
    /// the blocks the model was given (ISSUE-255: a card said only "Insert"). Empty without them.
    public var preview: [DiffRun] {
        let before = beforeText ?? ""
        let after = afterText ?? ""
        switch kind {
        case .insert: return after.isEmpty ? [] : [DiffRun(after, .added)]
        case .delete: return before.isEmpty ? [] : [DiffRun(before, .removed)]
        case .move: return before.isEmpty ? [] : [DiffRun(before, .same)]
        case .rewrite: return before.isEmpty && after.isEmpty ? [] : PageDiff.words(old: before, new: after)
        }
    }

    /// The change as `window.hikki.aiChanges` takes it.
    public var bridgeValue: [String: Any] {
        var value: [String: Any] = ["id": id, "kind": kind.rawValue, "title": title, "status": status.rawValue]
        if let block { value["block"] = block }
        if let after { value["after"] = after }
        if let html { value["html"] = html }
        if let blockType { value["type"] = blockType }
        if let why { value["why"] = why }
        return value
    }

    /// Of two copies of a change (two devices), the one further along: a reviewed one over a pending one.
    public static func merged(_ a: AIPageChange, _ b: AIPageChange) -> AIPageChange {
        a.status == .pending && b.status != .pending ? b : a
    }
}
