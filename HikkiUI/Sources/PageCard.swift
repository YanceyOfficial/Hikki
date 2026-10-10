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
        VStack(alignment: .leading, spacing: 0) {
            Theme.hover.frame(height: 36)
            VStack(alignment: .leading, spacing: 6) {
                PageIcon(icon, size: 24)
                    .offset(y: -18)
                    .padding(.bottom, -18)
                Text(title.isEmpty ? String(localized: "Untitled") : title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2, reservesSpace: true)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.mutedText)
            }
            .padding(12)
        }
        .frame(width: 148, alignment: .leading)
        .background(Theme.elevated, in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
        .clipShape(.rect(cornerRadius: 12))
        .contentShape(.rect(cornerRadius: 12))
    }
}

#Preview {
    HStack {
        PageCard(title: "Welcome to Hikki", icon: "👋", subtitle: "2h ago")
        PageCard(title: "", icon: nil, subtitle: "Yesterday")
    }
    .padding()
}
