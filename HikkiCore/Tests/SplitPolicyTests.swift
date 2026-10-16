import CoreGraphics
import Testing

@testable import HikkiCore

struct SplitPolicyTests {
    @Test func aWindowSplitsWhenItIsWideEnoughForTwoPagesOnAnyDevice() {
        #expect(SplitPolicy.allowed(windowWidth: 820))  // an 11-inch iPad upright
        #expect(SplitPolicy.allowed(windowWidth: 1133))  // iPad mini on its side
        #expect(SplitPolicy.allowed(windowWidth: 860))  // an unfolded iPhone Duo on its side
        #expect(!SplitPolicy.allowed(windowWidth: 744))  // iPad mini upright
        #expect(!SplitPolicy.allowed(windowWidth: 507))  // a narrow Stage Manager window
        #expect(!SplitPolicy.allowed(windowWidth: 402))  // a phone
    }
}
