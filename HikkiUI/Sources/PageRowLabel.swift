import SwiftUI

/// A page as a row on a touch screen — the iPhone's Home lists and its drawer's tree: the page's icon in a column of
/// its own, its title (muted below the top level) and room to the end, a row tall enough to touch
/// (`Size.touchRow`). The label of the button that opens the page; the caller draws the chevron and the indent.
public struct PageRowLabel: View {
    private let icon: String?
    private let title: String
    private let nested: Bool

    /// `nested`: below the top level of a tree (a quieter title).
    public init(icon: String?, title: String, nested: Bool = false) {
        self.icon = icon
        self.title = title
        self.nested = nested
    }

    public var body: some View {
        HStack(spacing: Spacing.s2_5) {
            PageIcon(icon, size: TextSize.lg.rawValue)
                .frame(width: Size.iconButton)
            Text(verbatim: PageTitle.display(title))
                .font(.hk(.base))
                .foregroundStyle(nested ? Theme.subtleForeground : Theme.foreground)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(height: Size.touchRow)
        .contentShape(.rect)
    }
}

#Preview {
    VStack(spacing: Spacing.s0) {
        PageRowLabel(icon: "🗺️", title: "Trip to Kyoto")
        PageRowLabel(icon: nil, title: "")
        PageRowLabel(icon: "📚", title: "Reading notes", nested: true)
    }
    .padding(.horizontal, Spacing.s4)
}
