import SwiftUI

/// Home's Upcoming: reminders that have rung and aren't done, then the dates of the week ahead — each row the date's
/// line ("Book the ryokan"), when ("Tomorrow 9:00 AM") and its page; a tap opens the page at the date. The first
/// `limit` rows show, the rest behind Show all.
public struct UpcomingList: View {
    public enum Kind: Sendable, Equatable {
        case date, reminder, overdue, done
    }

    public struct Row: Identifiable, Sendable, Equatable {
        public let id: String
        public let text: String
        public let when: String
        public let page: String
        public let kind: Kind

        public init(id: String, text: String, when: String, page: String, kind: Kind) {
            self.id = id
            self.text = text
            self.when = when
            self.page = page
            self.kind = kind
        }
    }

    let rows: [Row]
    let limit: Int
    let onOpen: (Row.ID) -> Void
    @State private var expanded = false

    public init(rows: [Row], limit: Int = 5, onOpen: @escaping (Row.ID) -> Void) {
        self.rows = rows
        self.limit = limit
        self.onOpen = onOpen
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s0) {
            ForEach(expanded ? rows : Array(rows.prefix(limit))) { row in
                UpcomingRow(row: row) { onOpen(row.id) }
            }
            if rows.count > limit {
                Button {
                    withAnimation(Motion.easeOut()) { expanded.toggle() }
                } label: {
                    Text(expanded ? "app:upcoming.showLess" : "app:upcoming.showAll \(String(rows.count))")
                        .font(.hk(.sm, .medium))
                        .foregroundStyle(Theme.mutedForeground)
                        .padding(.horizontal, Spacing.s3)
                        .padding(.vertical, Spacing.s2)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("upcoming-more")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("upcoming")
    }
}

/// One date: its icon (red once a reminder has rung), the line's words, then when and where.
private struct UpcomingRow: View {
    let row: UpcomingList.Row
    let onOpen: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s3) {
                IconView(icon, size: TextSize.base.rawValue)
                    .foregroundStyle(row.kind == .overdue ? Theme.destructive : Theme.mutedForeground)
                    .frame(width: Spacing.s5)
                VStack(alignment: .leading, spacing: Spacing.s0_5) {
                    Text(verbatim: row.text)
                        .font(.hk(.base))
                        .foregroundStyle(row.kind == .done ? Theme.mutedForeground : Theme.foreground)
                        .strikethrough(row.kind == .done)
                        .lineLimit(1)
                    HStack(spacing: Spacing.s1) {
                        Text(verbatim: row.when)
                            .foregroundStyle(row.kind == .overdue ? Theme.destructive : Theme.mutedForeground)
                        Text(verbatim: "·").foregroundStyle(Theme.subtleForeground)
                        Text(verbatim: row.page).foregroundStyle(Theme.mutedForeground).lineLimit(1)
                    }
                    .font(.hk(.sm))
                }
                Spacer(minLength: Spacing.s0)
            }
            .padding(.horizontal, Spacing.s3)
            .padding(.vertical, Spacing.s2)
            .background(hovered ? Theme.accent : .clear, in: .rect(cornerRadius: Radius.md))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { over in withAnimation(Motion.easeOut()) { hovered = over } }
        .accessibilityIdentifier("upcoming-row")
    }

    private var icon: Icon {
        switch row.kind {
        case .date: .calendarDots
        case .reminder, .overdue: .bellSimple
        case .done: .checkCircleFill
        }
    }
}

#Preview {
    UpcomingList(
        rows: [
            .init(id: "1", text: "Send the invoice", when: "Yesterday 5:00 PM", page: "Work", kind: .overdue),
            .init(id: "2", text: "Book the ryokan", when: "Tomorrow", page: "Trip to Kyoto", kind: .reminder),
            .init(id: "3", text: "Dentist", when: "Friday 9:30 AM", page: "Errands", kind: .date),
            .init(id: "4", text: "Renew passport", when: "Oct 30", page: "Errands", kind: .done),
        ], limit: 3
    ) { _ in }
    .padding()
}
