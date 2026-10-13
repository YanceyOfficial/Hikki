import SwiftUI

/// One result in the search palette (Notion's rows): icon, title with the terms emphasized and the edited time at
/// the end of the line, the parent path under it, then an excerpt of the page text with the terms emphasized.
public struct SearchResultRow: View {
    private let title: String
    private let icon: String?
    private let snippet: String
    private let path: String
    private let terms: [String]
    private let updatedAt: Date?
    private let isSelected: Bool

    public init(
        title: String, icon: String?, snippet: String = "", path: String = "", terms: [String] = [],
        updatedAt: Date? = nil, isSelected: Bool = false
    ) {
        self.title = title
        self.icon = icon
        self.snippet = snippet
        self.path = path
        self.terms = terms
        self.updatedAt = updatedAt
        self.isSelected = isSelected
    }

    public var body: some View {
        HStack(alignment: .top, spacing: Spacing.s2_5) {
            PageIcon(icon, size: 16)
                .padding(.top, Spacing.px)
            VStack(alignment: .leading, spacing: Spacing.s0_5) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s2) {
                    HighlightedText(title.isEmpty ? String(localized: "app:page.untitled") : title, terms: terms)
                        .font(.hk(.sm, .medium))
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1)
                    Spacer(minLength: Spacing.s2)
                    if let updatedAt {
                        Text(updatedAt, format: .relative(presentation: .named))
                            .font(.hk(.xs))
                            .foregroundStyle(Theme.mutedForeground)
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
                }
                if !path.isEmpty {
                    Text(path).font(.hk(.xs)).foregroundStyle(Theme.mutedForeground).lineLimit(1)
                }
                if !snippet.isEmpty {
                    HighlightedText(snippet, terms: terms)
                        .font(.hk(.xs))
                        .foregroundStyle(Theme.subtleForeground)
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, Spacing.s2_5)
        .padding(.vertical, Spacing.s2)
        .background(isSelected ? Theme.accentStrong : .clear, in: .rect(cornerRadius: Radius.md))
        .contentShape(.rect)
    }
}

#Preview {
    VStack(spacing: Spacing.s0_5) {
        SearchResultRow(
            title: "Weekly sync", icon: "🗓️", path: "Work / Meetings", terms: ["week"], updatedAt: .now, isSelected: true)
        SearchResultRow(
            title: "Roadmap", icon: nil, snippet: "…the roadmap is due Friday, after the review with the team…",
            path: "Projects", terms: ["roadmap", "friday"], updatedAt: .now.addingTimeInterval(-3 * 86_400))
        SearchResultRow(title: "", icon: "📝", updatedAt: .now.addingTimeInterval(-40 * 86_400))
    }
    .padding(Spacing.s1_5)
    .frame(width: 520)
    .background(Theme.popover)
}
