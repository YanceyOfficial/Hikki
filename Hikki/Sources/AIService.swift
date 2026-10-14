import Foundation
import HikkiAI
import HikkiCore

/// Runs the editor's AI requests: picks the model (Settings → AI), streams its answer and passes each event back to
/// the page that asked. One per editor; a request is cancelled when the page asks or a new one replaces it.
@MainActor
final class AIService {
    private var tasks: [String: Task<Void, Never>] = [:]

    /// Wires an editor's AI messages to this service.
    func attach(_ editor: EditorController) {
        editor.onAIRequest = { [weak self, weak editor] payload in
            guard let self, let editor else { return }
            self.run(payload) { [weak editor] event in editor?.sendAIEvent(event) }
        }
        editor.onAICancel = { [weak self] id in self?.cancel(id) }
    }

    func cancel(_ id: String) {
        tasks.removeValue(forKey: id)?.cancel()
    }

    private func run(_ payload: AIRequestPayload, send: @escaping @MainActor ([String: Any]) -> Void) {
        let id = payload.id
        let keys = Dictionary(uniqueKeysWithValues: AIProvider.allCases.compactMap { p in AIPreferences.key(p).map { (p, $0) } })
        let choice = UserDefaults.standard.string(forKey: AIPreferences.modelKey)
        guard let model = AIModelCatalog.resolve(choice, available: Set(keys.keys)) else {
            // No key at all: name the provider of the model chosen (or Auto's first choice).
            let provider = choice.flatMap(AIModelCatalog.model(id:))?.provider ?? .anthropic
            send(Self.event(id, for: .missingKey(provider)))
            return
        }
        let request = AIPrompts.request(for: Self.task(payload), model: model)
        let client: any AIClient
        do {
            client = try AIClients.client(for: model, keys: keys)
        } catch {
            send(Self.event(id, for: error as? AIError ?? .invalidResponse))
            return
        }
        Log.info(
            "AI request", category: "ai",
            context: ["action": payload.action, "model": model.id, "units": "\(payload.units.count)"])
        tasks[id]?.cancel()
        tasks[id] = Task { [weak self] in
            var characters = 0
            do {
                for try await event in client.stream(request) {
                    if Task.isCancelled { return }
                    if case .text(let delta) = event { characters += delta.count }
                    send(Self.event(id, for: event))
                }
                Log.info("AI request finished", category: "ai", context: ["characters": "\(characters)"])
            } catch {
                let failure = error as? AIError ?? (error is CancellationError ? .cancelled : .invalidResponse)
                if failure != .cancelled, !Task.isCancelled {
                    Log.warn("AI request failed: \(Self.code(failure))", category: "ai")
                    send(Self.event(id, for: failure))
                }
            }
            self?.tasks[id] = nil
        }
    }

    static func task(_ payload: AIRequestPayload) -> AITask {
        AITask(
            action: payload.action, instruction: payload.instruction, answer: payload.answer,
            units: payload.units.map { AITask.Unit(key: $0.key, html: $0.html) }, title: payload.context.title,
            before: payload.context.before, after: payload.context.after, previous: payload.context.previous)
    }

    /// An answer's event as the page reads it (`AIStreamEvent` in protocol.ts).
    static func event(_ id: String, for event: AIEvent) -> [String: Any] {
        switch event {
        case .text(let delta): ["id": id, "type": "text", "delta": delta]
        case .searching(let query): ["id": id, "type": "searching", "query": query ?? NSNull()]
        case .citation(let citation): ["id": id, "type": "citation", "url": citation.url, "title": citation.title ?? NSNull()]
        case .finished: ["id": id, "type": "done"]
        }
    }

    static func event(_ id: String, for error: AIError) -> [String: Any] {
        var event: [String: Any] = ["id": id, "type": "error", "code": code(error)]
        if case .missingKey(let provider) = error { event["provider"] = provider.name }
        if case .rejected(let message) = error, !message.isEmpty { event["message"] = String(message.prefix(300)) }
        return event
    }

    static func code(_ error: AIError) -> String {
        switch error {
        case .missingKey: "missingKey"
        case .unauthorized: "unauthorized"
        case .rateLimited: "rateLimited"
        case .unavailable: "unavailable"
        case .offline: "offline"
        case .rejected: "rejected"
        case .invalidResponse: "invalidResponse"
        case .cancelled: "cancelled"
        }
    }
}
