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
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 16)).foregroundStyle(Theme.mutedText)
                TextField("Search pages…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .focused($fieldFocused)
                    .onSubmit(openSelection)
                    .accessibilityIdentifier("search-field")
                #if os(iOS)
                    Button("Cancel", action: dismiss).foregroundStyle(Theme.secondaryText)
                #endif
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            Theme.border.frame(height: 1)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        if rows.isEmpty {
                            Text(query.isEmpty ? "No pages yet" : "No results for “\(query)”")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.mutedText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 28)
                        }
                        ForEach(sections, id: \.title) { section in
                            Text(section.title)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.mutedText)
                                .padding(.horizontal, 10)
                                .padding(.top, 10)
                                .padding(.bottom, 4)
                            ForEach(section.items, id: \.offset) { index, hit in
                                SearchResultRow(title: hit.title, icon: hit.icon, snippet: hit.snippet, path: path(of: hit.id),
                                                query: query, isSelected: index == selection)
                                    .id(index)
                                    .onTapGesture { open(hit.id) }
                                    .onHover { if $0 { selection = index } }
                            }
                        }
                    }
                    .padding(6)
                }
                .scrollIndicators(.automatic)
                .frame(maxHeight: 420)
                .fixedSize(horizontal: false, vertical: true)
                .onChange(of: selection) { _, index in proxy.scrollTo(index) }
            }

            #if os(macOS)
                Theme.border.frame(height: 1)
                HStack(spacing: 14) {
                    hint("↑↓", "Select")
                    hint("↵", "Open")
                    hint("esc", "Close")
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: 34)
            #endif
        }
        .background(Theme.elevated)
        .onAppear { fieldFocused = true }
        .onChange(of: query) { _, q in
            results = model.search(q)
            selection = 0
        }
        .onKeyPress(.downArrow) { move(1) }
        .onKeyPress(.upArrow) { move(-1) }
        .onKeyPress(.escape) { dismiss(); return .handled }
    }

    private struct Section {
        let title: String
        let items: [(offset: Int, element: SearchHit)]
    }

    /// Indices stay global so ↑/↓ walks across sections.
    private var sections: [Section] {
        let indexed = Array(rows.enumerated())
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            return indexed.isEmpty ? [] : [Section(title: String(localized: "Recent"), items: indexed)]
        }
        let titles = indexed.filter { $0.element.snippet.isEmpty }
        let content = indexed.filter { !$0.element.snippet.isEmpty }
        return [
            titles.isEmpty ? nil : Section(title: String(localized: "Pages"), items: titles),
            content.isEmpty ? nil : Section(title: String(localized: "In page content"), items: content),
        ].compactMap(\.self)
    }

    private var rows: [SearchHit] {
        query.trimmingCharacters(in: .whitespaces).isEmpty
            ? model.tree.recent(limit: 8).map { SearchHit(id: $0.id, title: $0.title, icon: $0.icon, snippet: "") }
            : results
    }

    private func hint(_ key: String, _ label: LocalizedStringKey) -> some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Theme.hover, in: .rect(cornerRadius: 4))
            Text(label).font(.system(size: 12))
        }
        .foregroundStyle(Theme.mutedText)
    }

    private func path(of id: String) -> String {
        model.tree.path(to: id).dropLast().map { $0.title.isEmpty ? String(localized: "Untitled") : $0.title }.joined(separator: " / ")
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
                .clipShape(.rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
                .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
                .padding(.horizontal, 24)
                .padding(.top, 90)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
    }
}
