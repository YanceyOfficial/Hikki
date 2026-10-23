import Foundation

/// An answer that may call tools: each round streams the model's answer; when it called tools, they run (`perform`, in
/// the order called), their results go back as the next turn — with the answer as the provider sent it (`carried`) —
/// and the model goes on. Events reach the caller as they come, the calls and their results among them; `.finished`
/// comes once, at the very end. Past `maxRounds` the model is told to answer without tools.
public enum AIToolLoop {
    public static let maxRounds = 8

    public static func run(
        _ request: AIRequest, client: any AIClient, perform: @escaping @Sendable (AIToolCall) async -> AIToolOutput
    ) -> AsyncThrowingStream<AIEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = request
                    var wroteText = false
                    for round in 1...maxRounds {
                        if round == maxRounds { request.toolsAllowed = false }
                        var parts: [AIMessage.Part] = []
                        var calls: [AIToolCall] = []
                        var roundText = false
                        for try await event in client.stream(request) {
                            switch event {
                            case .text(let delta):
                                // A round's words start a paragraph of their own after the last round's.
                                if !roundText, wroteText { continuation.yield(.text("\n\n")) }
                                roundText = true
                                wroteText = true
                                if case .text(let earlier) = parts.last {
                                    parts[parts.count - 1] = .text(earlier + delta)
                                } else {
                                    parts.append(.text(delta))
                                }
                                continuation.yield(event)
                            case .carried(let provider, let json):
                                parts.append(.carried(provider, json))
                            case .toolCall(let call):
                                parts.append(.toolCall(call))
                                calls.append(call)
                                continuation.yield(event)
                            case .finished:
                                break
                            default:
                                continuation.yield(event)
                            }
                        }
                        guard !calls.isEmpty, request.toolsAllowed else { break }
                        request.messages.append(AIMessage(role: .assistant, parts: parts))
                        var results: [AIMessage.Part] = []
                        for call in calls {
                            try Task.checkCancellation()
                            let output = await perform(call)
                            continuation.yield(.toolResult(call, output))
                            results.append(.toolResult(callID: call.id, output: output.text, isError: output.isError))
                        }
                        try Task.checkCancellation()
                        request.messages.append(AIMessage(role: .user, parts: results))
                    }
                    continuation.yield(.finished)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: HTTPErrors.map(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
