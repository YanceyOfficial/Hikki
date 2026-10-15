import Foundation
import Testing

@testable import HikkiCore

struct HomeDigestTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func page(_ id: String, daysAgo: Double) -> PageSummary {
        PageSummary(
            id: id, parentId: nil, title: id, icon: nil, updatedAt: now.addingTimeInterval(-daysAgo * 86_400), favoritedAt: nil,
            deletedAt: nil, sortKey: 0)
    }

    @Test func recentsAreTheNewestEightAndTheWeekStopsAtSevenDays() {
        // 12 pages, one a day: p0 today … p11 eleven days ago, given out of order.
        let pages = (0..<12).reversed().map { page("p\($0)", daysAgo: Double($0)) }
        let digest = HomeDigest(pages: pages, now: now, calendar: Calendar(identifier: .gregorian))
        #expect(digest.recents.map(\.id) == (0..<8).map { "p\($0)" })
        #expect(digest.weekPages.map(\.id) == (0...7).map { "p\($0)" })  // 7 days back, inclusive
        // Beyond the cards: this week's edits that aren't already one.
        #expect(digest.recentlyEdited.isEmpty)
    }

    @Test func recentlyEditedListsTheWeeksPagesPastTheCards() {
        let pages = (0..<15).map { page("p\($0)", daysAgo: Double($0) * 0.1) }
        let digest = HomeDigest(pages: pages, now: now)
        #expect(digest.weekPages.count == HomeDigest.weekLimit)
        #expect(digest.recentlyEdited.map(\.id) == ["p8", "p9"])
    }

    @Test func anEmptyWorkspaceHasNothing() {
        let digest = HomeDigest(pages: [], now: now)
        #expect(digest.recents.isEmpty && digest.weekPages.isEmpty && digest.recentlyEdited.isEmpty)
    }
}
