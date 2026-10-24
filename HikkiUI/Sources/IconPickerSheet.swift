import SwiftUI

/// An emoji as the icon picker shows it.
public nonisolated struct IconPickerEmoji: Identifiable, Hashable, Sendable {
    public var emoji: String
    /// Its name, for VoiceOver.
    public var label: String
    public var id: String { emoji }

    public init(emoji: String, label: String) {
        self.emoji = emoji
        self.label = label
    }
}

/// A group of the picker, its first emoji standing for it in the category bar.
public nonisolated struct IconPickerSection: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var emojis: [IconPickerEmoji]

    public init(id: String, title: String, emojis: [IconPickerEmoji]) {
        self.id = id
        self.title = title
        self.emojis = emojis
    }
}

/// A phone's icon picker, Notion's: a search field, a bar of the categories (a tap jumps to one), then a grid — recently
/// picked first, every category under its title — with Remove and Random in the bar. A callout's picker also has its
/// background colours along the foot. Plain values in, picks out; `sections` nil while the catalog loads (or for good
/// when it `failed`).
public struct IconPickerSheet: View {
    let title: LocalizedStringKey
    let sections: [IconPickerSection]?
    let failed: Bool
    let recents: [IconPickerEmoji]
    let current: String?
    let search: (String) -> [IconPickerEmoji]
    let onPick: (String) -> Void
    let onRandom: (() -> Void)?
    let onRemove: (() -> Void)?
    /// A callout's background: the chosen palette name (nil: the default) and what a pick does. Nil: no colours.
    let color: (selected: String?, onPick: (String?) -> Void)?
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    public init(
        title: LocalizedStringKey, sections: [IconPickerSection]?, failed: Bool = false, recents: [IconPickerEmoji],
        current: String?,
        search: @escaping (String) -> [IconPickerEmoji], onPick: @escaping (String) -> Void,
        onRandom: (() -> Void)? = nil, onRemove: (() -> Void)? = nil,
        color: (selected: String?, onPick: (String?) -> Void)? = nil
    ) {
        self.title = title
        self.sections = sections
        self.failed = failed
        self.recents = recents
        self.current = current
        self.search = search
        self.onPick = onPick
        self.onRandom = onRandom
        self.onRemove = onRemove
        self.color = color
    }

    public var body: some View {
        NavigationStack {
            ScrollViewReader { scroller in
                VStack(spacing: Spacing.s0) {
                    searchField.padding(.horizontal, Spacing.s4).padding(.bottom, Spacing.s2)
                    if let sections, query.isEmpty {
                        categoryBar(sections, scroller: scroller)
                    }
                    Divider()
                    ScrollView {
                        content.padding(.horizontal, Spacing.s3).padding(.bottom, Spacing.s4)
                    }
                    .scrollDismissesKeyboard(.immediately)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: Spacing.s0) {
                if let color { CalloutColorBar(selected: color.selected, onPick: color.onPick) }
            }
            .navigationTitle(Text(title))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if let onRemove {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .destructive) {
                            dismiss()
                            onRemove()
                        } label: {
                            Text("app:icon.remove")
                        }
                        .accessibilityIdentifier("icon-remove")
                    }
                }
                if let onRandom {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            dismiss()
                            onRandom()
                        } label: {
                            IconLabel("app:icon.random", icon: .shuffle)
                        }
                        .accessibilityIdentifier("icon-random")
                    }
                }
            }
        }
        .accessibilityIdentifier("icon-picker-sheet")
    }

    private var searchField: some View {
        HStack(spacing: Spacing.s2) {
            IconView(.magnifyingGlass, size: TextSize.base.rawValue).foregroundStyle(Theme.mutedForeground)
            TextField(text: $query) { Text("app:icon.search") }
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { if let first = search(query).first { pick(first.emoji) } }
                .accessibilityIdentifier("icon-search")
        }
        .padding(.horizontal, Spacing.s3)
        .frame(height: Size.searchField)
        .background(Theme.muted, in: .rect(cornerRadius: Radius.lg))
    }

    /// Each category by its first emoji, greyed until tapped (the web picker's bar).
    private func categoryBar(_ sections: [IconPickerSection], scroller: ScrollViewProxy) -> some View {
        HStack(spacing: Spacing.s0) {
            ForEach(sections) { section in
                Button {
                    withAnimation(Motion.easeInOut()) { scroller.scrollTo(section.id, anchor: .top) }
                } label: {
                    Text(verbatim: section.emojis.first?.emoji ?? "")
                        .font(.system(size: TextSize.lg.rawValue))  // design-lint: allow (an emoji at a token size)
                        .grayscale(1)
                        .opacity(0.7)
                        .frame(maxWidth: .infinity, minHeight: Size.iconButton)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: section.title))
            }
        }
        .padding(.horizontal, Spacing.s3)
        .padding(.bottom, Spacing.s1)
    }

    @ViewBuilder private var content: some View {
        if !query.isEmpty {
            let found = search(query)
            if found.isEmpty {
                status("app:icon.empty")
            } else {
                grid(found)
            }
        } else if let sections {
            LazyVStack(alignment: .leading, spacing: Spacing.s0, pinnedViews: .sectionHeaders) {
                if !recents.isEmpty {
                    Section {
                        grid(recents)
                    } header: {
                        header(Text("app:icon.recent"))
                    }
                }
                ForEach(sections) { section in
                    Section {
                        grid(section.emojis)
                    } header: {
                        header(Text(verbatim: section.title)).id(section.id)
                    }
                }
            }
        } else {
            status(failed ? "app:icon.failed" : "app:icon.loading")
        }
    }

    private func grid(_ emojis: [IconPickerEmoji]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: Size.emojiCell), spacing: Spacing.s0)], spacing: Spacing.s0) {
            ForEach(emojis) { item in
                Button {
                    pick(item.emoji)
                } label: {
                    Text(verbatim: item.emoji)
                        .font(.system(size: TextSize.x3l.rawValue))  // design-lint: allow (an emoji at a token size)
                        .frame(maxWidth: .infinity, minHeight: Size.emojiCell)
                        .background(
                            item.emoji == current ? Theme.accent : Color.clear, in: .rect(cornerRadius: Radius.md)
                        )
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: item.label))
                .accessibilityIdentifier("icon-emoji")
            }
        }
    }

    private func header(_ text: Text) -> some View {
        text
            .font(.hk(.xs, .medium))
            .foregroundStyle(Theme.mutedForeground)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.s1)
            .padding(.top, Spacing.s3)
            .padding(.bottom, Spacing.s1_5)
            .background(.bar)
    }

    private func status(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.hk(.sm))
            .foregroundStyle(Theme.mutedForeground)
            .frame(maxWidth: .infinity)
            .padding(Spacing.s7)
    }

    private func pick(_ emoji: String) {
        dismiss()
        onPick(emoji)
    }
}

