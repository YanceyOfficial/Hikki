import SwiftUI

/// Notion's AI model menu as a popover list: "Auto" on top, then groups of models (Favorites, Recommended, Other
/// models), the chosen one checked, and a star at each row's end that stars or unstars the model (filled when it is a
/// favourite; unstarred ones show it faintly, fully on hover). Plain values in; the app orders the groups and keeps
/// the choice and the stars.
public struct ModelPickerList: View {
    public struct Item: Identifiable, Equatable, Sendable {
        public let id: String
        public let name: String
        /// Quieter text after the name (the provider).
        public let detail: String?
        public let isFavorite: Bool

        public init(id: String, name: String, detail: String? = nil, isFavorite: Bool = false) {
            self.id = id
            self.name = name
            self.detail = detail
            self.isFavorite = isFavorite
        }
    }

    public struct Group: Identifiable {
        public let id: String
        public let title: LocalizedStringKey
        public let items: [Item]

        public init(id: String, title: LocalizedStringKey, items: [Item]) {
            self.id = id
            self.title = title
            self.items = items
        }
    }

    private let autoID: String
    private let autoTitle: LocalizedStringKey
    private let autoDetail: LocalizedStringKey?
    private let groups: [Group]
    private let selection: String
    private let onSelect: (String) -> Void
    private let onToggleFavorite: (String) -> Void

    public init(
        autoID: String, autoTitle: LocalizedStringKey, autoDetail: LocalizedStringKey? = nil, groups: [Group],
        selection: String, onSelect: @escaping (String) -> Void, onToggleFavorite: @escaping (String) -> Void
    ) {
        self.autoID = autoID
        self.autoTitle = autoTitle
        self.autoDetail = autoDetail
        self.groups = groups
        self.selection = selection
        self.onSelect = onSelect
        self.onToggleFavorite = onToggleFavorite
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.px) {
                Row(
                    id: autoID, title: Text(autoTitle), detail: autoDetail.map { Text($0) }, isSelected: selection == autoID, star: nil,
                    onSelect: { onSelect(autoID) }
                )
                ForEach(groups) { group in
                    Text(group.title)
                        .font(.hk(.xs, .medium))
                        .foregroundStyle(Theme.mutedForeground)
                        .padding(.horizontal, Spacing.s2)
                        .padding(.top, Spacing.s2_5)
                        .padding(.bottom, Spacing.s1)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(group.items) { item in
                        Row(
                            id: item.id, title: Text(verbatim: item.name), detail: item.detail.map { Text(verbatim: $0) },
                            isSelected: selection == item.id, star: item.isFavorite,
                            onSelect: { onSelect(item.id) }, onStar: { onToggleFavorite(item.id) }
                        )
                    }
                }
            }
            .padding(Spacing.s1_5)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: Size.modelMenu)
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.popover)
    }

    /// A row; its pick button is `model-<id>`, its star `model-star-<id>` (UI tests).
    private struct Row: View {
        let id: String
        let title: Text
        let detail: Text?
        let isSelected: Bool
        /// nil: no star (Auto).
        let star: Bool?
        let onSelect: () -> Void
        var onStar: () -> Void = {}
        @State private var hovering = false

        var body: some View {
            HStack(spacing: Spacing.s2) {
                Button(action: onSelect) {
                    HStack(spacing: Spacing.s2) {
                        title.font(.hk(.sm)).foregroundStyle(Theme.foreground)
                        if let detail { detail.font(.hk(.xs)).foregroundStyle(Theme.mutedForeground) }
                        Spacer(minLength: Spacing.s2)
                        if isSelected {
                            IconView(.check, size: TextSize.sm.rawValue).foregroundStyle(Theme.foreground)
                        }
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("model-\(id)")
                if let star {
                    Button(action: onStar) {
                        IconView(star ? .starFill : .star, size: TextSize.sm.rawValue)
                            .foregroundStyle(star ? Theme.favorite : Theme.mutedForeground)
                            .opacity(star || hovering ? 1 : 0.45)
                            .frame(width: Size.iconButtonSm, height: Size.iconButtonSm)
                            .contentShape(.rect)
                    }
                    .buttonStyle(HoverHighlightStyle(cornerRadius: Radius.sm))
                    .accessibilityLabel(star ? "app:ai.model.unstar" : "app:ai.model.star")
                    .accessibilityIdentifier("model-star-\(id)")
                }
            }
            .padding(.horizontal, Spacing.s2)
            .frame(height: Size.iconButton + Spacing.s1)
            .background(hovering ? Theme.accent : .clear, in: .rect(cornerRadius: Radius.md))
            .onHover { hovering = $0 }
            .animation(Motion.easeOut(), value: hovering)
        }
    }
}

#Preview {
    ModelPickerList(
        autoID: "auto", autoTitle: "Auto",
        groups: [
            .init(id: "favorites", title: "Favorites", items: [.init(id: "o", name: "Opus 5.5", detail: "Anthropic", isFavorite: true)]),
            .init(
                id: "recommended", title: "Recommended",
                items: [
                    .init(id: "s", name: "Sonnet 5.5", detail: "Anthropic"), .init(id: "g", name: "GPT-6.1 Sol", detail: "OpenAI"),
                ]),
        ],
        selection: "s", onSelect: { _ in }, onToggleFavorite: { _ in })
}
