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

/// The app icon's sparkle: a large four-point star with a small one below its right, their sides curved inwards.
/// Coordinates are the icon's (a 1024 grid), fitted into the rect.
nonisolated public struct HikkiSparkle: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        // The pair spans x 648…910 (262) and y 184…476 (292) on the icon's grid: scaled to fit, centred.
        let scale = min(rect.width / 262, rect.height / 292)
        let left = rect.midX - 262 * scale / 2
        let top = rect.midY - 292 * scale / 2
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: left + (x - 648) * scale, y: top + (y - 184) * scale)
        }
        var path = Path()
        func star(cx: CGFloat, cy: CGFloat, r: CGFloat) {
            let k = r * 0.24  // the control point's pull towards the centre (the icon's 27.84 of 116)
            path.move(to: point(cx, cy - r))
            path.addQuadCurve(to: point(cx + r, cy), control: point(cx + k, cy - k))
            path.addQuadCurve(to: point(cx, cy + r), control: point(cx + k, cy + k))
            path.addQuadCurve(to: point(cx - r, cy), control: point(cx - k, cy + k))
            path.addQuadCurve(to: point(cx, cy - r), control: point(cx - k, cy - k))
            path.closeSubpath()
        }
        star(cx: 764, cy: 300, r: 116)
        star(cx: 866, cy: 432, r: 44)
        return path
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
