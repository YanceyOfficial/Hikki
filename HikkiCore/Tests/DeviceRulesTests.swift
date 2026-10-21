import CoreGraphics
import Testing

@testable import HikkiCore

struct DeviceRulesTests {
    @Test func phoneSizedScreensStayUprightTabletSizedOnTheirSide() {
        #expect(DeviceRules.orientation(screen: CGSize(width: 402, height: 874)) == .portrait)  // iPhone
        #expect(DeviceRules.orientation(screen: CGSize(width: 440, height: 956)) == .portrait)  // a Pro Max
        #expect(DeviceRules.orientation(screen: CGSize(width: 466, height: 678)) == .portrait)  // Duo, folded
        #expect(DeviceRules.orientation(screen: CGSize(width: 956, height: 440)) == .portrait)  // already turned
        #expect(DeviceRules.orientation(screen: CGSize(width: 669, height: 951)) == .landscape)  // Duo, unfolded
        #expect(DeviceRules.orientation(screen: CGSize(width: 744, height: 1133)) == .landscape)  // iPad mini
        #expect(DeviceRules.orientation(screen: CGSize(width: 1032, height: 1376)) == .landscape)  // iPad Pro 13"
    }

    @Test func drawingsAreOnlyLookedAtOnPhoneSizedScreens() {
        #expect(DeviceRules.drawingsReadOnly(screen: CGSize(width: 402, height: 874)))  // iPhone
        #expect(DeviceRules.drawingsReadOnly(screen: CGSize(width: 956, height: 440)))  // a Pro Max on its side
        #expect(DeviceRules.drawingsReadOnly(screen: CGSize(width: 466, height: 678)))  // Duo, folded
        #expect(!DeviceRules.drawingsReadOnly(screen: CGSize(width: 669, height: 951)))  // Duo, unfolded
        #expect(!DeviceRules.drawingsReadOnly(screen: CGSize(width: 744, height: 1133)))  // iPad mini
    }

    @Test func aWindowSplitsWhenItIsWideEnoughForTwoPages() {
        #expect(DeviceRules.allowsSplit(windowWidth: 820))
        #expect(DeviceRules.allowsSplit(windowWidth: 1133))  // iPad mini on its side
        #expect(DeviceRules.allowsSplit(windowWidth: 951))  // an unfolded Duo on its side
        #expect(!DeviceRules.allowsSplit(windowWidth: 744))
        #expect(!DeviceRules.allowsSplit(windowWidth: 402))
    }

    @Test func sheetsHideTheBarsOnlyBesideAVerticalBar() {
        #expect(DeviceRules.sheetHidesBars(hasVerticalBar: true))
        #expect(!DeviceRules.sheetHidesBars(hasVerticalBar: false))
    }
}
