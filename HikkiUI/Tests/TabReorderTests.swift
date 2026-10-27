import Testing

@testable import HikkiUI

struct TabReorderTests {
    /// Four tabs of 100 points, side by side.
    let tabs: [ClosedRange<Double>] = [0...100, 100...200, 200...300, 300...400]
    let single = [false, false, false, false]

    @Test func aTabSwapsOnceMoreThanHalfOfItLiesOverTheNeighbour() {
        // Carried 45 points right: under half of the next tab — stays.
        #expect(TabReorder.gap(tabs: tabs, joined: single, moving: 0, box: 45...145) == nil)
        // Past the next tab's middle: after it.
        #expect(TabReorder.gap(tabs: tabs, joined: single, moving: 0, box: 55...155) == 2)
        // On past the one after: after that one too.
        #expect(TabReorder.gap(tabs: tabs, joined: single, moving: 0, box: 160...260) == 3)
        #expect(TabReorder.gap(tabs: tabs, joined: single, moving: 0, box: 320...420) == 4)
        // Leftward: the box's left edge against the middles.
        #expect(TabReorder.gap(tabs: tabs, joined: single, moving: 3, box: 260...360) == nil)
        #expect(TabReorder.gap(tabs: tabs, joined: single, moving: 3, box: 240...340) == 2)
        #expect(TabReorder.gap(tabs: tabs, joined: single, moving: 3, box: 40...140) == 0)
        // Where it already is.
        #expect(TabReorder.gap(tabs: tabs, joined: single, moving: 1, box: 100...200) == nil)
    }

    @Test func aSplitIsOneTabToPassAndToMove() {
        // Tabs 1 and 2 are a split: passed by their joint middle (200), never split apart.
        let joined = [false, true, false, false]
        #expect(TabReorder.gap(tabs: tabs, joined: joined, moving: 0, box: 60...160) == nil)
        #expect(TabReorder.gap(tabs: tabs, joined: joined, moving: 0, box: 110...210) == 3)
        #expect(TabReorder.gap(tabs: tabs, joined: joined, moving: 3, box: 210...310) == nil)
        #expect(TabReorder.gap(tabs: tabs, joined: joined, moving: 3, box: 190...290) == 1)
        // The pair itself dragged (either half): its joint box, 200 wide.
        #expect(TabReorder.gap(tabs: tabs, joined: joined, moving: 2, box: 150...350) == nil)
        #expect(TabReorder.gap(tabs: tabs, joined: joined, moving: 1, box: 160...360) == 4)
        #expect(TabReorder.gap(tabs: tabs, joined: joined, moving: 2, box: 40...240) == 0)
    }

    @Test func nothingWithoutAMatchingStrip() {
        #expect(TabReorder.gap(tabs: tabs, joined: [false], moving: 0, box: 0...100) == nil)
        #expect(TabReorder.gap(tabs: tabs, joined: single, moving: 9, box: 0...100) == nil)
    }
}
