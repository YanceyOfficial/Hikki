import CoreGraphics

/// Split view's arithmetic (Hikki/Sources/SplitView.swift): the divider takes `grip` of the width, the two sides share
/// the rest by `fraction`, and neither gets less than `minimum` (less than half the room, when the window is narrow).
public enum SplitGeometry {
    /// The left side's width.
    public static func leftWidth(total: CGFloat, fraction: Double, grip: CGFloat, minimum: CGFloat) -> CGFloat {
        let room = max(total - grip, 0)
        let floor = min(minimum, room / 2)
        return min(max(room * CGFloat(fraction), floor), room - floor)
    }

    /// The fraction after dragging the divider by `translation` from `start`, kept between 0.2 and 0.8.
    public static func dragged(from start: Double, by translation: CGFloat, total: CGFloat, grip: CGFloat) -> Double {
        let room = max(total - grip, 1)
        return min(max(start + Double(translation / room), 0.2), 0.8)
    }
}
