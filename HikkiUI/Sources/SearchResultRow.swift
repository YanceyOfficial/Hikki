import SwiftUI

/// One result in the search palette (Notion's rows): icon, title with the terms emphasized and the edited time at
/// the end of the line, the parent path under it, then an excerpt with the terms emphasized — of the page text, or
/// of an attached file, named before it (`attachment`).
public struct SearchResultRow: View {
    private let title: String
    private let icon: String?
    private let snippet: String
    private let path: String
    private let terms: [String]
    private let attachment: String?
    private let updatedAt: Date?
    private let isSelected: Bool

    public init(
        title: String, icon: String?, snippet: String = "", path: String = "", terms: [String] = [],
        attachment: String? = nil, updatedAt: Date? = nil, isSelected: Bool = false
    ) {
        self.title = title
        self.icon = icon
        self.snippet = snippet
        self.path = path
        self.terms = terms
        self.attachment = attachment
        self.updatedAt = updatedAt
        self.isSelected = isSelected
    }

    public var body: some View {
        HStack(alignment: .top, spacing: Spacing.s2_5) {
            PageIcon(icon, size: Size.pageIcon)
                .padding(.top, Spacing.px)
            VStack(alignment: .leading, spacing: Spacing.s0_5) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s2) {
                    HighlightedText(PageTitle.display(title), terms: terms)
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
                if let attachment {
                    HStack(spacing: Spacing.s1) {
                        IconView(.paperclip, size: TextSize.xs.rawValue)
                        Text(attachment).lineLimit(1)
                    }
                    .font(.hk(.xs))
                    .foregroundStyle(Theme.mutedForeground)
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

/// Another place a search result's page matches, under its row (VS Code's / Obsidian's): the excerpt alone, in line
/// with the title above, with the terms emphasized.
public struct SearchMatchRow: View {
    private let snippet: String
    private let terms: [String]
    private let isSelected: Bool

    public init(snippet: String, terms: [String] = [], isSelected: Bool = false) {
        self.snippet = snippet
        self.terms = terms
        self.isSelected = isSelected
    }

    public var body: some View {
        HStack(spacing: Spacing.s2) {
            Theme.border.frame(width: Spacing.px)
            HighlightedText(snippet, terms: terms)
                .font(.hk(.xs))
                .foregroundStyle(Theme.subtleForeground)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, Spacing.s1_5)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.leading, Self.indent)
        .padding(.trailing, Spacing.s2_5)
        .background(isSelected ? Theme.accentStrong : .clear, in: .rect(cornerRadius: Radius.md))
        .contentShape(.rect)
    }

    /// In line with the title of the row above (its padding, the 16 pt icon, the gap after it).
    static let indent = Spacing.s2_5 + Spacing.s4 + Spacing.s2_5
}

/// Under a search result: how many more places its page matches, a caret that opens them ("12 more matches") —
/// or shows the rest, or folds them away again.
public struct SearchMatchesToggleRow: View {
    private let title: String
    private let isExpanded: Bool
    private let isSelected: Bool

    public init(_ title: String, isExpanded: Bool = false, isSelected: Bool = false) {
        self.title = title
        self.isExpanded = isExpanded
        self.isSelected = isSelected
    }

    public var body: some View {
        HStack(spacing: Spacing.s1) {
            IconView(isExpanded ? .caretDown : .caretRight, size: TextSize.x2s.rawValue)
            Text(title).font(.hk(.xs, .medium)).lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.mutedForeground)
        .padding(.leading, SearchMatchRow.indent)
        .padding(.trailing, Spacing.s2_5)
        .padding(.vertical, Spacing.s1)
        .background(isSelected ? Theme.accentStrong : .clear, in: .rect(cornerRadius: Radius.md))
        .contentShape(.rect)
    }
}

#Preview("Matches") {
    VStack(spacing: Spacing.px) {
        SearchResultRow(
            title: "N4 文法", icon: "🍀", snippet: "ので表示理由 动词辞书形 + ので、〜", path: "日本語を勉強する",
            terms: ["ので"], updatedAt: .now)
        SearchMatchRow(snippet: "日本語がわからないので、英語で話していただけませんか。", terms: ["ので"], isSelected: true)
        SearchMatchRow(snippet: "雨が降っているので家にいます。", terms: ["ので"])
        SearchMatchesToggleRow("Show 8 more", isExpanded: false)
        SearchMatchesToggleRow("12 more matches", isExpanded: false, isSelected: true)
    }
    .padding(Spacing.s1_5)
    .frame(width: 520)
    .background(Theme.popover)
}

#Preview {
    VStack(spacing: Spacing.s0_5) {
        SearchResultRow(
            title: "Weekly sync", icon: "🗓️", path: "Work / Meetings", terms: ["week"], updatedAt: .now, isSelected: true)
        SearchResultRow(
            title: "Roadmap", icon: nil, snippet: "…the roadmap is due Friday, after the review with the team…",
            path: "Projects", terms: ["roadmap", "friday"], updatedAt: .now.addingTimeInterval(-3 * 86_400))
        SearchResultRow(
            title: "Trip", icon: "🧭", snippet: "…BOARDING PASS · gate B12 · seat 14A…", terms: ["gate"],
            attachment: "boarding-pass.pdf", updatedAt: .now.addingTimeInterval(-86_400))
        SearchResultRow(title: "", icon: "📝", updatedAt: .now.addingTimeInterval(-40 * 86_400))
    }
    .padding(Spacing.s1_5)
    .frame(width: 520)
    .background(Theme.popover)
}
