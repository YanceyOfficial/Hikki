import Testing

@testable import HikkiCore

struct ChatTimelineTests {
    @Test func thinkingAndSearchesFormSteps() {
        var t = ChatTimeline.step(.thinking, in: nil)
        t = ChatTimeline.thought("**Reading**", in: t)
        t = ChatTimeline.thought(" the page", in: t)
        t = ChatTimeline.searched(nil, in: t)
        t = ChatTimeline.searched("kyoto weather may", in: t)
        // The same search named again (start, then done) stays one step.
        t = ChatTimeline.searched("kyoto weather may", in: t)
        t = ChatTimeline.thought("Mild.", in: t)
        #expect(t.steps.map(\.kind) == [.thinking, .search, .thinking])
        #expect(t.steps.map(\.text) == ["**Reading** the page", "kyoto weather may", "Mild."])
    }

    @Test func emptyStepsArentKept() {
        var t = ChatTimeline.step(.thinking, in: nil)
        t = ChatTimeline.step(.thinking, in: t)
        #expect(t.steps.count == 1)
        #expect(ChatTimeline.kept(t) == nil)
        t = ChatTimeline.searched("q", in: t)
        #expect(ChatTimeline.kept(t)?.steps.map(\.kind) == [.search])
    }
}
