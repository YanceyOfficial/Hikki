import CoreGraphics
import Testing

@testable import HikkiUI

/// The reviewed cards are one pile whether collapsed or spread (ISSUE-257: switching containers jittered).
struct ReviewStackLayoutTests {
    @Test func spreadIsAListNewestFirst() {
        let placed = ReviewStackLayout.place(heights: [100, 50, 80], spread: true, spacing: 8, peek: 10, peeking: 3)
        #expect(placed.offsets == [0, 108, 166])
        #expect(placed.height == 246)
        #expect(placed.scales == [1, 1, 1])
        #expect(placed.opacities == [1, 1, 1])
    }

    @Test func collapsedIsAPileWithBottomsAlignedAndTheOlderCardsBehind() {
        let placed = ReviewStackLayout.place(heights: [100, 50, 80, 90, 70], spread: false, spacing: 8, peek: 10, peeking: 3)
        // The top card is the pile; each older card ends a step higher, shorter ones hidden behind the top one.
        #expect(placed.height == 100)
        #expect(placed.offsets == [0, 40, 0, -20, -10])
        #expect(placed.scales.map { ($0 * 100).rounded() } == [100, 94, 88, 82, 76])
        #expect(placed.opacities == [1, 1, 1, 0, 0])
    }

    @Test func aTallerCardBehindRaisesThePile() {
        let placed = ReviewStackLayout.place(heights: [60, 100], spread: false, spacing: 8, peek: 10, peeking: 3)
        #expect(placed.height == 110)
        #expect(placed.offsets == [50, 0])
    }

    @Test func nothingReviewedIsNoPile() {
        let placed = ReviewStackLayout.place(heights: [], spread: false, spacing: 8, peek: 10, peeking: 3)
        #expect(placed.height == 0)
        #expect(placed.offsets.isEmpty)
    }
}
