import HikkiCore
import HikkiUI
import SwiftUI

/// How Home shows the workspace's pages.
enum HomeLayout: String, CaseIterable, Identifiable {
    case table, gallery

    static let storageKey = "home.layout"

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .table: "app:home.layout.table"
        case .gallery: "app:home.layout.gallery"
        }
    }

    var icon: Icon {
        switch self {
        case .table: .listBullets
        case .gallery: .browsers
        }
    }
}

/// One page as Home lists it: what the columns show, flattened so the table can sort on any of them.
nonisolated struct HomeRow: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let icon: String?
    let location: String
    let createdAt: Date
    let updatedAt: Date
    let words: Int
    let isFavorite: Bool
}

/// The order of Home's rows: a column and a direction (the table's headers set it; a menu does elsewhere).
nonisolated struct HomeSort: SortComparator, Hashable, Sendable {
    enum Field: String, Hashable, Sendable {
        case name, location, created, edited, words, favorite
    }

    var field: Field
    var order: SortOrder = .forward

    func compare(_ a: HomeRow, _ b: HomeRow) -> ComparisonResult {
        let result: ComparisonResult =
            switch field {
            case .name: a.title.localizedStandardCompare(b.title)
            case .location: a.location.localizedStandardCompare(b.location)
            case .created: Self.compare(a.createdAt, b.createdAt)
            case .edited: Self.compare(a.updatedAt, b.updatedAt)
            case .words: Self.compare(a.words, b.words)
            case .favorite: Self.compare(a.isFavorite ? 1 : 0, b.isFavorite ? 1 : 0)
            }
        return order == .forward ? result : result.reversed
    }

    private static func compare<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
        a < b ? .orderedAscending : a > b ? .orderedDescending : .orderedSame
    }
}

extension ComparisonResult {
    nonisolated fileprivate var reversed: ComparisonResult {
        switch self {
        case .orderedAscending: .orderedDescending
        case .orderedDescending: .orderedAscending
        case .orderedSame: .orderedSame
        }
    }
}

