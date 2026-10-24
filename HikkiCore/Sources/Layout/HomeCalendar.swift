import Foundation

/// A month of a calendar, by its year and number (1–12): what Home's Calendar view shows.
public struct CalendarMonth: Hashable, Sendable {
    public let year: Int
    public let month: Int

    public init(year: Int, month: Int) {
        // Normalised, so stepping past December or January lands in the next / previous year.
        let index = year * 12 + (month - 1)
        self.year = Int((Double(index) / 12).rounded(.down))
        self.month = index - self.year * 12 + 1
    }

    /// The month `date` falls in on `calendar`.
    public init(containing date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1)
    }

    /// The month `count` months later (earlier when negative).
    public func adding(_ count: Int) -> CalendarMonth {
        CalendarMonth(year: year, month: month + count)
    }

    /// Its first day, at the start of the day.
    public func firstDay(in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: 1)).map { calendar.startOfDay(for: $0) }
            ?? Date(timeIntervalSince1970: 0)
    }

    public func contains(_ date: Date, in calendar: Calendar) -> Bool {
        CalendarMonth(containing: date, calendar: calendar) == self
    }
}

/// Home's Calendar view (Mac and iPad): the month as whole weeks, the pages edited on each day (a page's edited date,
/// `updatedAt`, on the local calendar), how many were edited in the month and which day to show first.
public enum HomeCalendar {
    /// The calendar the view counts days on: the user's, with weeks starting on Monday (as the editor's dates do).
    public static func calendar(_ base: Calendar = .current) -> Calendar {
        var calendar = base
        calendar.firstWeekday = 2
        return calendar
    }

    /// The month's weeks, each 7 days starting on the calendar's first weekday: from the week holding its 1st to the
    /// week holding its last day, so the days before and after it fill out the first and last rows.
    public static func weeks(of month: CalendarMonth, calendar: Calendar) -> [[Date]] {
        let first = month.firstDay(in: calendar)
        let lead = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let length = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        let rows = (lead + length + 6) / 7
        guard let start = calendar.date(byAdding: .day, value: -lead, to: first) else { return [] }
        return (0..<rows).map { week in
            (0..<7).compactMap { day in
                calendar.date(byAdding: .day, value: week * 7 + day, to: start).map { calendar.startOfDay(for: $0) }
            }
        }
    }

    /// The weekday names in the order the weeks run (`symbols` as `Calendar` gives them, Sunday first).
    public static func weekdaySymbols(_ symbols: [String], firstWeekday: Int) -> [String] {
        guard symbols.count == 7, (1...7).contains(firstWeekday) else { return symbols }
        return Array(symbols[(firstWeekday - 1)...] + symbols[..<(firstWeekday - 1)])
    }

    /// Items under the start of the day they fall on, each day's newest first.
    public static func byDay<Item>(_ items: [Item], date: (Item) -> Date, calendar: Calendar) -> [Date: [Item]] {
        var days: [Date: [(date: Date, item: Item)]] = [:]
        for item in items {
            let when = date(item)
            days[calendar.startOfDay(for: when), default: []].append((when, item))
        }
        return days.mapValues { entries in entries.sorted { $0.date > $1.date }.map(\.item) }
    }

    /// How many items fall in the month.
    public static func count<Item>(in month: CalendarMonth, of days: [Date: [Item]], calendar: Calendar) -> Int {
        days.reduce(0) { sum, entry in month.contains(entry.key, in: calendar) ? sum + entry.value.count : sum }
    }

    /// The day to show first in `month`: today when it is in the month and has items; else the month's last day with
    /// items (not after today); else today when it is in the month, or the month's first day.
    public static func defaultDay<Item>(in month: CalendarMonth, days: [Date: [Item]], today: Date, calendar: Calendar)
        -> Date
    {
        let today = calendar.startOfDay(for: today)
        let inMonth = month.contains(today, in: calendar)
        if inMonth, days[today]?.isEmpty == false { return today }
        let busy = days.compactMap { day, items in
            !items.isEmpty && day <= today && month.contains(day, in: calendar) ? day : nil
        }
        if let last = busy.max() { return last }
        return inMonth ? today : month.firstDay(in: calendar)
    }
}
