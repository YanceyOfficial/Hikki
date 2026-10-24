import HikkiCore
import HikkiSearch
import HikkiUI
import SwiftUI

/// ⌘K search (Notion's): one list of best matches — titles, also by pinyin, ahead of page text (`SearchRanker`) —
/// each with its path, an excerpt around the match and the edited time; recent pages while the field is empty; nothing
/// at all when nothing matches. Chips under the field narrow where the words
/// may match (All / Titles / Text / Files, `SearchScope`) and a menu at their end orders by match or by edited time.
/// Mac/iPad show it as a centered overlay card; iPhone as a sheet.
struct SearchPalette: View {
    @Environment(AppModel.self) private var model
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    let navigator: Navigator
    let dismiss: () -> Void
    @State private var query = ""
    @State private var results: [SearchHit] = []
    @State private var selection = 0
    /// Pages whose other matches are open under their row, and those showing all of them (not just the first few).
    @State private var expanded: Set<String> = []
    @State private var showingAll: Set<String> = []
    @State private var options = SearchOptions.standard
    @FocusState private var fieldFocused: Bool

    var body: some View {
        screen.screenTitle(String(localized: "app:nav.search"))
    }

    @ViewBuilder private var screen: some View {
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
                            .frame(width: Size.iconButton, height: Size.iconButton)
                            .contentShape(.rect)
                    }
                    .buttonStyle(HoverHighlightStyle(cornerRadius: Radius.full))
                    .help("app:search.close")
                    .accessibilityLabel("app:search.close")
                    .accessibilityIdentifier("search-close")
                #endif
            }
            .padding(.horizontal, Spacing.s4)
            .frame(height: Size.searchHeader)
            filters
            Theme.border.frame(height: Spacing.px)

            ScrollViewReader { proxy in
                ScrollView {
                    // A plain stack keyed by page: lazily made rows keyed by position kept showing the recent pages
                    // after the first search of a newly opened palette (and stopped following hover).
                    VStack(alignment: .leading, spacing: Spacing.px) {
                        if items.isEmpty {
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
                            ForEach(section.items, id: \.element.id) { index, item in
                                row(item, isSelected: index == selection)
                                    .id(item.id)
                                    .onTapGesture { activate(item) }
                                    .onHover { if $0 { selection = index } }
                            }
                        }
                    }
                    .padding(Spacing.s1_5)
                }
                .scrollIndicators(.automatic)
                // A phone fills the screen: the results take the rest of it, so the field never moves (results
                // sized to their content shifted the whole screen with every keystroke, and the keyboard pushed
                // the field out of sight). Elsewhere the card grows with its results.
                .frame(maxHeight: phone ? .infinity : Size.searchResults)
                .fixedSize(horizontal: false, vertical: !phone)
                .onChange(of: selection) { _, index in
                    if items.indices.contains(index) { proxy.scrollTo(items[index].id) }
                }
            }

            #if os(macOS)
                Theme.border.frame(height: Spacing.px)
                HStack(spacing: Spacing.s3_5) {
                    hint("↑↓", "app:search.hintSelect")
                    hint("↵", "app:search.hintOpen")
                    hint("esc", "app:search.hintClose")
                    Spacer()
                }
                .padding(.horizontal, Spacing.s4)
                .frame(height: Size.searchField)
            #endif
        }
        .background(phone ? Theme.background : Theme.popover)
        #if os(iOS)
            // A phone: the whole screen (presented full screen by ContentView); a page-sized sheet on iPad.
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
        // Searched off the main thread (the index may be busy writing; typing never waits for it). A newer query
        // cancels the older one's task, so a late answer can't replace a newer list.
        .task(id: SearchKey(query: query, options: options)) {
            let found = await model.search(query, options: options)
            guard !Task.isCancelled else { return }
            #if DEBUG
                // What reached the index (as code points) and what came back — ids and counts only.
                Log.info(
                    "palette search", category: "search",
                    context: [
                        "scalars": query.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: " "),
                        "results": "\(found.count)", "top": found.prefix(3).map(\.id).joined(separator: ","),
                    ])
            #endif
            results = found
            selection = 0
            expanded = []
            showingAll = []
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
    private var phoneChips: Bool { phone }

    /// A compact window (a phone, a folded iPhone Duo): search fills it.
    private var phone: Bool {
        #if os(iOS)
            sizeClass == .compact
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
        let items: [(offset: Int, element: Item)]
    }

    private typealias Item = SearchListItem

    private var items: [Item] {
        SearchListItem.list(rows, expanded: expanded, showingAll: showingAll)
    }

    @ViewBuilder
    private func row(_ item: Item, isSelected: Bool) -> some View {
        switch item {
        case .page(let hit):
            SearchResultRow(
                title: hit.title, icon: hit.icon, snippet: hit.snippet, path: path(of: hit.id), terms: hit.terms,
                attachment: hit.attachment.map { $0.label ?? String(localized: "app:search.image") },
                updatedAt: hit.updatedAt, isSelected: isSelected)
        case .match(let hit, let match):
            SearchMatchRow(snippet: match.snippet, terms: hit.terms, isSelected: isSelected)
        case .toggle(_, let toggle):
            switch toggle {
            case .expand(let count):
                SearchMatchesToggleRow(String(localized: "app:search.moreMatches \(String(count))"), isSelected: isSelected)
                    .accessibilityIdentifier("search-more-matches")
            case .showAll(let remaining):
                SearchMatchesToggleRow(
                    String(localized: "app:search.showMoreMatches \(String(remaining))"), isExpanded: true, isSelected: isSelected)
            case .collapse:
                SearchMatchesToggleRow(String(localized: "app:search.fewerMatches"), isExpanded: true, isSelected: isSelected)
            }
        }
    }

    /// Indices stay global so ↑/↓ walks across sections.
    private var sections: [Section] {
        let indexed = Array(items.enumerated())
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            return indexed.isEmpty ? [] : [Section(title: String(localized: "app:search.recent"), items: indexed)]
        }
        return indexed.isEmpty ? [] : [Section(title: String(localized: "app:search.bestMatches"), items: indexed)]
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
        model.tree.path(to: id).dropLast().map(\.displayTitle).joined(separator: " / ")
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        let count = items.count
        guard count > 0 else { return .ignored }
        selection = (selection + delta + count) % count
        return .handled
    }

    private func openSelection() {
        let items = items
        guard items.indices.contains(selection) else { return }
        activate(items[selection])
    }

    /// A page or one of its matches opens; the toggle opens, extends or folds the matches (the selection stays on it,
    /// or goes back to the page when they fold).
    private func activate(_ item: Item) {
        switch item {
        case .page(let hit): open(hit)
        case .match(let hit, let match):
            navigator.open(hit.id, at: match.blockId, revealing: hit.terms)
            dismiss()
        case .toggle(let hit, let toggle):
            switch toggle {
            case .expand: expanded.insert(hit.id)
            case .showAll: showingAll.insert(hit.id)
            case .collapse:
                expanded.remove(hit.id)
                showingAll.remove(hit.id)
                if let index = items.firstIndex(where: { $0.id == hit.id }) { selection = index }
            }
        }
    }

    /// A result whose excerpt is the page's own text opens at its block (or, indexed without one, the first place
    /// its words occur), the words selected; a file match at the block showing the file (no words to select there);
    /// a title match at the top.
    private func open(_ hit: SearchHit) {
        if hit.attachment != nil, let block = hit.blockId {
            navigator.open(hit.id, at: block, revealing: [])
        } else if !hit.snippet.isEmpty, hit.attachment == nil {
            navigator.open(hit.id, at: hit.blockId, revealing: hit.terms)
        } else {
            navigator.open(hit.id)
        }
        dismiss()
    }
}
