import Foundation

/// Where a tab dragged along the strip goes — Chrome's rule: the dragged tab's own box, carried under the pointer,
/// swaps with a neighbour once more than half of it lies over that neighbour (its leading edge past the neighbour's
/// middle), neighbour after neighbour outward from where it started. A split's two tabs count as one tab, moving and
/// passed alike. The pointer alone decided before (ISSUE-191): a tab grabbed by its edge then swapped far too early or
/// far too late.
public enum TabReorder {
    /// `tabs`: each tab's x-range in strip order; `joined`: tab i is the leading half of a split with i + 1; `moving`:
    /// the dragged tab's index; `box`: its own x-range under the pointer (the pair's, in a split). The gap to move into
    /// as `NavigationTabs.move` takes it — before the tab at that index, `tabs.count` for after the last — or nil to
    /// stay where it is.
    public static func gap(tabs: [ClosedRange<Double>], joined: [Bool], moving: Int, box: ClosedRange<Double>) -> Int? {
        guard tabs.indices.contains(moving), joined.count == tabs.count else { return nil }
        let first = moving > 0 && joined[moving - 1] ? moving - 1 : moving
        let last = joined[first] ? first + 1 : first
        // Leftward: neighbours whose middle the box's left edge went past, one after another; a pair by its own middle.
        var passedLeft = 0
        var i = first - 1
        while i >= 0 {
            let lead = i > 0 && joined[i - 1] ? i - 1 : i
            guard box.lowerBound < middle(tabs[lead].lowerBound, tabs[i].upperBound) else { break }
            passedLeft += i - lead + 1
            i = lead - 1
        }
        if passedLeft > 0 { return first - passedLeft }
        // Rightward: the same with the box's right edge.
        var passedRight = 0
        i = last + 1
        while i < tabs.count {
            let trail = joined[i] ? i + 1 : i
            guard box.upperBound > middle(tabs[i].lowerBound, tabs[trail].upperBound) else { break }
            passedRight += trail - i + 1
            i = trail + 1
        }
        return passedRight > 0 ? last + 1 + passedRight : nil
    }

    private static func middle(_ from: Double, _ to: Double) -> Double { (from + to) / 2 }
}
