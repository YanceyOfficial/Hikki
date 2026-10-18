import SwiftUI

/// Text that shimmers while something works ("Thinking…", "Searching the web…"): muted text with a band of the full
/// foreground colour sweeping across it from the leading edge, once per `Motion.loop` — the native counterpart of the
/// editor's `hk-ai-sweep` and exodus's `ShimmeringText`. SwiftUI has no such effect of its own (the macOS / iOS 27 SDK
/// offers none for text), so the band is a gradient fill moved by a `TimelineView`. With Reduce Motion on the text
/// stays still and muted. VoiceOver reads the text as it is.
public struct ShimmerText: View {
    private let text: Text
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    public init(_ key: LocalizedStringKey) { text = Text(key) }

    public init(verbatim: String) { text = Text(verbatim: verbatim) }

    public init(_ text: Text) { self.text = text }

    public var body: some View {
        if reduceMotion {
            text.foregroundStyle(Theme.mutedForeground)
        } else {
            TimelineView(.animation) { context in
                text.foregroundStyle(Self.band(at: Self.phase(context.date), rightToLeft: layoutDirection == .rightToLeft))
            }
        }
    }

    /// Where in its sweep the band is at `date`: 0 just before the leading edge, 1 just past the trailing one.
    nonisolated static func phase(_ date: Date, period: TimeInterval = Motion.loop) -> Double {
        let elapsed = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
        return elapsed / period
    }

    /// Half the band's width, as a fraction of the text's width.
    private static let halfWidth = 0.3

    /// The fill for one moment: muted everywhere but around the band's centre, which travels from off the leading
    /// edge to off the trailing one (outside its stops a linear gradient keeps its end colours).
    private static func band(at phase: Double, rightToLeft: Bool) -> LinearGradient {
        let travelled = -halfWidth + (1 + 2 * halfWidth) * phase
        let centre = rightToLeft ? 1 - travelled : travelled
        return LinearGradient(
            colors: [Theme.mutedForeground, Theme.foreground, Theme.mutedForeground],
            startPoint: UnitPoint(x: centre - halfWidth, y: 0.5), endPoint: UnitPoint(x: centre + halfWidth, y: 0.5))
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Spacing.s4) {
        ShimmerText(verbatim: "Thinking…").font(.hk(.sm))
        ShimmerText(verbatim: "Searching the web for “swift-markdown tables”…").font(.hk(.sm))
        ShimmerText(verbatim: "Thinking…").font(.hk(.x2l, .semibold))
    }
    .padding(Spacing.s6)
}
