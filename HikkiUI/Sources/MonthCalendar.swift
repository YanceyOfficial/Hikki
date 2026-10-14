import SwiftUI

/// A month grid in shadcn's calendar look: the month and ‹ › on top, the weekdays, then the days as rounded cells —
/// the selected day filled in the tone, today in bold tone ink, days outside the month faint, a dot under days that
/// are `marked`. It fills its width. Purely presentational: the caller holds the shown month and the selection.
public struct MonthCalendar: View {
    @Binding private var month: Date
    @Binding private var selection: Date
    private let marked: Set<DateComponents>
    private let calendar: Calendar
    @Environment(\.colorTone) private var colorTone

    public init(month: Binding<Date>, selection: Binding<Date>, marked: Set<DateComponents> = [], calendar: Calendar = .current) {
        _month = month
        _selection = selection
        self.marked = marked
        self.calendar = calendar
    }

    /// The key `marked` uses for a date: its year, month and day.
    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> DateComponents {
        calendar.dateComponents([.year, .month, .day], from: date)
    }

    public var body: some View {
        VStack(spacing: Spacing.s2) {
            HStack(spacing: Spacing.s1) {
                Text(month, format: .dateTime.year().month(.wide))
                    .font(.hk(.sm, .semibold))
                    .foregroundStyle(Theme.foreground)
                Spacer(minLength: Spacing.s2)
                step(-1, icon: .caretLeft, label: "app:calendar.previous")
                step(1, icon: .caretRight, label: "app:calendar.next")
            }
            .padding(.horizontal, Spacing.s1)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.s0_5), count: 7), spacing: Spacing.s0_5) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(verbatim: symbol)
                        .font(.hk(.xs))
                        .foregroundStyle(Theme.mutedForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, Spacing.s1)
                }
                ForEach(days, id: \.self) { day in
                    cell(day)
                }
            }
        }
    }

    private func step(_ delta: Int, icon: Icon, label: LocalizedStringKey) -> some View {
        Button {
            if let next = calendar.date(byAdding: .month, value: delta, to: month) { month = next }
        } label: {
            IconView(icon, size: TextSize.sm.rawValue)
                .foregroundStyle(Theme.subtleForeground)
                .frame(width: Size.iconButton, height: Size.iconButton)
                .contentShape(.rect)
        }
        .buttonStyle(HoverHighlightStyle(cornerRadius: Radius.md))
        .accessibilityLabel(label)
    }

    private func cell(_ day: Date) -> some View {
        let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)
        let isSelected = calendar.isDate(day, inSameDayAs: selection)
        let isToday = calendar.isDateInToday(day)
        let hasMark = marked.contains(Self.dayKey(day, calendar: calendar))
        return Button {
            selection = day
            if !inMonth { month = day }
        } label: {
            VStack(spacing: Spacing.px) {
                Text(day, format: .dateTime.day())
                    .font(.hk(.md, isToday || isSelected ? .semibold : .regular))
                    .foregroundStyle(
                        isSelected ? colorTone.onFill : isToday ? colorTone.ink : inMonth ? Theme.foreground : Theme.mutedForeground)
                Circle()
                    .fill(isSelected ? colorTone.onFill : colorTone.fill)
                    .frame(width: 4, height: 4)
                    .opacity(hasMark ? 1 : 0)
            }
            .frame(maxWidth: .infinity, minHeight: Size.iconButton + Spacing.s2)
            .background(isSelected ? colorTone.fill : .clear, in: .rect(cornerRadius: Radius.md))
            .contentShape(.rect)
        }
        .buttonStyle(HoverHighlightStyle(cornerRadius: Radius.md))
        .opacity(inMonth ? 1 : 0.5)
        .accessibilityLabel(Text(day, format: .dateTime.year().month().day()))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Short weekday names, starting on the calendar's first weekday.
    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// Six weeks covering the shown month, from the week its first day falls in.
    private var days: [Date] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
            let start = calendar.dateInterval(of: .weekOfMonth, for: interval.start)?.start
        else { return [] }
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
}

#Preview {
    @Previewable @State var month = Date.now
    @Previewable @State var selection = Date.now
    MonthCalendar(
        month: $month, selection: $selection,
        marked: [MonthCalendar.dayKey(.now), MonthCalendar.dayKey(.now.addingTimeInterval(-3 * 86_400))]
    )
    .padding()
    .frame(width: 340)
    .background(Theme.background)
}
