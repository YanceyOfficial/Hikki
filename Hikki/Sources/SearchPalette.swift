import HikkiCore
import HikkiUI
import SwiftUI

/// ⌘K quick switcher: fuzzy/pinyin title matches first, then full-text body matches.
struct SearchPalette: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let navigator: Navigator
    @State private var query = ""
    @State private var results: [SearchHit] = []
    @State private var selection = 0
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.mutedText)
                TextField("Search pages…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .focused($fieldFocused)
                    .onSubmit(openSelection)
                    .accessibilityIdentifier("search-field")
                #if os(iOS)
                    Button("Cancel") { dismiss() }
                #endif
            }
            .padding(14)
            Divider()
            ScrollViewReader { proxy in
                List {
                    Section {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, hit in
                            Button { open(hit.id) } label: {
                                SearchResultRow(title: hit.title, icon: hit.icon, snippet: hit.snippet, path: path(of: hit.id))
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(index == selection ? Theme.selected : Color.clear)
                            .id(index)
                        }
                    } header: {
                        Text(query.isEmpty ? "Recent" : rows.isEmpty ? "No results" : "Best matches")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.mutedText)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .onChange(of: selection) { _, index in proxy.scrollTo(index) }
            }
        }
        .background(Theme.elevated)
        #if os(macOS)
        .frame(width: 620, height: 440)
        #endif
        .onAppear { fieldFocused = true }
        .onChange(of: query) { _, q in
            results = model.search(q)
            selection = 0
        }
        .onKeyPress(.downArrow) { move(1) }
        .onKeyPress(.upArrow) { move(-1) }
        .onKeyPress(.escape) { dismiss(); return .handled }
    }

    private var rows: [SearchHit] {
        query.trimmingCharacters(in: .whitespaces).isEmpty
            ? model.tree.recent(limit: 8).map { SearchHit(id: $0.id, title: $0.title, icon: $0.icon, snippet: "") }
            : results
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
