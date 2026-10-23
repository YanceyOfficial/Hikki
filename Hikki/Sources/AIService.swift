import Foundation
import HikkiAI
import HikkiCore
import UniformTypeIdentifiers

/// Runs the editor's AI requests: picks the model (the panel's pick, else Settings → AI), streams its answer and passes each event back to
/// the page that asked. One per editor; a request is cancelled when the page asks or a new one replaces it.
@MainActor
final class AIService {
    private var tasks: [String: Task<Void, Never>] = [:]

    /// Wires an editor's AI messages to this service.
    func attach(_ editor: EditorController) {
        editor.onAIRequest = { [weak self, weak editor] payload in
            guard let self, let editor else { return }
            // A picture or a PDF asked about: the workspace's own file (never a path the page names).
            let file = payload.media.flatMap { AssetStore.name(fromURL: $0.url) }.flatMap(editor.assetFile(named:))
            self.run(payload, mediaFile: file) { [weak editor] event in editor?.sendAIEvent(event) }
        }
        editor.onAICancel = { [weak self] id in self?.cancel(id) }
    }

    func cancel(_ id: String) {
        tasks.removeValue(forKey: id)?.cancel()
    }

    private func run(
        _ payload: AIRequestPayload, mediaFile: URL?, send: @escaping @MainActor ([String: Any]) -> Void
    ) {
        let id = payload.id
        // The trial is over: AI waits for the unlock (the page says why).
        guard Purchases.shared.access.canWrite else {
            Purchases.shared.isShowingUnlock = true
            send(["id": id, "type": "error", "code": "locked"])
            return
        }
        let client: any AIClient
        let model: AIModel
        // A model picked in the panel for this request, else the default (Settings → AI, the chat's last pick).
        switch Self.connect(payload.model ?? UserDefaults.standard.string(forKey: AIPreferences.modelKey)) {
        case .success(let connection): (model, client) = connection
        case .failure(let error):
            send(Self.event(id, for: error))
            return
        }
        Log.info(
            "AI request", category: "ai",
            context: [
                "action": payload.action, "model": model.id, "units": "\(payload.units.count)",
                "media": payload.media?.kind.rawValue ?? "none",
            ])
        tasks[id]?.cancel()
        tasks[id] = Task { [weak self] in
            var characters = 0
            var part: AIMessage.Part?
            if let media = payload.media {
                do {
                    part = try await Self.mediaPart(media, file: mediaFile)
                } catch {
                    if Task.isCancelled { return }
                    Incident.report(.aiMediaUnreadable, error, category: "ai")
                    send(["id": id, "type": "error", "code": "mediaUnreadable"])
                    self?.tasks[id] = nil
                    return
                }
            }
            let request = AIPrompts.request(for: Self.task(payload, media: part), model: model)
            do {
                for try await event in client.stream(request) {
                    if Task.isCancelled { return }
                    if case .text(let delta) = event { characters += delta.count }
                    if let event = Self.event(id, for: event) { send(event) }
                }
                Log.info("AI request finished", category: "ai", context: ["characters": "\(characters)"])
            } catch {
                let failure = error as? AIError ?? (error is CancellationError ? .cancelled : .invalidResponse)
                if failure != .cancelled, !Task.isCancelled {
                    // Shown in the page's own AI panel; logged with its code and an incident id.
                    if let code = failure.errorCode { Incident.report(code, failure, category: "ai") }
                    send(Self.event(id, for: failure))
                }
            }
            self?.tasks[id] = nil
        }
    }

    /// The model a choice ("auto", or a catalog id) runs on and its client — or why it can't: no key for it (Auto
    /// with no key at all names the chosen model's provider, else Anthropic), or an unusable base URL.
    static func connect(_ choice: String?) -> Result<(AIModel, any AIClient), AIError> {
        let keys = Dictionary(uniqueKeysWithValues: AIProvider.allCases.compactMap { p in AIPreferences.key(p).map { (p, $0) } })
        guard let model = AIModelCatalog.resolve(choice, available: Set(keys.keys)) else {
            let provider = choice.flatMap(AIModelCatalog.model(id:))?.provider ?? .anthropic
            return .failure(AIPreferences.base(provider) == nil ? .badBaseURL(provider) : .missingKey(provider))
        }
        guard let base = AIPreferences.base(model.provider) else { return .failure(.badBaseURL(model.provider)) }
        do {
            return .success((model, try AIClients.client(for: model, keys: keys, bases: [model.provider: base])))
        } catch {
            return .failure(error as? AIError ?? .invalidResponse)
        }
    }

