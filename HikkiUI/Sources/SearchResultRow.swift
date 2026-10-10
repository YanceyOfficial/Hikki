import SwiftUI

/// One result in the search palette: icon, title, optional body excerpt and breadcrumb path.
public struct SearchResultRow: View {
    private let title: String
    private let icon: String?
    private let snippet: String
    private let path: String

    public init(title: String, icon: String?, snippet: String = "", path: String = "") {
        self.title = title
        self.icon = icon
        self.snippet = snippet
        self.path = path
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 10) {
            PageIcon(icon, size: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title.isEmpty ? String(localized: "Untitled") : title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    if !path.isEmpty {
                        Text(path).font(.system(size: 12)).foregroundStyle(Theme.mutedText).lineLimit(1)
                    }
                }
                if !snippet.isEmpty {
                    Text(snippet).font(.system(size: 12)).foregroundStyle(Theme.secondaryText).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
    }
}
