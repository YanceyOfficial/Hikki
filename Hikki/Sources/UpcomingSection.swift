import HikkiCore
import HikkiUI
import SwiftUI

/// Home's Upcoming (HikkiUI's `UpcomingList` over `Upcoming.items`): redrawn every minute, so a reminder turns red
/// when it rings; nothing when there's nothing coming. A row opens its page at the date's block.
struct UpcomingSection<Header: View>: View {
    @Environment(AppModel.self) private var model
    let navigator: Navigator
    @ViewBuilder let header: Header

    var body: some View {
        TimelineView(.everyMinute) { context in
            let items = Upcoming.items(model.reminders.entries, now: context.date, calendar: .current)
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    header
                    UpcomingList(rows: items.map { Self.row($0, now: context.date) }) { id in
                        guard let entry = items.first(where: { $0.id == id }) else { return }
                        navigator.open(entry.pageId, at: entry.found.blockId.isEmpty ? nil : entry.found.blockId, revealing: [])
                    }
                }
            }
        }
    }

    static func row(_ entry: DateEntry, now: Date) -> UpcomingList.Row {
        let calendar = Calendar.current
        let mention = entry.mention
        let page = entry.pageTitle.isEmpty ? String(localized: "app:page.untitled") : entry.pageTitle
        let kind: UpcomingList.Kind =
            if mention.remind == nil { .date } else if mention.done { .done } else if mention.isOverdue(now: now, calendar: calendar) {
                .overdue
            } else { .reminder }
        return UpcomingList.Row(
            id: entry.id, text: entry.found.text.isEmpty ? page : entry.found.text, when: when(mention, now: now),
            page: page, kind: kind)
    }

    /// "Today", "Tomorrow 9:00 AM", "Friday", "Oct 30", "Jan 2, 2027" — the editor's chip label.
    static func when(_ mention: DateMention, now: Date) -> String {
        let calendar = Calendar.current
        let day: String =
            switch Upcoming.day(of: mention, now: now, calendar: calendar) {
            case .today: String(localized: "app:date.today")
            case .tomorrow: String(localized: "app:date.tomorrow")
            case .yesterday: String(localized: "app:date.yesterday")
            case .weekday(let date): date.formatted(.dateTime.weekday(.wide))
            case .date(let date, let withYear):
                withYear ? date.formatted(.dateTime.month(.abbreviated).day().year()) : date.formatted(.dateTime.month(.abbreviated).day())
            case nil: mention.date
            }
        guard mention.time != nil, let at = mention.day(in: calendar) else { return day }
        return "\(day) \(at.formatted(date: .omitted, time: .shortened))"
    }
}