/// Home: every page of the workspace as a database (Notion's) — a sortable table of names, places, dates and sizes,
/// or a gallery of cards — with a filter and New Page on top. iPhone gets the same as a list.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    let navigator: Navigator
    @AppStorage(HomeLayout.storageKey) private var layout = HomeLayout.table
    @State private var filter = ""
    @State private var sortOrder = [HomeSort(field: .edited, order: .reverse)]
    @State private var selection: Set<HomeRow.ID> = []
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    private var compact: Bool {
        #if os(iOS)
            sizeClass == .compact
        #else
            false
        #endif
    }

    var body: some View {
        let rows = self.rows
        if compact {
            phone(rows)
        } else {
            wide(rows)
        }
    }

    private func wide(_ rows: [HomeRow]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s0) {
            header(count: rows.count)
                .padding(.horizontal, Spacing.s6)
                .padding(.top, Spacing.s6)
                .padding(.bottom, Spacing.s3)
            if model.tree.all.isEmpty {
                empty("app:home.empty")
            } else if rows.isEmpty {
                empty("app:home.noMatches")
            } else {
                switch layout {
                case .table: table(rows)
                case .gallery: gallery(rows)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // One surface with the table under the title (Music's): the table's own background, not the page's darker one.
        .background(Theme.listSurface)
        .navigationTitle("app:nav.home")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: Rows

    private var rows: [HomeRow] {
        let query = filter.trimmingCharacters(in: .whitespaces)
        let untitled = String(localized: "app:page.untitled")
        return model.tree.all
            .map { page in
                HomeRow(
                    id: page.id, title: page.title.isEmpty ? untitled : page.title, icon: page.icon,
                    location: model.tree.path(to: page.id).dropLast()
                        .map { $0.title.isEmpty ? untitled : $0.title }
                        .joined(separator: " › "),
                    createdAt: page.createdAt, updatedAt: page.updatedAt, words: page.wordCount,
                    isFavorite: page.isFavorite)
            }
            .filter { query.isEmpty || $0.title.localizedStandardContains(query) || $0.location.localizedStandardContains(query) }
            .sorted(using: sortOrder)
    }

    // MARK: Header

    private func header(count: Int) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s2) {
                Text("app:home.allPages").font(.hk(.x2l, .bold)).foregroundStyle(Theme.foreground)
                Text(count, format: .number).font(.hk(.md)).foregroundStyle(Theme.mutedForeground)
                Spacer()
            }
            HStack(spacing: Spacing.s2) {
                if !compact {
                    Picker("app:home.layout", selection: $layout) {
                        ForEach(HomeLayout.allCases) { item in
                            IconLabel(item.title, icon: item.icon).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityIdentifier("home-layout")
                }
                Spacer()
                HStack(spacing: Spacing.s1_5) {
                    IconView(.magnifyingGlass, size: TextSize.sm.rawValue).foregroundStyle(Theme.mutedForeground)
                    TextField("app:home.filter", text: $filter)
                        .textFieldStyle(.plain)
                        .font(.hk(.md))
                        .accessibilityIdentifier("home-filter")
                }
                .padding(.horizontal, Spacing.s2_5)
                .frame(width: Size.homeFilter, height: Size.searchField)
                .background(Theme.muted, in: .rect(cornerRadius: Radius.md))
                if compact || layout == .gallery {
                    sortMenu
                }
                Button {
                    navigator.newPage()
                } label: {
                    IconLabel("app:page.new", icon: .notePencil)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("home-new-page")
            }
        }
    }

    /// The gallery and the phone list have no column headers to click: a menu picks the order.
    private var sortMenu: some View {
        Menu {
            Picker("app:home.sort", selection: sortField) {
                Text("app:home.column.edited").tag(HomeSort.Field.edited)
                Text("app:home.column.created").tag(HomeSort.Field.created)
                Text("app:home.column.name").tag(HomeSort.Field.name)
                Text("app:home.column.words").tag(HomeSort.Field.words)
            }
        } label: {
            IconLabel("app:home.sort", icon: .caretUpDown)
        }
        .fixedSize()
        .accessibilityIdentifier("home-sort")
    }

    /// Names sort A→Z; dates and sizes newest/largest first.
    private var sortField: Binding<HomeSort.Field> {
        Binding {
            sortOrder.first?.field ?? .edited
        } set: { field in
            sortOrder = [HomeSort(field: field, order: field == .name ? .forward : .reverse)]
        }
    }

    private func empty(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.hk(.md))
            .foregroundStyle(Theme.mutedForeground)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Layouts

    /// Notion's table view: click a header to sort, double-click (or Return) a row to open it.
    private func table(_ rows: [HomeRow]) -> some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("app:home.column.name", sortUsing: HomeSort(field: .name)) { row in
                HStack(spacing: Spacing.s2) {
                    PageIcon(row.icon, size: 16)
                    Text(row.title).lineLimit(1)
                }
                .accessibilityIdentifier("home-row-\(row.title)")
            }
            .width(min: 180, ideal: 280)  // design-lint: allow (table column widths)
            TableColumn("app:home.column.location", sortUsing: HomeSort(field: .location)) { row in
                Text(row.location).foregroundStyle(Theme.subtleForeground).lineLimit(1)
            }
            .width(min: 100, ideal: 180)  // design-lint: allow (table column widths)
            TableColumn("app:home.column.created", sortUsing: HomeSort(field: .created)) { row in
                Text(row.createdAt, format: .dateTime.year().month().day()).foregroundStyle(Theme.subtleForeground)
            }
            .width(min: 90, ideal: 110)  // design-lint: allow (table column widths)
            TableColumn("app:home.column.edited", sortUsing: HomeSort(field: .edited)) { row in
                Text(row.updatedAt, format: .relative(presentation: .named)).foregroundStyle(Theme.subtleForeground)
            }
            .width(min: 90, ideal: 120)  // design-lint: allow (table column widths)
            TableColumn("app:home.column.words", sortUsing: HomeSort(field: .words)) { row in
                Text(row.words, format: .number).foregroundStyle(Theme.subtleForeground).monospacedDigit()
            }
            .width(min: 50, ideal: 70)  // design-lint: allow (table column widths)
            TableColumn("app:home.column.favorite", sortUsing: HomeSort(field: .favorite)) { row in
                if row.isFavorite {
                    IconView(.star, size: TextSize.sm.rawValue).foregroundStyle(Theme.subtleForeground)
                }
            }
            .width(min: 40, ideal: 60)  // design-lint: allow (table column widths)
        }
        .contextMenu(forSelectionType: HomeRow.ID.self) { ids in
            if ids.count == 1, let id = ids.first, let page = model.tree.page(id) {
                PageActions(page: page, navigator: navigator)
            }
        } primaryAction: { ids in
            if let id = ids.first { navigator.openFromSidebar(.page(id)) }
        }
        // Its rows on the screen's own surface, so the title above and the table read as one.
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("home-table")
    }

    private func gallery(_ rows: [HomeRow]) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Size.homeCard), spacing: Spacing.s3)], spacing: Spacing.s3) {
                ForEach(rows) { row in
                    Button {
                        navigator.openFromSidebar(.page(row.id))
                    } label: {
                        HomeCard(row: row)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if let page = model.tree.page(row.id) { PageActions(page: page, navigator: navigator) }
                    }
                    .accessibilityIdentifier("home-card-\(row.title)")
                }
            }
            .padding(.horizontal, Spacing.s6)
            .padding(.bottom, Spacing.s6)
        }
    }

    // MARK: iPhone

    /// iPhone: a large title, the filter as a capsule, pages under day headings (when ordered by edit time) as plain
    /// rows, the order in the bar's menu and New Page floating at the bottom right.
    private func phone(_ rows: [HomeRow]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.s0) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s2_5) {
                    Text("app:home.allPages").font(.hk(.x3l, .bold)).foregroundStyle(Theme.foreground)
                    Text(rows.count, format: .number).font(.hk(.lg)).foregroundStyle(Theme.mutedForeground)
                }
                .padding(.bottom, Spacing.s3)
                HStack(spacing: Spacing.s2) {
                    IconView(.magnifyingGlass, size: TextSize.base.rawValue).foregroundStyle(Theme.mutedForeground)
                    TextField("app:home.filter", text: $filter)
                        .font(.hk(.base))
                        .accessibilityIdentifier("home-filter")
                }
                .padding(.horizontal, Spacing.s3_5)
                .frame(height: Size.iconButton + Spacing.s3)
                .background(Theme.muted, in: .capsule)
                .padding(.bottom, Spacing.s2)
                if model.tree.all.isEmpty {
                    empty("app:home.empty").padding(.top, Spacing.s12)
                } else if rows.isEmpty {
                    empty("app:home.noMatches").padding(.top, Spacing.s12)
                } else if sortField.wrappedValue == .edited {
                    ForEach(RecencyGroup.grouped(rows, by: \.updatedAt), id: \.group) { group in
                        Text(Self.heading(group.group))
                            .font(.hk(.md, .semibold))
                            .foregroundStyle(Theme.mutedForeground)
                            .padding(.top, Spacing.s4)
                            .padding(.bottom, Spacing.s1)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(group.items) { phoneRow($0, group: group.group) }
                    }
                } else {
                    ForEach(rows) { phoneRow($0, group: nil) }
                }
            }
            .padding(.horizontal, Spacing.s4)
            .padding(.bottom, Size.floatingBar + Spacing.s12)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Theme.background)
        .navigationTitle("")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) { sortMenu }
        }
        .overlay(alignment: .bottomTrailing) {
            Button {
                navigator.newPage()
            } label: {
                HStack(spacing: Spacing.s2) {
                    IconView(.plus, size: TextSize.lg.rawValue)
                    Text("app:page.new").font(.hk(.base, .semibold))
                }
                .foregroundStyle(ColorTone.standard.onFill)
                .padding(.horizontal, Spacing.s5)
                .frame(height: Size.floatingBar)
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(ColorTone.standard.fill).interactive(), in: .capsule)
            .padding(.trailing, Spacing.s4)
            .padding(.bottom, Spacing.s2)
            .accessibilityIdentifier("home-new-page")
        }
    }

    private func phoneRow(_ row: HomeRow, group: RecencyGroup?) -> some View {
        Button {
            navigator.open(row.id)
        } label: {
            HStack(spacing: Spacing.s3) {
                PageIcon(row.icon, size: TextSize.lg.rawValue)
                    .frame(width: Size.iconButton + Spacing.s1_5, height: Size.iconButton + Spacing.s1_5)
                    .background(Theme.muted, in: .rect(cornerRadius: Radius.lg))
                VStack(alignment: .leading, spacing: Spacing.px) {
                    Text(row.title).font(.hk(.base)).foregroundStyle(Theme.foreground).lineLimit(1)
                    if !row.location.isEmpty {
                        Text(row.location).font(.hk(.md)).foregroundStyle(Theme.mutedForeground).lineLimit(1)
                    }
                }
                Spacer(minLength: Spacing.s2)
                Text(Self.when(row.updatedAt, in: group))
                    .font(.hk(.md))
                    .monospacedDigit()
                    .foregroundStyle(Theme.placeholder)
            }
            .frame(minHeight: Size.row + Spacing.s6)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let page = model.tree.page(row.id) { PageActions(page: page, navigator: navigator) }
        }
        .accessibilityIdentifier("home-row-\(row.title)")
    }

    private static func heading(_ group: RecencyGroup) -> String {
        switch group {
        case .today: String(localized: "app:home.today")
        case .yesterday: String(localized: "app:home.yesterday")
        case .thisWeek: String(localized: "app:home.thisWeek")
        case .month(let month): Calendar.current.standaloneMonthSymbols[month - 1]
        case .year(let year): String(year)
        }
    }

    /// The edit time as its heading needs it: a time today and yesterday, a weekday within the week, else the date.
    private static func when(_ date: Date, in group: RecencyGroup?) -> String {
        switch group {
        case .today, .yesterday: date.formatted(date: .omitted, time: .shortened)
        case .thisWeek: date.formatted(.dateTime.weekday(.abbreviated))
        default: date.formatted(.dateTime.month(.abbreviated).day())
        }
    }
}

