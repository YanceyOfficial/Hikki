import Foundation

/// What the app lets the user do: everything for `trialDays` after the first download, and for good once the unlock is
/// bought (one in-app purchase for iPhone, iPad and Mac); after the trial without it, read only — pages open, search,
/// copy and export, nothing is written, so the notes stay theirs either way.
public enum Access: Equatable, Sendable {
    case trial(daysLeft: Int)
    case unlocked
    case expired

    public static let trialDays = 14

    /// The state on `now` for an app first downloaded on `downloaded` (the App Store's original purchase date) with the
    /// unlock bought or not. The last day of the trial counts as one day left, never zero.
    public static func on(_ now: Date, downloaded: Date, unlocked: Bool, calendar: Calendar = .current) -> Access {
        if unlocked { return .unlocked }
        guard let end = calendar.date(byAdding: .day, value: trialDays, to: downloaded), now < end else { return .expired }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: end)).day ?? 0
        return .trial(daysLeft: min(trialDays, max(1, days)))
    }

    /// Pages may be written, made and imported, and AI asked.
    public var canWrite: Bool { self != .expired }
}
