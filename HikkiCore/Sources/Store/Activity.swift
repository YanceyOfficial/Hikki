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
