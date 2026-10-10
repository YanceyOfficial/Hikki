import SwiftUI

/// Where the custom title-bar row sits, measured from the real window (traffic lights) on macOS so
/// our sidebar header and tab strip line up with them. Defaults suit iPad / no measurement.
public struct ChromeMetrics: Equatable, Sendable {
    /// Height of the title-bar row; its vertical center matches the traffic lights' center.
    public var barHeight: CGFloat
    /// Space to leave on the leading edge for the traffic lights (0 where there are none).
    public var leadingInset: CGFloat

    public init(barHeight: CGFloat = Size.tabBar, leadingInset: CGFloat = 0) {
        self.barHeight = barHeight
        self.leadingInset = leadingInset
    }
}

extension EnvironmentValues {
    @Entry public var chromeMetrics = ChromeMetrics()
}
