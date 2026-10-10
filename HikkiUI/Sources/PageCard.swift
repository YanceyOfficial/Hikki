import SwiftUI

/// Card for a page in grids (Home → recently edited).
public struct PageCard: View {
    private let title: String
    private let icon: String?
    private let subtitle: String

    public init(title: String, icon: String?, subtitle: String) {
        self.title = title
        self.icon = icon
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s0) {
            Theme.accent.frame(height: 36)
            VStack(alignment: .leading, spacing: Spacing.s1_5) {
                PageIcon(icon, size: 20)
                    .offset(y: -Spacing.s4)
                    .padding(.bottom, -Spacing.s4)
                Text(title.isEmpty ? String(localized: "app:page.untitled") : title)
                    .font(.hk(.sm, .semibold))
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(2, reservesSpace: true)
                Text(subtitle)
                    .font(.hk(.xs))
                    .foregroundStyle(Theme.mutedForeground)
            }
            .padding(Spacing.s3)
        }
        .frame(width: 148, alignment: .leading)
        .background(Theme.popover, in: .rect(cornerRadius: Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(Theme.border))
        .clipShape(.rect(cornerRadius: Radius.xl))
        .contentShape(.rect(cornerRadius: Radius.xl))
    }
}

#Preview {
    HStack {
        PageCard(title: "Welcome to Hikki", icon: "👋", subtitle: "2h ago")
        PageCard(title: "", icon: nil, subtitle: "Yesterday")
    }
    .padding()
}
