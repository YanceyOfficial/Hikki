import SwiftUI

/// Home's Calendar view (Mac and iPad): a month of what was written each day. The month's name and how many pages
/// were edited in it, ‹ Today › to move, a row of weekday names, then a cell per day — its number (today in the
/// tone's circle) and up to two of the pages edited that day, then "+N more". Days outside the month are dimmed; a
/// cell is a button that selects its day. Plain cells: no shading by how much was written.
public struct MonthCalendar: View {
    /// A page as a day's cell lists it.
    public struct Page: Identifiable, Hashable, Sendable {
        public let id: String
        public let title: String
        public let icon: String?

        public init(id: String, title: String, icon: String?) {
            self.id = id
            self.title = title
            self.icon = icon
        }
    }

    public struct Day: Identifiable, Hashable, Sendable {
        /// The day's start.
        public let id: Date
        public let number: Int
        public let inMonth: Bool
        public let isToday: Bool
        /// The pages to show in the cell (the first two are), newest first.
        public let pages: [Page]
        /// How many pages were edited that day in all.
        public let total: Int
        /// The day spelled out for VoiceOver ("Saturday, October 24").
        public let label: String

        public init(id: Date, number: Int, inMonth: Bool, isToday: Bool, pages: [Page], total: Int, label: String) {
            self.id = id
            self.number = number
            self.inMonth = inMonth
            self.isToday = isToday
            self.pages = pages
            self.total = total
            self.label = label
        }
    }

    /// Pages a cell names before "+N more".
    public static let pagesPerDay = 2

    let title: String
    let summary: String
    let weekdays: [String]
    let weeks: [[Day]]
    let selection: Date?
    let onSelect: (Date) -> Void
    let onMove: (Int) -> Void
    let onToday: () -> Void

    /// - Parameters:
    ///   - title: the month ("October 2026").
    ///   - summary: how much was written in it ("12 pages edited").
    ///   - weekdays: the weekday names in the order the weeks run.
    ///   - onMove: −1 for the month before, +1 for the month after.
    public init(
        title: String, summary: String, weekdays: [String], weeks: [[Day]], selection: Date?,
        onSelect: @escaping (Date) -> Void, onMove: @escaping (Int) -> Void, onToday: @escaping () -> Void
    ) {
        self.title = title
        self.summary = summary
        self.weekdays = weekdays
        self.weeks = weeks
        self.selection = selection
        self.onSelect = onSelect
        self.onMove = onMove
        self.onToday = onToday
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            header
            // Seven equal columns, whatever the titles in them.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.s1), count: 7), spacing: Spacing.s1) {
                ForEach(Array(weekdays.enumerated()), id: \.offset) { _, name in
                    Text(verbatim: name)
                        .font(.hk(.xs, .medium))
                        .foregroundStyle(Theme.mutedForeground)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Spacing.s2)
                }
                ForEach(weeks.flatMap { $0 }) { day in
                    MonthCalendarCell(day: day, isSelected: selection == day.id) { onSelect(day.id) }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("month-calendar")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s2) {
            Text(verbatim: title).font(.hk(.lg, .semibold)).foregroundStyle(Theme.foreground)
            Text(verbatim: summary).font(.hk(.md)).foregroundStyle(Theme.mutedForeground)
            Spacer(minLength: Spacing.s2)
            HStack(spacing: Spacing.s1) {
                Button {
                    onMove(-1)
                } label: {
                    IconView(.caretLeft, size: TextSize.sm.rawValue)
                }
                .accessibilityLabel(Text("app:calendar.previous"))
                .help(Text("app:calendar.previous"))
                .accessibilityIdentifier("calendar-previous")
                Button(action: onToday) {
                    Text("app:calendar.today").font(.hk(.md))
                }
                .accessibilityIdentifier("calendar-today")
                Button {
                    onMove(1)
                } label: {
                    IconView(.caretRight, size: TextSize.sm.rawValue)
                }
                .accessibilityLabel(Text("app:calendar.next"))
                .help(Text("app:calendar.next"))
                .accessibilityIdentifier("calendar-next")
            }
            .buttonStyle(.bordered)
        }
    }
}