/// A callout's background colours: the default, then the palette's washes, the chosen one ringed. A pick keeps the
/// sheet open (the icon is still to choose, or not).
private struct CalloutColorBar: View {
    let selected: String?
    let onPick: (String?) -> Void
    @Environment(\.colorTone) private var tone

    var body: some View {
        HStack(spacing: Spacing.s0) {
            ForEach([nil] + PanelPalette.names, id: \.self) { (name: String?) in
                Button {
                    onPick(name)
                } label: {
                    Circle()
                        .fill(PanelPalette.wash(name ?? "gray"))
                        .overlay { Circle().strokeBorder(Theme.border, lineWidth: Spacing.px) }
                        .frame(width: Size.colorSwatch, height: Size.colorSwatch)
                        .padding(Spacing.s1)
                        .overlay {
                            if name == selected { Circle().strokeBorder(tone.fill, lineWidth: Spacing.s0_5) }
                        }
                        .frame(maxWidth: .infinity, minHeight: Size.iconButton)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(PanelPalette.label(name)))
                .accessibilityAddTraits(name == selected ? .isSelected : [])
                .accessibilityIdentifier("callout-color-\(name ?? "default")")
            }
        }
        .padding(.horizontal, Spacing.s3)
        .padding(.vertical, Spacing.s2)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("app:icon.calloutColor"))
    }
}

#Preview("Page icon") {
    let sections = [
        IconPickerSection(
            id: "smileys", title: "Smileys & emotion",
            emojis: ["😀", "😃", "😄", "😁", "😆", "🥹", "😅", "😂"].map { IconPickerEmoji(emoji: $0, label: $0) }),
        IconPickerSection(
            id: "animals", title: "Animals & nature",
            emojis: ["🐶", "🐱", "🐭", "🐹", "🐰", "🦊"].map { IconPickerEmoji(emoji: $0, label: $0) }),
    ]
    IconPickerSheet(
        title: "Icon", sections: sections, recents: [IconPickerEmoji(emoji: "🌸", label: "🌸")], current: "🐶",
        search: { _ in [] }, onPick: { _ in }, onRandom: {}, onRemove: {})
}

#Preview("Callout") {
    IconPickerSheet(
        title: "Icon", sections: nil, recents: [], current: "💡", search: { _ in [] }, onPick: { _ in },
        color: (selected: "blue", onPick: { _ in }))
}
