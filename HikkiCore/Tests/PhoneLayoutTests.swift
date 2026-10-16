import CoreGraphics
import Testing

@testable import HikkiCore

struct PhoneLayoutTests {
    @Test func aPhoneKeepsItsOwnLayoutUnlessUnfoldedOnItsSide() {
        // An unfolded iPhone Duo held upright: regular both ways, taller than wide.
        #expect(
            PhoneLayout.forcesCompact(isPhone: true, horizontalRegular: true, verticalRegular: true, size: CGSize(width: 680, height: 860)))
        // A large iPhone on its side: regular width, compact height.
        #expect(
            PhoneLayout.forcesCompact(isPhone: true, horizontalRegular: true, verticalRegular: false, size: CGSize(width: 956, height: 440))
        )
        // Unfolded on its side: an iPad mini's shape keeps the sidebar and tabs.
        #expect(
            !PhoneLayout.forcesCompact(isPhone: true, horizontalRegular: true, verticalRegular: true, size: CGSize(width: 860, height: 680))
        )
    }

    @Test func compactWindowsAndIPadsAreLeftAlone() {
        // Already compact (any phone upright, folded): nothing to force.
        #expect(
            !PhoneLayout.forcesCompact(
                isPhone: true, horizontalRegular: false, verticalRegular: true, size: CGSize(width: 402, height: 874)))
        // An iPad, even upright, keeps the regular layout.
        #expect(
            !PhoneLayout.forcesCompact(
                isPhone: false, horizontalRegular: true, verticalRegular: true, size: CGSize(width: 834, height: 1194)))
    }

    @Test func splitViewIsForTheLargerIPadsOnly() {
        #expect(SplitPolicy.allowed(isPad: true, screenShortSide: 820))  // iPad Air / iPad 11-inch
        #expect(SplitPolicy.allowed(isPad: true, screenShortSide: 1032))  // iPad Pro 13-inch
        #expect(!SplitPolicy.allowed(isPad: true, screenShortSide: 744))  // iPad mini
        #expect(!SplitPolicy.allowed(isPad: false, screenShortSide: 860))  // an unfolded iPhone Duo
    }
}
