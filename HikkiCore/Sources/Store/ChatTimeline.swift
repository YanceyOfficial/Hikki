import Foundation

/// How an answer's thinking timeline (`ChatThinking`) grows as the model's events arrive: thinking runs on in one step
/// until the provider starts a new one or a search comes between; a search is a step of its own, its query filled in
/// when the provider says it (OpenAI and Anthropic name it only once the search is under way).
public enum ChatTimeline {
    public static func step(_ kind: ChatThinking.Step.Kind, in thinking: ChatThinking?) -> ChatThinking {
        var thinking = thinking ?? ChatThinking()
        // An empty step is reused rather than left behind.
        if let last = thinking.steps.last, last.kind == kind, last.text.isEmpty { return thinking }
        thinking.steps.append(.init(kind: kind, text: ""))
        return thinking
    }

    public static func thought(_ delta: String, in thinking: ChatThinking?) -> ChatThinking {
        var thinking = thinking ?? ChatThinking()
        if thinking.steps.last?.kind != .thinking { thinking.steps.append(.init(kind: .thinking, text: "")) }
        thinking.steps[thinking.steps.count - 1].text += delta
        return thinking
    }

    public static func searched(_ query: String?, in thinking: ChatThinking?) -> ChatThinking {
        var thinking = thinking ?? ChatThinking()
        let query = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let last = thinking.steps.last, last.kind == .search, last.text.isEmpty || last.text == query {
            if !query.isEmpty { thinking.steps[thinking.steps.count - 1].text = query }
            return thinking
        }
        thinking.steps.append(.init(kind: .search, text: query))
        return thinking
    }

    /// The answer's first words end its thinking: the timeline keeps how long it took, from `startedAt` (the question's
    /// moment) to `now` — once; nothing without a timeline, nothing more once it is timed.
    public static func ended(_ thinking: ChatThinking?, startedAt: Date, now: Date = .now) -> ChatThinking? {
        guard var thinking, thinking.seconds == nil else { return thinking }
        thinking.seconds = now.timeIntervalSince(startedAt)
        return thinking
    }

    /// As it is kept: thinking steps with nothing in them left out; nil when nothing is left.
    public static func kept(_ thinking: ChatThinking) -> ChatThinking? {
        var kept = thinking
        kept.steps.removeAll { $0.kind == .thinking && $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return kept.steps.isEmpty ? nil : kept
    }
}
