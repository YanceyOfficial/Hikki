import HikkiCore
import HikkiSearch
import HikkiUI
import SwiftUI

/// ⌘K search (Notion's): one list of best matches — titles, also by pinyin, ahead of page text (`SearchRanker`) —
/// each with its path, an excerpt around the match and the edited time; recent pages while the field is empty. With
/// semantic search on, the few pages that stand out by meaning follow under "Similar in meaning", each showing its
/// closest sentence; nothing at all is listed when nothing matches. Chips under the field narrow where the words
/// may match (All / Titles / Text / Files, `SearchScope`) and a menu at their end orders by match or by edited time.
/// Mac/iPad show it as a centered overlay card; iPhone as a sheet.
struct SearchPalette: View {
    @Environment(AppModel.self) private var model
    let navigator: Navigator
    let dismiss: () -> Void
    @State private var query = ""
    @State private var results: [SearchHit] = []
    @State private var selection = 0
    @State private var options = SearchOptions.standard
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
                #else
                    // A sheet on the Mac can't be clicked away: Escape or this.
                    Button(action: dismiss) {
                        IconView(.x, size: TextSize.sm.rawValue)
                            .foregroundStyle(Theme.mutedForeground)
                            .frame(width: Size.iconButtonSm, height: Size.iconButtonSm)
                            .contentShape(.rect)
                    }
                    .buttonStyle(HoverHighlightStyle(cornerRadius: Radius.full))
                    .help("app:search.close")
                    .accessibilityLabel("app:search.close")
                    .accessibilityIdentifier("search-close")
                #endif
            }
            .padding(.horizontal, Spacing.s4)
            .frame(height: 52)
            filters
            Theme.border.frame(height: 1)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Spacing.px) {
                        // No page has the words: said so, also above pages that are only close in meaning.
                        if rows.isEmpty || !query.isEmpty && rows.allSatisfy(\.related) {
                            Text(query.isEmpty ? "app:search.noPages" : "app:search.noResults \(query)")
                                .font(.hk(.md))
                                .foregroundStyle(Theme.mutedForeground)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, rows.isEmpty ? Spacing.s7 : Spacing.s4)
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
                                    terms: hit.terms,
                                    attachment: hit.attachment.map { $0.label ?? String(localized: "app:search.image") },
                                    updatedAt: hit.updatedAt, isSelected: index == selection
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
                .frame(maxHeight: Size.searchResults)
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
        #if os(iOS)
            // A phone sheet: the field at the top, not floating mid-way above the keyboard; a page-sized one on iPad.
            .frame(maxHeight: .infinity, alignment: .top)
            .presentationSizing(.page)
        #else
            .frame(width: Size.searchWidth)
        #endif
        .onAppear {
            fieldFocused = true
            #if DEBUG
                // HIKKI_OPEN_SEARCH=<text> opens ⌘K with that query (screenshots).
                if let text = ProcessInfo.processInfo.environment["HIKKI_OPEN_SEARCH"], !text.isEmpty, query.isEmpty {
                    query = text
                }
            #endif
        }
        .onChange(of: query) { _, q in
            results = model.search(q, options: options)
            selection = 0
        }
        .onChange(of: options) { _, new in
            results = model.search(query, options: new)
            selection = 0
        }
        // Then by meaning too (Settings → Search → Semantic search), once typing pauses: pages related only by
        // meaning follow under their own heading (unfiltered searches only).
        .task(id: SearchKey(query: query, options: options)) {
            let text = query
            let options = options
            guard model.semantic.isEnabled, options.scope == .all, SearchIndex.meansSomething(text) else { return }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let vector = await model.semantic.queryVector(text), !Task.isCancelled,
                text == query, options == self.options
            else { return }
            let found = model.search(text, queryVector: vector, options: options)
            let sharpened = await model.semantic.sharpen(found, queryVector: vector)
            guard !Task.isCancelled, text == query, options == self.options else { return }
            results = sharpened
            selection = min(selection, max(results.count - 1, 0))
        }
        // While an input method is composing, its candidates own the arrows and Escape.
        .onKeyPress(.downArrow) { TextComposition.isActive ? .ignored : move(1) }
        .onKeyPress(.upArrow) { TextComposition.isActive ? .ignored : move(-1) }
        .onKeyPress(.escape) {
            guard !TextComposition.isActive else { return .ignored }
            dismiss()
            return .handled
        }
    }

    private struct SearchKey: Equatable {
        let query: String
        let options: SearchOptions
    }

    /// The scope chips and, at the row's end, the sort menu.
    private var filters: some View {
        HStack(spacing: Spacing.s2) {
            ScrollView(.horizontal) {
                HStack(spacing: phoneChips ? Spacing.s2 : Spacing.s1_5) {
                    ForEach(SearchScope.allCases, id: \.self) { scope in
                        FilterChip(title(scope), isSelected: options.scope == scope, look: phoneChips ? .filled : .subtle) {
                            options.scope = scope
                        }
                        .accessibilityIdentifier("search-scope-\(scope.rawValue)")
                    }
                }
            }
            .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            Menu {
                Picker(selection: $options.sort) {
                    ForEach(SearchSort.allCases, id: \.self) { sort in
                        Text(title(sort)).tag(sort)
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: Spacing.s1) {
                    Text(title(options.sort)).font(.hk(.xs, .medium))
                    IconView(.caretDown, size: TextSize.x2s.rawValue)
                }
                .foregroundStyle(Theme.mutedForeground)
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("app:search.sort")
            .accessibilityLabel("app:search.sort")
            .accessibilityIdentifier("search-sort")
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.bottom, Spacing.s2_5)
    }

    /// iPhone: the larger, filled chips of the phone's search sheet.
    private var phoneChips: Bool {
        #if os(iOS)
            UIDevice.current.userInterfaceIdiom == .phone
        #else
            false
        #endif
    }

    private func title(_ scope: SearchScope) -> LocalizedStringKey {
        switch scope {
        case .all: "app:search.scope.all"
        case .titles: "app:search.scope.titles"
        case .text: "app:search.scope.text"
        case .files: "app:search.scope.files"
        }
    }

    private func title(_ sort: SearchSort) -> LocalizedStringKey {
        switch sort {
        case .relevance: "app:search.sort.relevance"
        case .edited: "app:search.sort.edited"
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
        let matches = indexed.filter { !$0.element.related }
        let related = indexed.filter { $0.element.related }
        var out: [Section] = []
        if !matches.isEmpty { out.append(Section(title: String(localized: "app:search.bestMatches"), items: matches)) }
        if !related.isEmpty { out.append(Section(title: String(localized: "app:search.related"), items: related)) }
        return out
    }

    private var rows: [SearchHit] {
        query.trimmingCharacters(in: .whitespaces).isEmpty
            ? model.tree.recent(limit: 10).map {
                SearchHit(id: $0.id, title: $0.title, icon: $0.icon, snippet: "", updatedAt: $0.updatedAt, terms: [])
            }
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
