import SwiftUI

/// A week of writing at a glance (iPhone Home): the headline figure, a bar per day (today tinted), and a line of totals.
public struct WeekActivityCard: View {
    public struct Day: Identifiable, Sendable {
        public let id: Int
        /// The weekday's letter ("M", "一").
        public let label: String
        public let value: Int
        public let isToday: Bool

        public init(id: Int, label: String, value: Int, isToday: Bool) {
            self.id = id
            self.label = label
            self.value = value
            self.isToday = isToday
        }
    }

    let title: LocalizedStringKey
    let headline: String
    let caption: String
    let days: [Day]
    let footnote: String
    @Environment(\.colorTone) private var tone

    public init(title: LocalizedStringKey, headline: String, caption: String, days: [Day], footnote: String) {
        self.title = title
        self.headline = headline
        self.caption = caption
        self.days = days
        self.footnote = footnote
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            Text(title).font(.hk(.xs, .medium)).foregroundStyle(Theme.mutedForeground)
            HStack(alignment: .bottom, spacing: Spacing.s4) {
                VStack(alignment: .leading, spacing: Spacing.s0_5) {
                    Text(verbatim: headline)
                        .font(.hk(.x3l, .bold).monospacedDigit())
                        .foregroundStyle(Theme.foreground)
                    Text(verbatim: caption).font(.hk(.xs)).foregroundStyle(Theme.mutedForeground)
                }
                Spacer(minLength: Spacing.s2)
                bars
            }
            Text(verbatim: footnote).font(.hk(.xs)).foregroundStyle(Theme.subtleForeground)
        }
        .padding(Spacing.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.muted, in: .rect(cornerRadius: Radius.xl))
        .accessibilityElement(children: .combine)
    }

    private var bars: some View {
        let top = max(days.map(\.value).max() ?? 0, 1)
        return HStack(alignment: .bottom, spacing: Spacing.s1_5) {
            ForEach(days) { day in
                VStack(spacing: Spacing.s1) {
                    Capsule()
                        .fill(day.isToday ? tone.fill : Theme.mutedForeground.opacity(day.value > 0 ? 0.45 : 0.18))
                        .frame(width: Spacing.s2, height: max(Spacing.s1, Size.weekBar * CGFloat(day.value) / CGFloat(top)))
                    Text(verbatim: day.label)
                        .font(.hk(.x2s, day.isToday ? .semibold : .regular))
                        .foregroundStyle(day.isToday ? Theme.foreground : Theme.mutedForeground)
                }
            }
        }
        .frame(height: Size.weekBar + Spacing.s5, alignment: .bottom)
    }
}

#Preview {
    WeekActivityCard(
        title: "This week", headline: "2,481", caption: "words written",
        days: ["M", "T", "W", "T", "F", "S", "S"].enumerated().map { index, label in
            .init(id: index, label: label, value: [120, 0, 800, 340, 0, 1221, 0][index], isToday: index == 5)
        },
        footnote: "32 pages · 41,203 words in all"
    )
    .padding(Spacing.s4)
    .background(Theme.background)
}
