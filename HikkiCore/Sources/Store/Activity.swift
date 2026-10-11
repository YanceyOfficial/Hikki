import Foundation

/// One day of writing on this device.
public struct DailyActivity: Equatable, Sendable {
    public var day: Date
    public var edits: Int
    public var wordsAdded: Int

    public init(day: Date, edits: Int, wordsAdded: Int) {
        self.day = day
        self.edits = edits
        self.wordsAdded = wordsAdded
    }
}

public struct WorkspaceStats: Equatable, Sendable {
    public var pages: Int
    public var words: Int

    public init(pages: Int, words: Int) {
        self.pages = pages
        self.words = words
    }
}

/// Day keys (yyyy-MM-dd in the local calendar) for the activity table.
public enum ActivityDay {
    public static func key(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public static func date(_ key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

/// What Home shows, computed from daily activity.
public enum ActivitySummary {
    /// Consecutive days with edits, ending today — or yesterday, so a streak isn't lost before today's first edit.
    public static func streak(_ days: [DailyActivity], today: Date, calendar: Calendar = .current) -> Int {
        let active = Set(days.filter { $0.edits > 0 }.map { ActivityDay.key($0.day, calendar: calendar) })
        var day = calendar.startOfDay(for: today)
        if !active.contains(ActivityDay.key(day, calendar: calendar)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while active.contains(ActivityDay.key(day, calendar: calendar)) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    /// Edits in the 7 days ending today.
    public static func editsThisWeek(_ days: [DailyActivity], today: Date, calendar: Calendar = .current) -> Int {
        guard let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: today)) else { return 0 }
        return days.filter { $0.day >= start }.reduce(0) { $0 + $1.edits }
    }

    /// The heatmap's columns: `weeks` weeks ending with the week of `today`, each a column of 7 days starting
    /// on the calendar's first weekday. Days after today are nil (the current week is partial).
    public static func grid(weeks: Int, today: Date, calendar: Calendar = .current) -> [[Date?]] {
        let end = calendar.startOfDay(for: today)
        let weekday = calendar.component(.weekday, from: end)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        guard let thisWeekStart = calendar.date(byAdding: .day, value: -offset, to: end),
            let first = calendar.date(byAdding: .day, value: -7 * (weeks - 1), to: thisWeekStart)
        else { return [] }
        return (0..<weeks).map { w in
            (0..<7).map { d -> Date? in
                guard let day = calendar.date(byAdding: .day, value: w * 7 + d, to: first), day <= end else { return nil }
                return day
            }
        }
    }

    /// Intensity 0…4 for a day's edits, relative to the busiest day (GitHub-style quartiles); 0 means none.
    public static func level(_ edits: Int, max busiest: Int) -> Int {
        guard edits > 0, busiest > 0 else { return 0 }
        return min(4, Int((Double(edits) / Double(busiest) * 4).rounded(.up)))
    }
}
