import SwiftUI

/// How an answer was worked out, above it (actovia's thinking timeline): one line — while the model works, the step
/// it is on shimmering; afterwards "Thought for 12 seconds" — that opens into the steps, each a row on a thin rail:
/// a stretch of thinking (its title, then its words, quieter) or a web search (its query).
public struct ThinkingTimeline: View {
    public struct Step: Identifiable, Equatable, Sendable {
        public enum Kind: Sendable { case thinking, search }

        public var id: Int
        public var kind: Kind
        public var title: String
        public var detail: AttributedString

        public init(id: Int, kind: Kind, title: String, detail: AttributedString = AttributedString()) {
            self.id = id
            self.kind = kind
            self.title = title
            self.detail = detail
        }
    }

    let header: String
    let isStreaming: Bool
    let steps: [Step]
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `header`: the step in progress while `isStreaming`, else the summary ("Thought for 12 seconds").
    public init(header: String, isStreaming: Bool, steps: [Step]) {
        self.header = header
        self.isStreaming = isStreaming
        self.steps = steps
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: Spacing.s1_5) {
                    if isStreaming && reduceMotion {
                        ProgressView().controlSize(.mini)
                    } else {
                        AIGlyph(size: TextSize.sm.rawValue, tinted: isStreaming)
                    }
                    Group {
                        if isStreaming {
                            ShimmerText(verbatim: header)
                        } else {
                            Text(verbatim: header).foregroundStyle(Theme.mutedForeground)
                        }
                    }
                    .font(.hk(.sm, .medium))
                    .lineLimit(1)
                    if !steps.isEmpty {
                        IconView(.caretDown, size: TextSize.xs.rawValue)
                            .foregroundStyle(Theme.mutedForeground)
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(steps.isEmpty)
            .accessibilityIdentifier("thinking-timeline")
            .accessibilityValue(Text(expanded ? "app:ai.timeline.expanded" : "app:ai.timeline.collapsed"))

            if expanded {
                VStack(alignment: .leading, spacing: Spacing.s0) {
                    ForEach(steps) { step in row(step, isLast: step.id == steps.last?.id) }
                }
                .padding(.leading, Spacing.px)
                .transition(.opacity)
            }
        }
        .animation(Motion.easeOut(), value: expanded)
    }

    private func row(_ step: Step, isLast: Bool) -> some View {
        let active = isStreaming && isLast
        return HStack(alignment: .top, spacing: Spacing.s2_5) {
            VStack(spacing: Spacing.s1) {
                IconView(step.kind == .search ? .globe : .sparkle, size: TextSize.sm.rawValue)
                    .foregroundStyle(active ? Theme.foreground : Theme.mutedForeground)
                    .padding(.top, Spacing.px)
                if !isLast {
                    Rectangle().fill(Theme.border).frame(width: Spacing.px).frame(maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: Spacing.s0_5) {
                Text(verbatim: step.title)
                    .font(.hk(.sm, .medium))
                    .foregroundStyle(active ? Theme.foreground : Theme.mutedForeground)
                if !step.detail.characters.isEmpty {
                    Text(step.detail)
                        .font(.hk(.sm))
                        .foregroundStyle(Theme.mutedForeground)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, isLast ? Spacing.s0 : Spacing.s3)
        }
        .transition(.opacity)
    }
}

#Preview("Thinking timeline") {
    VStack(alignment: .leading, spacing: Spacing.s6) {
        ThinkingTimeline(
            header: "Checking the dates", isStreaming: true,
            steps: [.init(id: 0, kind: .thinking, title: "Reading the page", detail: "The trip is planned for May.")])
        ThinkingTimeline(
            header: "Thought for 12 seconds", isStreaming: false,
            steps: [
                .init(id: 0, kind: .thinking, title: "Reading the page", detail: "The trip is planned for May; flights are booked."),
                .init(id: 1, kind: .search, title: "Searched for “Kyoto weather May”"),
                .init(id: 2, kind: .thinking, title: "Answering", detail: "Mild, 15–25 °C, with some rain."),
            ])
    }
    .padding()
    .frame(width: 360)
}
