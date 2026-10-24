import SwiftUI

/// The AI mark: Hikki's own sparkle — the two four-point stars of the app icon's ✦ (design/icon/hi-star/03-star.svg) —
/// painted in a warm-to-cool sweep of the ink palette (orange, pink, purple, blue), so it reads apart from the
/// toolbar's outline glyphs (a speech bubble here looked like the comments button). Tinted plain (`tinted`) where
/// colour would shout — a selected, filled control.
public struct AIGlyph: View {
    private let size: CGFloat
    private let tinted: Bool

    public init(size: CGFloat = TextSize.base.rawValue, tinted: Bool = false) {
        self.size = size
        self.tinted = tinted
    }

    public var body: some View {
        // An image, not the shape: toolbars draw only images and text (Marks.xcassets/AIMark, the same sparkle).
        let mark = Image("AIMark", bundle: .module).renderingMode(.template).resizable().scaledToFit().frame(width: size, height: size)
        if tinted {
            mark
        } else {
            mark.foregroundStyle(
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
        AIGlyph(size: 40)
        AIGlyph(tinted: true).foregroundStyle(Theme.subtleForeground)
    }
    .padding()
}