    /// What went wrong, in the user's words (the native Ask AI sheet; the page has its own strings).
    static func message(for error: AIError) -> String {
        switch error {
        case .missingKey(let provider): String(localized: "app:ai.error.missingKey \(provider.name)")
        case .badBaseURL(let provider): String(localized: "app:ai.error.badBaseURL \(provider.name)")
        case .unauthorized: String(localized: "app:ai.error.unauthorized")
        case .rateLimited: String(localized: "app:ai.error.rateLimited")
        case .unavailable: String(localized: "app:ai.error.unavailable")
        case .offline: String(localized: "app:ai.error.offline")
        case .rejected(let message) where !message.isEmpty:
            String(localized: "app:ai.error.rejectedWith \(String(message.prefix(300)))")
        case .rejected: String(localized: "app:ai.error.rejected")
        case .refused: String(localized: "app:ai.error.refused")
        case .invalidResponse, .cancelled: String(localized: "app:ai.error.invalidResponse")
        }
    }

    /// The app's language by name, for answers (the system's per-app language choice).
    static var appLanguage: String {
        AIPrompts.languageName(Bundle.main.preferredLocalizations.first ?? "en")
    }

    /// The file a request is about, made ready for the model (pictures scaled, PDFs within the size limit), read off the
    /// main thread. Fails when the page named no workspace file, or it can't be read.
    @concurrent
    nonisolated static func mediaPart(_ media: AIRequestPayload.Media, file: URL?) async throws -> AIMessage.Part {
        guard let file else { throw AIAttachments.Failure.unreadable }
        let data = try Data(contentsOf: file)
        switch media.kind {
        case .image: return try AIAttachments.image(data)
        case .pdf: return try AIAttachments.part(data, type: .pdf, name: media.name ?? file.lastPathComponent)
        }
    }

    static func task(_ payload: AIRequestPayload, media: AIMessage.Part? = nil) -> AITask {
        AITask(
            action: payload.action, instruction: payload.instruction, answer: payload.answer,
            units: payload.units.map { AITask.Unit(key: $0.key, html: $0.html) }, title: payload.context.title,
            before: payload.context.before, after: payload.context.after, previous: payload.context.previous,
            language: appLanguage, media: media)
    }

    /// An answer's event as the page reads it (`AIStreamEvent` in protocol.ts); nil for what the page doesn't show.
    static func event(_ id: String, for event: AIEvent) -> [String: Any]? {
        switch event {
        case .text(let delta): ["id": id, "type": "text", "delta": delta]
        case .searching(let query): ["id": id, "type": "searching", "query": query ?? NSNull()]
        case .citation(let citation): ["id": id, "type": "citation", "url": citation.url, "title": citation.title ?? NSNull()]
        case .finished: ["id": id, "type": "done"]
        // The page's requests don't ask for thinking, pictures or tools (only the chat has them).
        case .reasoning, .reasoningStep, .image, .toolCall, .toolResult, .carried: nil
        }
    }

    static func event(_ id: String, for error: AIError) -> [String: Any] {
        var event: [String: Any] = ["id": id, "type": "error", "code": code(error)]
        if case .missingKey(let provider) = error { event["provider"] = provider.name }
        if case .badBaseURL(let provider) = error { event["provider"] = provider.name }
        if case .rejected(let message) = error, !message.isEmpty { event["message"] = String(message.prefix(300)) }
        return event
    }

    /// The name the editor's `ai.error.*` strings key on.
    static func code(_ error: AIError) -> String { error.legacyName }
}

extension AIError {
    /// The code a failure is logged and reported under (nil: cancelled, nothing went wrong).
    var errorCode: ErrorCode? {
        switch self {
        case .missingKey: .aiMissingKey
        case .badBaseURL: .aiBadBaseURL
        case .unauthorized: .aiUnauthorized
        case .rateLimited: .aiRateLimited
        case .unavailable: .aiUnavailable
        case .offline: .aiOffline
        case .rejected: .aiRejected
        case .refused: .aiPictureRefused
        case .invalidResponse: .aiInvalidResponse
        case .cancelled: nil
        }
    }

    /// The pre-registry names (the editor's `ai.error.*` strings key on them).
    var legacyName: String {
        switch self {
        case .missingKey: "missingKey"
        case .badBaseURL: "badBaseURL"
        case .unauthorized: "unauthorized"
        case .rateLimited: "rateLimited"
        case .unavailable: "unavailable"
        case .offline: "offline"
        case .rejected: "rejected"
        case .refused: "refused"
        case .invalidResponse: "invalidResponse"
        case .cancelled: "cancelled"
        }
    }
}
