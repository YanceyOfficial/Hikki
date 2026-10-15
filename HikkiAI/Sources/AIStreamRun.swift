import Foundation

/// One streamed answer at a time (Ask AI's chat): events go to `onEvent` as they come, and `onEnd` hears once how the
/// answer ended — nil when it ran to its end, else the failure. A stopped run, or one a newer `start` replaced, ends
/// silently: a stream that was cancelled finishes like one that completed (`AsyncThrowingStream` returns nil), which
/// read as an empty answer, and its late end cleared the newer run's state.
@MainActor
public final class AIStreamRun {
    private var task: Task<Void, Never>?
    /// Bumped by every start and stop: a run only reports while it is still the current one.
    private var generation = 0

    public init() {}

    /// A run is going (started, not stopped, not ended).
    public var isRunning: Bool { task != nil }

    public func start(
        _ stream: AsyncThrowingStream<AIEvent, Error>, onEvent: @escaping @MainActor (AIEvent) -> Void,
        onEnd: @escaping @MainActor (AIError?) -> Void
    ) {
        stop()
        let id = generation
        task = Task { [weak self] in
            var failure: AIError?
            do {
                for try await event in stream {
                    guard !Task.isCancelled, self?.generation == id else { return }
                    onEvent(event)
                }
            } catch {
                failure = error as? AIError ?? .invalidResponse
            }
            guard !Task.isCancelled, let self, self.generation == id else { return }
            self.task = nil
            onEnd(failure == .cancelled ? nil : failure)
        }
    }

    /// Cancels the run; its end is never reported.
    public func stop() {
        task?.cancel()
        task = nil
        generation += 1
    }
}
