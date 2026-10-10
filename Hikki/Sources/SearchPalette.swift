import HikkiCore
import HikkiUI
import SwiftUI

/// ⌘K quick switcher: fuzzy/pinyin title matches first, then full-text body matches.
/// Mac/iPad show it as a centered overlay card (Notion-style); iPhone as a sheet.
struct SearchPalette: View {
    @Environment(AppModel.self) private var model
    let navigator: Navigator
    let dismiss: () -> Void
    @State private var query = ""
    @State private var results: [SearchHit] = []
    @State private var selection = 0
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: Spacing.s0) {
            HStack(spacing: Spacing.s2_5) {
                IconView(.magnifyingGlass, size: TextSize.base.rawValue).foregroundStyle(Theme.mutedForeground)
                TextField("app:search.placeholder", text: $query)
                    .textFieldStyle(.plain)
                    .font(.hk(.base))
                    .focused($fieldFocused)
                    .onSubmit(openSelection)
                    .accessibilityIdentifier("search-field")
                #if os(iOS)
                    Button("app:common.cancel", action: dismiss).foregroundStyle(Theme.subtleForeground)
                #endif
            }
            .padding(.horizontal, Spacing.s4)
            .frame(height: 52)
            Theme.border.frame(height: 1)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Spacing.px) {
                        if rows.isEmpty {
                            Text(query.isEmpty ? "app:search.noPages" : "app:search.noResults \(query)")
                                .font(.hk(.md))
                                .foregroundStyle(Theme.mutedForeground)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Spacing.s7)
                        }
                        ForEach(sections, id: \.title) { section in
                            Text(section.title)
                                .font(.hk(.xs, .medium))
                                .foregroundStyle(Theme.mutedForeground)
                                .padding(.horizontal, Spacing.s2_5)
                                .padding(.top, Spacing.s2_5)
                                .padding(.bottom, Spacing.s1)
                            ForEach(section.items, id: \.offset) { index, hit in
                                SearchResultRow(
                                    title: hit.title, icon: hit.icon, snippet: hit.snippet, path: path(of: hit.id),
                                    query: query, isSelected: index == selection
                                )
                                .id(index)
                                .onTapGesture { open(hit.id) }
                                .onHover { if $0 { selection = index } }
                            }
                        }
                    }
                    .padding(Spacing.s1_5)
                }
                .scrollIndicators(.automatic)
                .frame(maxHeight: 420)
                .fixedSize(horizontal: false, vertical: true)
                .onChange(of: selection) { _, index in proxy.scrollTo(index) }
            }

            #if os(macOS)
                Theme.border.frame(height: 1)
                HStack(spacing: Spacing.s3_5) {
                    hint("↑↓", "app:search.hintSelect")
                    hint("↵", "app:search.hintOpen")
                    hint("esc", "app:search.hintClose")
                    Spacer()
                }
                .padding(.horizontal, Spacing.s4)
                .frame(height: 34)
            #endif
        }
        .background(Theme.popover)
        .onAppear { fieldFocused = true }
        .onChange(of: query) { _, q in
            results = model.search(q)
            selection = 0
        }
        .onKeyPress(.downArrow) { move(1) }
        .onKeyPress(.upArrow) { move(-1) }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
    }

    private struct Section {
        let title: String
        let items: [(offset: Int, element: SearchHit)]
    }

    /// Indices stay global so ↑/↓ walks across sections.
    private var sections: [Section] {
        let indexed = Array(rows.enumerated())
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            return indexed.isEmpty ? [] : [Section(title: String(localized: "app:search.recent"), items: indexed)]
        }
        let titles = indexed.filter { $0.element.snippet.isEmpty }
        let content = indexed.filter { !$0.element.snippet.isEmpty }
        return [
            titles.isEmpty ? nil : Section(title: String(localized: "app:search.pages"), items: titles),
            content.isEmpty ? nil : Section(title: String(localized: "app:search.inContent"), items: content),
        ].compactMap(\.self)
    }

    private var rows: [SearchHit] {
        query.trimmingCharacters(in: .whitespaces).isEmpty
            ? model.tree.recent(limit: 8).map { SearchHit(id: $0.id, title: $0.title, icon: $0.icon, snippet: "") }
            : results
    }

    private func hint(_ key: String, _ label: LocalizedStringKey) -> some View {
        HStack(spacing: Spacing.s1) {
            Text(key)
                .font(.hk(.x2s, .medium))
                .padding(.horizontal, Spacing.s1)
                .padding(.vertical, Spacing.px)
                .background(Theme.accent, in: .rect(cornerRadius: Radius.sm))
            Text(label).font(.hk(.xs))
        }
        .foregroundStyle(Theme.mutedForeground)
    }

    private func path(of id: String) -> String {
        model.tree.path(to: id).dropLast().map { $0.title.isEmpty ? String(localized: "app:page.untitled") : $0.title }.joined(
            separator: " / ")
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        guard !rows.isEmpty else { return .ignored }
        selection = (selection + delta + rows.count) % rows.count
        return .handled
    }

    private func openSelection() {
        guard rows.indices.contains(selection) else { return }
        open(rows[selection].id)
    }

    private func open(_ id: String) {
        navigator.open(id)
        dismiss()
    }
}

/// Centered floating card with a dimmed backdrop (Mac/iPad).
struct SearchOverlay: View {
    let navigator: Navigator

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { navigator.isSearching = false }
            SearchPalette(navigator: navigator) { navigator.isSearching = false }
                .frame(maxWidth: 640)
                .clipShape(.rect(cornerRadius: Radius.xl))
                .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(Theme.border))
                .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
                .padding(.horizontal, Spacing.s6)
                .padding(.top, Spacing.s24)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
    }
}