/// A page in Home's gallery: its icon large, the title, where it sits, when it was edited and how long it is.
private struct HomeCard: View {
    let row: HomeRow
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            PageIcon(row.icon, size: 28)
            Text(row.title).font(.hk(.base, .medium)).foregroundStyle(Theme.foreground).lineLimit(2)
            if !row.location.isEmpty {
                Text(row.location).font(.hk(.xs)).foregroundStyle(Theme.mutedForeground).lineLimit(1)
            }
            Spacer(minLength: Spacing.s0)
            HStack(spacing: Spacing.s1) {
                Text(row.updatedAt, format: .relative(presentation: .named))
                Text(verbatim: "·")
                Text("app:home.words \(row.words.formatted())")
                Spacer(minLength: Spacing.s0)
                if row.isFavorite { IconView(.star, size: TextSize.xs.rawValue) }
            }
            .font(.hk(.xs))
            .foregroundStyle(Theme.mutedForeground)
        }
        .padding(Spacing.s4)
        .frame(maxWidth: .infinity, minHeight: Size.homeCard * 0.55, alignment: .topLeading)
        .background(hovering ? Theme.accent : Theme.card, in: .rect(cornerRadius: Radius.xl))
        .overlay { RoundedRectangle(cornerRadius: Radius.xl).stroke(Theme.border, lineWidth: 1) }
        .contentShape(.rect(cornerRadius: Radius.xl))
        .onHover { hovering = $0 }
        .animation(Motion.easeOut(Motion.popOut), value: hovering)
    }
}
