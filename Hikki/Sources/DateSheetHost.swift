#if os(iOS)
    import HikkiCore
    import HikkiUI
    import SwiftUI

    /// The iPhone's sheet for a date chip (HikkiUI's `DateSheet`, `dateSheet`): its edits go back to the page as its own
    /// once, when it closes (Done or a swipe down) — Remove date takes the chip out.
    struct DateSheetHost: View {
        let request: EditorController.DateRequest
        let editor: EditorController
        @Environment(\.dismiss) private var dismiss
        /// The chip as edited meanwhile; nil until something changed.
        @State private var edited: DateMention?
        @State private var answered = false

        var body: some View {
            DateSheet(
                value: Self.value(of: request.mention),
                dayTime: DateMention.dayTime,
                onChange: { edited = Self.mention($0, from: request.mention) },
                onDone: { dismiss() },
                onRemove: {
                    answer(remove: true)
                    dismiss()
                }
            )
            .onDisappear { answer(remove: false) }
        }

        /// The one answer an opening gets: the edit (nothing when unchanged), or the removal.
        private func answer(remove: Bool) {
            guard !answered else { return }
            answered = true
            if !remove, edited == nil || edited == request.mention { return }
            let id = request.id
            let change = remove ? nil : edited
            Task { await editor.applyDate(change, id: id) }
        }

        static func value(of mention: DateMention) -> DateSheetValue {
            let calendar = Calendar.current
            let day = mention.day(in: calendar) ?? .now
            return DateSheetValue(day: day, time: mention.time == nil ? nil : day, remind: mention.remind, done: mention.done)
        }

        static func mention(_ value: DateSheetValue, from mention: DateMention) -> DateMention {
            let calendar = Calendar.current
            let d = calendar.dateComponents([.year, .month, .day], from: value.day)
            var next = mention
            next.date = String(format: "%04d-%02d-%02d", d.year ?? 0, d.month ?? 0, d.day ?? 0)
            next.time = value.time.map { time in
                let t = calendar.dateComponents([.hour, .minute], from: time)
                return String(format: "%02d:%02d", t.hour ?? 0, t.minute ?? 0)
            }
            next.remind = value.remind
            next.done = value.done
            return next
        }
    }
#endif
