import SwiftUI

/// One result in the search palette: icon, title (query emphasized), parent path and an optional excerpt.
public struct SearchResultRow: View {
    private let title: String
    private let icon: String?
    private let snippet: String
    private let path: String
    private let query: String
    private let isSelected: Bool

    public init(title: String, icon: String?, snippet: String = "", path: String = "", query: String = "", isSelected: Bool = false) {
        self.title = title
        self.icon = icon
        self.snippet = snippet
        self.path = path
        self.query = query
        self.isSelected = isSelected
    }

    public var body: some View {
        HStack(alignment: snippet.isEmpty ? .center : .top, spacing: Spacing.s2_5) {
            PageIcon(icon, size: 16)
                .padding(.top, snippet.isEmpty ? Spacing.s0 : Spacing.px)
            VStack(alignment: .leading, spacing: Spacing.s0_5) {
                HStack(spacing: Spacing.s1_5) {
                    HighlightedText(title.isEmpty ? String(localized: "Untitled") : title, query: query)
                        .font(.hk(.sm))
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1)
                    if !path.isEmpty {
                        Text("— \(path)").font(.hk(.xs)).foregroundStyle(Theme.mutedForeground).lineLimit(1)
                    }
                }
                if !snippet.isEmpty {
                    HighlightedText(snippet, query: query)
                        .font(.hk(.xs))
                        .foregroundStyle(Theme.subtleForeground)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if isSelected {
                IconView(.arrowUDownLeft, size: TextSize.x2s.rawValue).foregroundStyle(Theme.mutedForeground)
            }
        }
        .padding(.horizontal, Spacing.s2_5)
        .padding(.vertical, Spacing.s2)
        .background(isSelected ? Theme.accentStrong : .clear, in: .rect(cornerRadius: Radius.md))
        .contentShape(.rect)
    }
}
