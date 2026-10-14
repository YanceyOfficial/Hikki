import CoreGraphics
import Testing

@testable import HikkiCore

struct SplitGeometryTests {
    @Test func halfAndHalfGivesBothSidesTheSameWidthBesideTheDivider() {
        let left = SplitGeometry.leftWidth(total: 1214, fraction: 0.5, grip: 14, minimum: 320)
        #expect(left == 600)
        #expect(1214 - 14 - left == left)
    }

    @Test func neitherSideGoesBelowTheMinimum() {
        #expect(SplitGeometry.leftWidth(total: 1014, fraction: 0.1, grip: 14, minimum: 320) == 320)
        #expect(SplitGeometry.leftWidth(total: 1014, fraction: 0.9, grip: 14, minimum: 320) == 680)
        // Too narrow for two minimums: halves.
        #expect(SplitGeometry.leftWidth(total: 514, fraction: 0.2, grip: 14, minimum: 320) == 250)
    }

    @Test func draggingMovesTheFractionByTheRoomBesideTheDivider() {
        #expect(SplitGeometry.dragged(from: 0.5, by: 100, total: 1014, grip: 14) == 0.6)
        #expect(SplitGeometry.dragged(from: 0.5, by: 900, total: 1014, grip: 14) == 0.8)
        #expect(SplitGeometry.dragged(from: 0.5, by: -900, total: 1014, grip: 14) == 0.2)
    }
}
