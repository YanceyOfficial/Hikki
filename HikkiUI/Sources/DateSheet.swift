import SwiftUI

/// A date chip as the phone's sheet edits it: the day, an optional time of day (only its hour and minute count), the
/// reminder (minutes before; nil: none) and whether it's marked done.
public struct DateSheetValue: Equatable, Sendable {
    public var day: Date
    public var time: Date?
    public var remind: Int?
    public var done: Bool

    public init(day: Date, time: Date? = nil, remind: Int? = nil, done: Bool = false) {
        self.day = day
        self.time = time
        self.remind = remind
        self.done = done
    }
}

/// The phone's sheet for a date chip (the editor's popover, natively): the calendar, Include time with its time, the
/// reminder, Mark done while there is one, and Remove date. Edits stay in the sheet until Done (or the sheet going
/// away, which the caller treats as Done); Remove hands back nothing.
public struct DateSheet: View {
    /// Reminder choices with a time of day, and on a whole day (at `dayTime`) — the editor's `REMIND_TIMED` / `REMIND_DAY`.
    public static let remindTimed = [0, 5, 60, 1440]
    public static let remindDay = [0, 1440, 10080]

    @State private var value: DateSheetValue
    /// When a whole day's reminder rings ("09:00"), shown in its choices.
    let dayTime: String
    let onChange: (DateSheetValue) -> Void
    let onDone: () -> Void
    let onRemove: () -> Void
    @Environment(\.colorTone) private var tone

    public init(
        value: DateSheetValue, dayTime: String, onChange: @escaping (DateSheetValue) -> Void, onDone: @escaping () -> Void,
        onRemove: @escaping () -> Void
    ) {
        _value = State(initialValue: value)
        self.dayTime = dayTime
        self.onChange = onChange
        self.onDone = onDone
        self.onRemove = onRemove
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s3) {
                HStack {
                    Text("app:date.title").font(.hk(.base, .semibold)).foregroundStyle(Theme.foreground)
                    Spacer(minLength: Spacing.s2)
                    Button("app:date.done", action: onDone)
                        .font(.hk(.base, .semibold))
                        .tint(tone.fill)
                        .accessibilityIdentifier("date-sheet-done")
                }
                DatePicker("app:date.title", selection: $value.day, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .tint(tone.fill)
                    .accessibilityIdentifier("date-sheet-calendar")
                VStack(spacing: Spacing.s0) {
                    timeRows
                    Divider().padding(.leading, Spacing.s4)
                    remindRow
                    if value.remind != nil {
                        Divider().padding(.leading, Spacing.s4)
                        doneRow
                    }
                }
                .glassEffect(.regular, in: .rect(cornerRadius: Radius.xl))
                Button(role: .destructive, action: onRemove) {
                    SheetRow(icon: .trash) { Text("app:date.remove").foregroundStyle(Theme.destructive) }
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Radius.xl))
                .accessibilityIdentifier("date-sheet-remove")
            }
            .padding(Spacing.s4)
        }
        .onChange(of: value) { _, next in onChange(next) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("date-sheet")
    }

    @ViewBuilder private var timeRows: some View {
        SheetRow(icon: .clock) {
            Toggle("app:date.includeTime", isOn: timed)
                .tint(tone.fill)
                .accessibilityIdentifier("date-sheet-include-time")
        }
        if let time = value.time {
            SheetRow(icon: nil) {
                DatePicker(
                    "app:date.time", selection: Binding(get: { time }, set: { value.time = $0 }),
                    displayedComponents: .hourAndMinute
                )
                .tint(tone.fill)
                .accessibilityIdentifier("date-sheet-time")
            }
        }
    }

    private var remindRow: some View {
        SheetRow(icon: .bellSimple) {
            HStack(spacing: Spacing.s2) {
                Text("app:date.remind").foregroundStyle(Theme.foreground)
                Spacer(minLength: Spacing.s2)
                remindPicker
            }
        }
    }

    private var remindPicker: some View {
        Picker("app:date.remind", selection: $value.remind) {
            Text(Self.remindLabel(nil, timed: value.time != nil, dayTime: dayTime)).tag(Int?.none)
            ForEach(value.time == nil ? Self.remindDay : Self.remindTimed, id: \.self) { minutes in
                Text(Self.remindLabel(minutes, timed: value.time != nil, dayTime: dayTime)).tag(Int?.some(minutes))
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .tint(Theme.mutedForeground)
        .accessibilityIdentifier("date-sheet-remind")
    }

    private var doneRow: some View {
        Button {
            value.done.toggle()
        } label: {
            SheetRow(icon: .checkCircleFill) {
                Text(value.done ? "app:date.markNotDone" : "app:date.markDone").foregroundStyle(Theme.foreground)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("date-sheet-mark-done")
    }

    /// Include time on: at `dayTime` on the day; off: the whole day. A reminder keeps meaning "at the time".
    private var timed: Binding<Bool> {
        Binding(
            get: { value.time != nil },
            set: { on in
                value.time = on ? Self.time(dayTime, on: value.day) : nil
                if value.remind != nil { value.remind = 0 }
            })
    }

    /// "HH:mm" on `day`, in the current calendar.
    static func time(_ text: String, on day: Date) -> Date {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        let calendar = Calendar.current
        return calendar.date(
            bySettingHour: parts.first ?? 9, minute: parts.count > 1 ? parts[1] : 0, second: 0, of: day) ?? day
    }

    /// A reminder choice in words — the editor's `remindLabel`.
    public static func remindLabel(_ minutes: Int?, timed: Bool, dayTime: String) -> LocalizedStringKey {
        guard let minutes else { return "app:date.remind.none" }
        if !timed {
            switch minutes {
            case 0: return "app:date.remind.onDay \(dayTime)"
            case 1440: return "app:date.remind.dayBefore \(dayTime)"
            case 10080: return "app:date.remind.weekBefore \(dayTime)"
            default: break
            }
        }
        switch minutes {
        case 0: return "app:date.remind.atTime"
        case 5: return "app:date.remind.minutes5"
        case 60: return "app:date.remind.hour1"
        case 1440: return "app:date.remind.day1"
        default: return "app:date.remind.minutes \(String(minutes))"
        }
    }
}

/// One row of the sheet's group: an icon (or its room), then the control.
private struct SheetRow<Content: View>: View {
    let icon: Icon?
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: Spacing.s3) {
            Group {
                if let icon { IconView(icon, size: TextSize.lg.rawValue) } else { Color.clear }
            }
            .foregroundStyle(Theme.mutedForeground)
            .frame(width: Spacing.s6)
            content.font(.hk(.base)).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s2_5)
        .contentShape(.rect)
    }
}

#Preview {
    DateSheet(
        value: DateSheetValue(day: .now, time: .now, remind: 60), dayTime: "09:00", onChange: { _ in }, onDone: {},
        onRemove: {})
}

#Preview("Whole day") {
    DateSheet(value: DateSheetValue(day: .now), dayTime: "09:00", onChange: { _ in }, onDone: {}, onRemove: {})
}
