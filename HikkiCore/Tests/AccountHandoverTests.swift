import Testing

@testable import HikkiCore

struct AccountHandoverTests {
    /// The answers to a run of statuses (`#expect` can't call a mutating method itself).
    private func asks(_ statuses: [Bool]) -> [Bool] {
        var offer = AccountHandoverOffer()
        return statuses.map { offer.shouldAsk(accountChanged: $0) }
    }

    @Test func asksOnceWhenSyncPausesForAnotherAccount() {
        // Still paused: the status is repeated, the user isn't asked again.
        #expect(asks([false, true, true, true]) == [false, true, false, false])
    }

    @Test func asksAgainAfterSyncLeftThatStateAndEnteredItAgain() {
        // Signed back in as the owner (syncing again), then as someone else once more.
        #expect(asks([true, false, true]) == [true, false, true])
    }

    @Test func aRunThatStartsPausedAsksAtOnce() {
        #expect(asks([true]) == [true])
    }
}
