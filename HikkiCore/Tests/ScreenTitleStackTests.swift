import Foundation
import Testing

@testable import HikkiCore

struct ScreenTitleStackTests {
    @Test func theDeepestScreenShownLastIsInFront() {
        var stack = ScreenTitleStack()
        let page = UUID()
        let sheet = UUID()
        stack.show(page, depth: 1, title: "Trip")
        #expect(stack.front == "Trip")
        stack.show(sheet, depth: 2, title: "Ask AI · Trip")
        #expect(stack.front == "Ask AI · Trip")
        // The page renamed underneath: the sheet stays in front.
        stack.show(page, depth: 1, title: "Kyoto")
        #expect(stack.front == "Ask AI · Trip")
        stack.hide(sheet)
        #expect(stack.front == "Kyoto")
        stack.hide(page)
        #expect(stack.front == nil)
    }

    @Test func atOneDepthTheLaterScreenWins() {
        var stack = ScreenTitleStack()
        let home = UUID()
        let page = UUID()
        stack.show(home, depth: 1, title: "Home")
        stack.show(page, depth: 1, title: "Trip")
        #expect(stack.front == "Trip")
        stack.hide(page)
        #expect(stack.front == "Home")
    }
}
