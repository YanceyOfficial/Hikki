import Foundation
import Testing

@testable import HikkiCore

struct RecencyGroupTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }()

    func date(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = calendar.timeZone
        return formatter.date(from: text)!
    }

    @Test func daysCountByTheCalendarNotBy24Hours() {
        let now = date("2026-10-15T00:30:00+08:00")
        #expect(RecencyGroup(date("2026-10-15T00:05:00+08:00"), now: now, calendar: calendar) == .today)
        // 40 minutes ago, but before midnight.
        #expect(RecencyGroup(date("2026-10-14T23:50:00+08:00"), now: now, calendar: calendar) == .yesterday)
        #expect(RecencyGroup(date("2026-10-09T12:00:00+08:00"), now: now, calendar: calendar) == .thisWeek)
        #expect(RecencyGroup(date("2026-10-08T12:00:00+08:00"), now: now, calendar: calendar) == .month(10))
        #expect(RecencyGroup(date("2026-03-01T12:00:00+08:00"), now: now, calendar: calendar) == .month(3))
        #expect(RecencyGroup(date("2025-12-31T12:00:00+08:00"), now: now, calendar: calendar) == .year(2025))
        // A clock that ran ahead on another device: still today.
        #expect(RecencyGroup(date("2026-10-16T09:00:00+08:00"), now: now, calendar: calendar) == .today)
    }

    @Test func groupsComeNewestFirstAndKeepTheItemsOrder() {
        let now = date("2026-10-15T12:00:00+08:00")
        let items = [
            ("a", date("2026-10-15T11:00:00+08:00")), ("b", date("2025-01-01T11:00:00+08:00")),
            ("c", date("2026-02-01T11:00:00+08:00")), ("d", date("2026-10-15T09:00:00+08:00")),
            ("e", date("2026-06-01T11:00:00+08:00")),
        ]
        let groups = RecencyGroup.grouped(items, by: \.1, now: now, calendar: calendar)
        #expect(groups.map(\.group) == [.today, .month(6), .month(2), .year(2025)])
        #expect(groups[0].items.map(\.0) == ["a", "d"])
    }
}
