import HikkiCore
import HikkiUI
import SwiftUI

/// How Home shows the workspace's pages.
enum HomeLayout: String, CaseIterable, Identifiable {
    case table, gallery, calendar

    static let storageKey = "home.layout"

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .table: "app:home.layout.table"
        case .gallery: "app:home.layout.gallery"
        case .calendar: "app:home.layout.calendar"
        }
    }

    var icon: Icon {
        switch self {
        case .table: .listBullets
        case .gallery: .browsers
        case .calendar: .calendarDots
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
    /// The stored cover (`PageCover`), for the gallery's cards.
    let cover: String?
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
/// a gallery of cards (with their covers) or a month calendar of what was edited each day — with a filter and New
/// Page on top. iPhone gets the same as a list.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    let navigator: Navigator
    @AppStorage(HomeLayout.storageKey) private var layout = HomeLayout.table
    @State private var filter = ""
    @State private var sortOrder = [HomeSort(field: .edited, order: .reverse)]
    @State private var selection: Set<HomeRow.ID> = []
    /// The rows as shown: built (a path per page) and sorted when the pages, the filter or the order change — not on
    /// every redraw.
    @State private var rows: [HomeRow] = []
    /// Too narrow for the table's columns (a side of a split view): pages as the phone's list instead.
    @State private var narrow = false
    /// The calendar's month, and the day picked in it (nil: `HomeCalendar.defaultDay`).
    @State private var month = CalendarMonth(containing: .now, calendar: HomeCalendar.calendar())
    @State private var pickedDay: Date?
    /// The shown rows under the day they were edited, for the calendar (built with the rows, only while it shows).
    @State private var rowsByDay: [Date: [HomeRow]] = [:]
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
        screen.syncRefreshable().screenTitle(String(localized: "app:nav.home"))
    }

    @ViewBuilder private var screen: some View {
        Group {
            if compact {
                phone(rows)
            } else {
                wide(rows)
            }
        }
        .onChange(of: model.tree, initial: true) { rebuildRows() }
        .onChange(of: filter) { rebuildRows() }
        .onChange(of: sortOrder) { rebuildRows() }
        .onChange(of: layout) { rebuildRows() }
        .onChange(of: compact) { rebuildRows() }
    }

    private func wide(_ rows: [HomeRow]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s0) {
            header(count: rows.count)
                .padding(.horizontal, Spacing.s6)
                .padding(.top, Spacing.s6)
                .padding(.bottom, Spacing.s3)
            if !model.tree.all.isEmpty {
                UpcomingSection(navigator: navigator) {
                    Text("app:home.upcoming")
                        .font(.hk(.sm, .semibold))
                        .foregroundStyle(Theme.mutedForeground)
                        .padding(.horizontal, Spacing.s3)
                        .accessibilityAddTraits(.isHeader)
                }
                .padding(.horizontal, Spacing.s3)
                .padding(.bottom, Spacing.s3)
            }
            if model.tree.all.isEmpty {
                empty("app:home.empty")
            } else if rows.isEmpty {
                empty("app:home.noMatches")
            } else {
                switch layout {
                case .table where narrow:
                    ScrollView {
                        pageList(rows).padding(.horizontal, Spacing.s6).padding(.bottom, Spacing.s6)
                    }
                case .table: table(rows)
                case .gallery: gallery(rows)
                case .calendar: calendarView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onGeometryChange(for: Bool.self) {
            $0.size.width < Size.homeNarrow
        } action: {
            narrow = $0
        }
        // One surface with the table under the title (Music's): the table's own background, not the page's darker one.
        .background(Theme.listSurface)
        // The Mac's toolbar names it; iOS has no bar over it (its heading is in the view).
        .navigationTitle(Navigator.usesTabs ? String(localized: "app:nav.home") : "")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: Rows

    private func rebuildRows() {
        let query = filter.trimmingCharacters(in: .whitespaces)
        let untitled = String(localized: "app:page.untitled")
        rows = model.tree.all
            .map { page in
                HomeRow(
                    id: page.id, title: page.title.isEmpty ? untitled : page.title, icon: page.icon,
                    location: model.tree.path(to: page.id).dropLast()
                        .map { $0.title.isEmpty ? untitled : $0.title }
                        .joined(separator: " › "),
                    createdAt: page.createdAt, updatedAt: page.updatedAt, words: page.wordCount,
                    isFavorite: page.isFavorite, cover: page.cover)
            }
            .filter { query.isEmpty || $0.title.localizedStandardContains(query) || $0.location.localizedStandardContains(query) }
            .sorted(using: sortOrder)
        rowsByDay =
            layout == .calendar && !compact ? HomeCalendar.byDay(rows, date: \.updatedAt, calendar: HomeCalendar.calendar()) : [:]
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
                if !narrow { filterField.frame(width: Size.homeFilter) }
                // The calendar orders by day itself.
                if compact || (layout != .calendar && (narrow || layout == .gallery)) {
                    sortMenu
                }
                Button {
                    navigator.newPage()
                } label: {
                    IconLabel("app:page.new", icon: .notePencil)
                        .labelStyle(NarrowLabelStyle(iconOnly: narrow))
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("home-new-page")
            }
            // A narrow side: the filter on a line of its own, the full width.
            if narrow { filterField }
        }
    }

    private var filterField: some View {
        HStack(spacing: Spacing.s1_5) {
            IconView(.magnifyingGlass, size: TextSize.sm.rawValue).foregroundStyle(Theme.mutedForeground)
            TextField("app:home.filter", text: $filter)
                .textFieldStyle(.plain)
                .font(.hk(.md))
                .accessibilityIdentifier("home-filter")
        }
        .padding(.horizontal, Spacing.s2_5)
        .frame(height: Size.searchField)
        .background(Theme.muted, in: .rect(cornerRadius: Radius.md))
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
                .labelStyle(NarrowLabelStyle(iconOnly: narrow))
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
                        HomeCard(row: row, cover: coverArt(row.cover))
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

    /// A card's cover as HikkiUI draws it: a built-in gradient, a picture in the workspace's assets (as a file) or a
    /// web address; nil for none, or one this device can't show (a missing asset, an unknown gradient).
    private func coverArt(_ raw: String?) -> PageCoverView.Art? {
        guard let cover = PageCover(raw) else { return nil }
        switch cover {
        case .gradient(let id):
            return CoverGradient(rawValue: id).map { PageCoverView.Art.gradient($0) }
        case .image(_, let position):
            if let name = cover.assetName {
                return model.assets.file(named: name).map { PageCoverView.Art.image($0, position: position) }
            }
            return cover.webURL.map { PageCoverView.Art.image($0, position: position) }
        }
    }

    // MARK: Calendar

    /// A month of what was edited each day (Mac and iPad), the picked day's pages beside it — under it on a narrow
    /// side. A click on a day picks it; a click on a page opens it, as the gallery's cards do.
    @ViewBuilder private func calendarView() -> some View {
        let calendar = HomeCalendar.calendar()
        let today = calendar.startOfDay(for: .now)
        let selected = selectedDay(calendar: calendar, today: today)
        let grid = MonthCalendar(
            title: month.firstDay(in: calendar).formatted(.dateTime.year().month(.wide)),
            summary: String(
                localized: "app:calendar.edited \(HomeCalendar.count(in: month, of: rowsByDay, calendar: calendar).formatted())"),
            weekdays: HomeCalendar.weekdaySymbols(calendar.shortStandaloneWeekdaySymbols, firstWeekday: calendar.firstWeekday),
            weeks: HomeCalendar.weeks(of: month, calendar: calendar).map { week in
                week.map { calendarDay($0, calendar: calendar, today: today) }
            },
            selection: selected,
            onSelect: { day in pickedDay = day },
            onMove: { step in
                month = month.adding(step)
                pickedDay = nil
            },
            onToday: {
                month = CalendarMonth(containing: today, calendar: calendar)
                pickedDay = today
            })
        let list = CalendarDayList(
            title: selected.formatted(.dateTime.weekday(.wide).month(.wide).day()), rows: dayPages(selected),
            onOpen: { id in navigator.openFromSidebar(.page(id)) }
        ) { id in
            if let page = model.tree.page(id) { PageActions(page: page, navigator: navigator) }
        }
        if narrow {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s4) {
                    grid
                    list
                }
                .padding(.horizontal, Spacing.s6)
                .padding(.bottom, Spacing.s6)
            }
        } else {
            HStack(alignment: .top, spacing: Spacing.s0) {
                ScrollView {
                    grid.padding(.leading, Spacing.s6).padding(.trailing, Spacing.s4).padding(.bottom, Spacing.s6)
                }
                Divider()
                ScrollView {
                    list.padding(Spacing.s3)
                }
                .frame(width: Size.homeCalendarPanel)
            }
        }
    }

    /// The picked day while it is in the shown month, else the month's default (today, or its last day with pages).
    private func selectedDay(calendar: Calendar, today: Date) -> Date {
        if let pickedDay, month.contains(pickedDay, in: calendar) { return pickedDay }
        return HomeCalendar.defaultDay(in: month, days: rowsByDay, today: today, calendar: calendar)
    }

    private func calendarDay(_ day: Date, calendar: Calendar, today: Date) -> MonthCalendar.Day {
        let pages = rowsByDay[day] ?? []
        return MonthCalendar.Day(
            id: day, number: calendar.component(.day, from: day), inMonth: month.contains(day, in: calendar),
            isToday: day == today,
            pages: pages.prefix(MonthCalendar.pagesPerDay).map { MonthCalendar.Page(id: $0.id, title: $0.title, icon: $0.icon) },
            total: pages.count, label: day.formatted(date: .complete, time: .omitted))
    }

    private func dayPages(_ day: Date) -> [CalendarDayPage] {
        (rowsByDay[day] ?? []).map { row in
            CalendarDayPage(
                id: row.id, title: row.title, icon: row.icon, location: row.location,
                words: String(localized: "app:home.words \(row.words.formatted())"),
                time: row.updatedAt.formatted(date: .omitted, time: .shortened))
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
                } else {
                    pageList(rows)
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

    /// The pages as plain rows, under day headings when ordered by edit time (the phone's Home, a narrow side).
    @ViewBuilder private func pageList(_ rows: [HomeRow]) -> some View {
        LazyVStack(alignment: .leading, spacing: Spacing.s0) {
            if sortField.wrappedValue == .edited {
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

/// A page in Home's gallery: its cover as a band when it has one, its icon large, the title, where it sits, when it
/// was edited and how long it is.
private struct HomeCard: View {
    let row: HomeRow
    let cover: PageCoverView.Art?
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s0) {
            if let cover {
                PageCoverView(cover).frame(height: Size.homeCardCover)
            }
            details
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(hovering ? Theme.accent : Theme.card)
        .clipShape(.rect(cornerRadius: Radius.xl))
        .overlay { RoundedRectangle(cornerRadius: Radius.xl).stroke(Theme.border, lineWidth: 1) }
        .contentShape(.rect(cornerRadius: Radius.xl))
        .onHover { hovering = $0 }
        .animation(Motion.easeOut(Motion.popOut), value: hovering)
    }

    private var details: some View {
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
    }
}

/// The title beside its icon, or the icon alone where room is short.
private struct NarrowLabelStyle: LabelStyle {
    let iconOnly: Bool

    func makeBody(configuration: Configuration) -> some View {
        if iconOnly {
            configuration.icon
        } else {
            Label(configuration)
        }
    }
}
