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
        HStack(alignment: snippet.isEmpty ? .center : .top, spacing: 10) {
            PageIcon(icon, size: 16)
                .padding(.top, snippet.isEmpty ? 0 : 1)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    HighlightedText(title.isEmpty ? String(localized: "Untitled") : title, query: query)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    if !path.isEmpty {
                        Text("— \(path)").font(.system(size: 12)).foregroundStyle(Theme.mutedText).lineLimit(1)
                    }
                }
                if !snippet.isEmpty {
                    HighlightedText(snippet, query: query)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if isSelected {
                Image(systemName: "return").font(.system(size: 11)).foregroundStyle(Theme.mutedText)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isSelected ? Theme.selected : .clear, in: .rect(cornerRadius: Theme.Metrics.cornerRadius))
        .contentShape(.rect)
    }
}
