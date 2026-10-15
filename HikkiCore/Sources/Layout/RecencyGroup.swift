import Foundation

/// Which heading a page edited at `date` falls under in a list ordered by recency (the phone's All pages): today,
/// yesterday, earlier in the last seven days, earlier this year (by month), or an earlier year.
public enum RecencyGroup: Hashable, Sendable, Comparable {
    case today
    case yesterday
    case thisWeek
    /// A month of this year (1–12), before the last seven days.
    case month(Int)
    case year(Int)

    public init(_ date: Date, now: Date = .now, calendar: Calendar = .current) {
        let startOfToday = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: day, to: startOfToday).day ?? 0
        if days <= 0 {
            self = .today
        } else if days == 1 {
            self = .yesterday
        } else if days < 7 {
            self = .thisWeek
        } else if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            self = .month(calendar.component(.month, from: date))
        } else {
            self = .year(calendar.component(.year, from: date))
        }
    }

    /// Newest first.
    private var rank: (Int, Int) {
        switch self {
        case .today: (0, 0)
        case .yesterday: (1, 0)
        case .thisWeek: (2, 0)
        case .month(let month): (3, -month)
        case .year(let year): (4, -year)
        }
    }

    public static func < (lhs: RecencyGroup, rhs: RecencyGroup) -> Bool { lhs.rank < rhs.rank }

    /// Items grouped under their headings, in the items' own order within a group, newest group first.
    public static func grouped<Item>(
        _ items: [Item], by date: (Item) -> Date, now: Date = .now, calendar: Calendar = .current
    ) -> [(group: RecencyGroup, items: [Item])] {
        var groups: [RecencyGroup: [Item]] = [:]
        for item in items { groups[RecencyGroup(date(item), now: now, calendar: calendar), default: []].append(item) }
        return groups.keys.sorted().map { ($0, groups[$0] ?? []) }
    }
}
