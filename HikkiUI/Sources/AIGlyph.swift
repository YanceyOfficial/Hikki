import SwiftUI

/// The AI mark: a chat bubble with a plus, painted in a warm-to-cool sweep of the ink palette (orange, pink, purple,
/// blue) so it reads apart from the monochrome toolbar glyphs. Tinted plain (`tinted`) where colour would shout —
/// a selected, filled control.
public struct AIGlyph: View {
    private let size: CGFloat
    private let tinted: Bool

    public init(size: CGFloat = TextSize.base.rawValue, tinted: Bool = false) {
        self.size = size
        self.tinted = tinted
    }

    public var body: some View {
        if tinted {
            IconView(.chatCircleDots, size: size)
        } else {
            IconView(.chatCircleDots, size: size)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.inkOrange, Theme.inkPink, Theme.inkPurple, Theme.inkBlue],
                        startPoint: .bottomLeading, endPoint: .topTrailing))
        }
    }
}

#Preview {
    HStack(spacing: Spacing.s4) {
        AIGlyph()
        AIGlyph(size: 24)
        AIGlyph(tinted: true).foregroundStyle(Theme.subtleForeground)
    }
    .padding()
}
