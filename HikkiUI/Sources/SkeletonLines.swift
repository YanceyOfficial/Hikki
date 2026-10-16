import SwiftUI

/// Grey bars standing in for text that is still loading (a list row, a page preview): one bar per line, each a
/// fraction of the available width, pulsing once per `Motion.loop` (still when Reduce Motion is on). Hidden from
/// VoiceOver, which reads the `label` instead.
public struct SkeletonLines: View {
    private let widths: [CGFloat]
    private let height: CGFloat
    private let spacing: CGFloat
    private let label: LocalizedStringKey
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    /// `widths` are fractions of the width (0…1), one per line; `height` is a line's bar.
    public init(
        _ widths: [CGFloat], height: CGFloat = Spacing.s3, spacing: CGFloat = Spacing.s2, label: LocalizedStringKey
    ) {
        self.widths = widths
        self.height = height
        self.spacing = spacing
        self.label = label
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(widths.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(Theme.muted)
                    .frame(height: height)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .scaleEffect(x: min(max(widths[index], 0), 1), y: 1, anchor: .leading)
            }
        }
        .opacity(dimmed ? 0.45 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(Motion.easeInOut(Motion.loop / 2).repeatForever(autoreverses: true)) { dimmed = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Spacing.s6) {
        SkeletonLines([0.5], height: Spacing.s6, label: "Loading")
        SkeletonLines([1, 0.92, 0.6], label: "Loading")
        SkeletonLines([0.7, 0.4, 0.55], height: Spacing.s2_5, label: "Loading")
    }
    .padding(Spacing.s6)
    .frame(width: 360)
}