/// One day: its number, then the pages edited on it.
private struct MonthCalendarCell: View {
    let day: MonthCalendar.Day
    let isSelected: Bool
    let onSelect: () -> Void
    @Environment(\.colorTone) private var tone
    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: Spacing.s1) {
                number
                ForEach(day.pages.prefix(MonthCalendar.pagesPerDay)) { page in
                    HStack(spacing: Spacing.s1) {
                        PageIcon(page.icon, size: TextSize.xs.rawValue)
                        Text(verbatim: page.title)
                            .font(.hk(.xs))
                            .foregroundStyle(Theme.foreground)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                if day.total > MonthCalendar.pagesPerDay {
                    Text("app:calendar.more \(String(day.total - MonthCalendar.pagesPerDay))")
                        .font(.hk(.x2s, .medium))
                        .foregroundStyle(Theme.mutedForeground)
                        .padding(.leading, Spacing.s1)
                }
                Spacer(minLength: Spacing.s0)
            }
            .padding(Spacing.s1_5)
            .frame(maxWidth: .infinity, minHeight: Size.homeCalendarCell, alignment: .topLeading)
            .opacity(day.inMonth ? 1 : 0.4)
            .background(background, in: .rect(cornerRadius: Radius.md))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.md)
                    .strokeBorder(isSelected ? tone.fill : Theme.border, lineWidth: isSelected ? Spacing.s0_5 : Spacing.px)
            }
            .contentShape(.rect(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
        .onHover { over in withAnimation(Motion.easeOut()) { hovering = over } }
        .accessibilityLabel(Text(verbatim: day.label))
        .accessibilityValue(day.total > 0 ? Text("app:calendar.pages \(String(day.total))") : Text(verbatim: ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("calendar-day-\(day.number)\(day.inMonth ? "" : "-other")")
    }

    private var background: Color {
        if isSelected || hovering { return Theme.accent }
        return day.inMonth ? Theme.card : .clear
    }

    @ViewBuilder private var number: some View {
        let text = Text(day.number, format: .number).font(.hk(.xs, day.isToday ? .semibold : .medium)).monospacedDigit()
        if day.isToday {
            text
                .foregroundStyle(tone.onFill)
                .frame(width: Spacing.s5, height: Spacing.s5)
                .background(tone.fill, in: .circle)
        } else {
            text
                .foregroundStyle(day.inMonth ? Theme.foreground : Theme.mutedForeground)
                .frame(minWidth: Spacing.s5, minHeight: Spacing.s5, alignment: .leading)
                .padding(.leading, Spacing.s1)
        }
    }
}

/// A page in `CalendarDayList`.
public struct CalendarDayPage: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let icon: String?
    public let location: String
    /// "1,204 words".
    public let words: String
    /// When it was edited ("3:41 PM").
    public let time: String

    public init(id: String, title: String, icon: String?, location: String, words: String, time: String) {
        self.id = id
        self.title = title
        self.icon = icon
        self.location = location
        self.words = words
        self.time = time
    }
}

/// The day picked in Home's calendar: its date as a heading and the pages edited on it — icon, title, where it sits
/// and how long it is; a click opens one. `menu` gives a row its context menu (the app's page actions).
public struct CalendarDayList<RowMenu: View>: View {
    public typealias Row = CalendarDayPage

    let title: String
    let rows: [Row]
    let onOpen: (Row.ID) -> Void
    let menu: (Row.ID) -> RowMenu

    public init(
        title: String, rows: [Row], onOpen: @escaping (Row.ID) -> Void, @ViewBuilder menu: @escaping (Row.ID) -> RowMenu
    ) {
        self.title = title
        self.rows = rows
        self.onOpen = onOpen
        self.menu = menu
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            Text(verbatim: title)
                .font(.hk(.sm, .semibold))
                .foregroundStyle(Theme.foreground)
                .padding(.horizontal, Spacing.s2)
                .padding(.bottom, Spacing.s1)
                .accessibilityAddTraits(.isHeader)
            if rows.isEmpty {
                Text("app:calendar.nothing")
                    .font(.hk(.md))
                    .foregroundStyle(Theme.mutedForeground)
                    .padding(.horizontal, Spacing.s2)
            } else {
                ForEach(rows) { row in
                    CalendarDayRow(row: row) { onOpen(row.id) }
                        .contextMenu { menu(row.id) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calendar-day-list")
    }
}

extension CalendarDayList where RowMenu == EmptyView {
    public init(title: String, rows: [Row], onOpen: @escaping (Row.ID) -> Void) {
        self.init(title: title, rows: rows, onOpen: onOpen) { _ in EmptyView() }
    }
}

private struct CalendarDayRow: View {
    let row: CalendarDayPage
    let onOpen: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: Spacing.s2) {
                PageIcon(row.icon, size: TextSize.base.rawValue)
                VStack(alignment: .leading, spacing: Spacing.s0_5) {
                    Text(verbatim: row.title).font(.hk(.sm, .medium)).foregroundStyle(Theme.foreground).lineLimit(1)
                    if !row.location.isEmpty {
                        Text(verbatim: row.location).font(.hk(.xs)).foregroundStyle(Theme.mutedForeground).lineLimit(1)
                    }
                    HStack(spacing: Spacing.s1) {
                        Text(verbatim: row.time)
                        Text(verbatim: "·")
                        Text(verbatim: row.words)
                    }
                    .font(.hk(.xs))
                    .monospacedDigit()
                    .foregroundStyle(Theme.subtleForeground)
                }
                Spacer(minLength: Spacing.s0)
            }
            .padding(.horizontal, Spacing.s2)
            .padding(.vertical, Spacing.s1_5)
            .background(hovering ? Theme.accent : .clear, in: .rect(cornerRadius: Radius.md))
            .contentShape(.rect(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
        .onHover { over in withAnimation(Motion.easeOut()) { hovering = over } }
        .accessibilityIdentifier("calendar-page-\(row.title)")
    }
}

#Preview {
    let calendar = Calendar(identifier: .gregorian)
    let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28)) ?? .now
    let pages = [
        MonthCalendar.Page(id: "a", title: "Trip to Kyoto", icon: "🗺️"),
        MonthCalendar.Page(id: "b", title: "Reading notes", icon: nil),
        MonthCalendar.Page(id: "c", title: "Weekly plan", icon: "📅"),
    ]
    let weeks = (0..<5).map { week in
        (0..<7).map { weekday -> MonthCalendar.Day in
            let offset = week * 7 + weekday
            let date = calendar.date(byAdding: .day, value: offset, to: start) ?? start
            let count = [0, 1, 3, 0, 2][offset % 5]
            return MonthCalendar.Day(
                id: date, number: calendar.component(.day, from: date), inMonth: (3..<34).contains(offset),
                isToday: offset == 29, pages: Array(pages.prefix(count)), total: count == 3 ? 5 : count, label: "\(offset)")
        }
    }
    return HStack(alignment: .top, spacing: Spacing.s4) {
        MonthCalendar(
            title: "October 2026", summary: "23 pages edited", weekdays: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"],
            weeks: weeks, selection: weeks[4][1].id, onSelect: { _ in }, onMove: { _ in }, onToday: {})
        CalendarDayList(
            title: "Saturday, October 24",
            rows: [
                .init(id: "a", title: "Trip to Kyoto", icon: "🗺️", location: "Travel", words: "1,204 words", time: "3:41 PM"),
                .init(id: "b", title: "Reading notes", icon: nil, location: "", words: "312 words", time: "9:02 AM"),
            ], onOpen: { _ in }
        )
        .frame(width: Size.homeCalendarPanel)
    }
    .padding()
    .frame(width: 1100)
}
