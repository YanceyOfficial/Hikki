import Foundation

/// What the iPhone's Home shows of the page list, worked out once per change of the tree rather than on every redraw:
/// the cards of pages edited last, this week's pages, and this week's edits beyond the cards.
public struct HomeDigest: Equatable, Sendable {
    /// The pages edited last, newest first ("Jump back in").
    public let recents: [PageSummary]
    /// Pages edited in the last 7 days, newest first (Ask AI's "this week").
    public let weekPages: [PageSummary]

    public static let recentLimit = 8
    public static let weekLimit = 10

    public init(pages: [PageSummary], now: Date = .now, calendar: Calendar = .current) {
        let newestFirst = pages.sorted { $0.updatedAt > $1.updatedAt }
        recents = Array(newestFirst.prefix(Self.recentLimit))
        let start = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        weekPages = Array(newestFirst.lazy.filter { $0.updatedAt >= start }.prefix(Self.weekLimit))
    }

    /// This week's edits not already shown as cards.
    public var recentlyEdited: [PageSummary] {
        Array(weekPages.dropFirst(recents.count).prefix(Self.weekLimit))
    }
}
