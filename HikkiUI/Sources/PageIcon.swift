import SwiftUI

/// A page's emoji icon, or a neutral document glyph when it has none.
public struct PageIcon: View {
    private let emoji: String?
    private let size: CGFloat

    public init(_ emoji: String?, size: CGFloat = 14) {
        self.emoji = emoji
        self.size = size
    }

    public var body: some View {
        Group {
            if let emoji, !emoji.isEmpty {
                Text(emoji).font(.system(size: size * 0.92)) // design-lint: allow (scales with the icon size)
            } else {
                Image(systemName: "doc.text")
                    .font(.system(size: size * 0.85, weight: .regular)) // design-lint: allow
                    .foregroundStyle(Theme.mutedForeground)
            }
        }
        .frame(width: size + 4, height: size + 4)
        .accessibilityHidden(true)
    }
}

#Preview {
    HStack { PageIcon("👋"); PageIcon(nil); PageIcon("🌊", size: 40) }.padding()
}
