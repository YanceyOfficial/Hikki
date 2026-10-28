import Foundation

/// When to offer the account in use for a workspace that synced with another iCloud account
/// (`CloudSync.Status.accountChanged`): once each time sync enters that state — a run that starts paused asks once,
/// a device signed back in and out again is asked again — never while it stays there.
public struct AccountHandoverOffer: Sendable, Equatable {
    private var wasPaused = false

    public init() {}

    /// Called with every status; true when the user should be asked now.
    public mutating func shouldAsk(accountChanged: Bool) -> Bool {
        defer { wasPaused = accountChanged }
        return accountChanged && !wasPaused
    }
}
