import Foundation
import Testing

@testable import HikkiAI

@MainActor
struct AIStreamRunTests {
    /// A stream the test drives by hand (a model that hasn't answered yet).
    private func pending() -> (AsyncThrowingStream<AIEvent, Error>, AsyncThrowingStream<AIEvent, Error>.Continuation) {
        AsyncThrowingStream.makeStream(of: AIEvent.self)
    }

    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(20))
    }

    @Test func stoppingBeforeAnyTextEndsSilently() async {
        let run = AIStreamRun()
        let (stream, continuation) = pending()
        var ends: [AIError?] = []
        run.start(stream, onEvent: { _ in }, onEnd: { ends.append($0) })
        #expect(run.isRunning)
        run.stop()
        await settle()
        continuation.finish()  // the provider's stream winding down after the cancel
        await settle()
        #expect(ends.isEmpty)  // no "empty answer" error for a stopped question
        #expect(!run.isRunning)
    }

    @Test func aStaleRunNeverEndsTheNewOne() async {
        let run = AIStreamRun()
        let (first, firstContinuation) = pending()
        let (second, secondContinuation) = pending()
        var ends: [String] = []
        var texts: [String] = []
        run.start(first, onEvent: { _ in }, onEnd: { _ in ends.append("first") })
        run.start(second, onEvent: { if case .text(let t) = $0 { texts.append(t) } }, onEnd: { _ in ends.append("second") })
        firstContinuation.yield(.text("late"))
        firstContinuation.finish()
        await settle()
        #expect(ends.isEmpty)
        #expect(run.isRunning)  // the new run's handle survives the old one finishing
        secondContinuation.yield(.text("hello"))
        secondContinuation.finish()
        await settle()
        #expect(texts == ["hello"])
        #expect(ends == ["second"])
        #expect(!run.isRunning)
    }

    @Test func failuresReachTheEnd() async {
        let run = AIStreamRun()
        let (stream, continuation) = pending()
        var ends: [AIError?] = []
        run.start(stream, onEvent: { _ in }, onEnd: { ends.append($0) })
        continuation.finish(throwing: AIError.invalidResponse)
        await settle()
        #expect(ends == [.invalidResponse])
    }
}
