import SwiftUI

extension EnvironmentValues {
    /// The accent the app is painted in (Settings → Appearance → Color tone). Set once at the root of each window;
    /// components read `fill` / `ink` / `onFill` from it instead of a fixed primary colour.
    @Entry public var colorTone: ColorTone = .standard
}

/// A swatch: the tone's fill as a dot (Settings' colour-tone list).
public struct ColorToneSwatch: View {
    private let tone: ColorTone
    private let size: CGFloat

    public init(_ tone: ColorTone, size: CGFloat = TextSize.lg.rawValue) {
        self.tone = tone
        self.size = size
    }

    public var body: some View {
        Circle()
            .fill(tone.fill)
            .overlay(Circle().strokeBorder(Theme.border))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

#Preview {
    HStack {
        ForEach(ColorTone.allCases) { ColorToneSwatch($0) }
    }
    .padding()
}
