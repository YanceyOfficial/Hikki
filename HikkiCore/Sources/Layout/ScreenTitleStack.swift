import Foundation

/// Every titled screen on display, and which one is in front — what iOS names a screenshot after (actovia's). A
/// screen nested in another (a sheet over the screen that presents it) is deeper; at the same depth the one shown last
/// is in front, so a sheet wins over what is beneath it, and when it goes the title beneath is back.
public struct ScreenTitleStack: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        var depth: Int
        var order: Int
        var title: String
    }

    private var entries: [UUID: Entry] = [:]
    private var nextOrder = 0

    public init() {}

    /// A screen appearing (in front of the others at its depth), or a shown screen's title changing (in place).
    public mutating func show(_ id: UUID, depth: Int, title: String) {
        if entries[id] != nil {
            entries[id]?.title = title
        } else {
            entries[id] = Entry(depth: depth, order: nextOrder, title: title)
            nextOrder += 1
        }
    }

    public mutating func hide(_ id: UUID) { entries[id] = nil }

    /// The title of the screen in front, if any screen is titled.
    public var front: String? {
        entries.values.max { ($0.depth, $0.order) < ($1.depth, $1.order) }?.title
    }
}
