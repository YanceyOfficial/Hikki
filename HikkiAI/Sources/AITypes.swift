import Foundation

/// Who runs a model. Only these two for now (the owner's call: no other vendors).
public enum AIProvider: String, CaseIterable, Codable, Sendable {
    case anthropic, openAI

    public var name: String {
        switch self {
        case .anthropic: "Anthropic"
        case .openAI: "OpenAI"
        }
    }
}

/// One model the app offers. The list is fixed (`AIModelCatalog`); the API id is what the provider is sent.
public struct AIModel: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let provider: AIProvider
    /// "Opus", "GPT-6.1" — shown bold.
    public let family: String
    /// "5.5", "Sol" — shown after the family, quieter.
    public let version: String

    public init(id: String, provider: AIProvider, family: String, version: String) {
        self.id = id
        self.provider = provider
        self.family = family
        self.version = version
    }

    public var displayName: String { "\(family) \(version)" }
}

/// A turn of a conversation.
public struct AIMessage: Equatable, Sendable {
    public enum Role: String, Sendable { case user, assistant }

    public enum Part: Equatable, Sendable {
        case text(String)
        /// An image the user attached (PNG / JPEG / GIF / WebP).
        case image(Data, mimeType: String)
    }

    public var role: Role
    public var parts: [Part]

    public init(role: Role, parts: [Part]) {
        self.role = role
        self.parts = parts
    }

    public static func user(_ text: String) -> AIMessage { AIMessage(role: .user, parts: [.text(text)]) }
    public static func assistant(_ text: String) -> AIMessage { AIMessage(role: .assistant, parts: [.text(text)]) }

    /// The text parts joined (for providers' plain-text history).
    public var text: String {
        parts.compactMap { if case .text(let text) = $0 { text } else { nil } }.joined(separator: "\n")
    }
}

/// What to ask a model.
public struct AIRequest: Sendable {
    public var model: AIModel
    /// Instructions (the system prompt): the task, the document's context, how to answer.
    public var instructions: String
    public var messages: [AIMessage]
    /// Let the model search the web with the provider's own tool (results come back as `.citation`s).
    public var webSearch: Bool
    public var maxOutputTokens: Int

    public init(
        model: AIModel, instructions: String, messages: [AIMessage], webSearch: Bool = false, maxOutputTokens: Int = 4096
    ) {
        self.model = model
        self.instructions = instructions
        self.messages = messages
        self.webSearch = webSearch
        self.maxOutputTokens = maxOutputTokens
    }
}

/// A source the answer cites (from the provider's web search).
public struct AICitation: Hashable, Codable, Sendable {
    public var url: String
    public var title: String?

    public init(url: String, title: String?) {
        self.url = url
        self.title = title
    }
}

/// What a stream yields, in order: text as it is written, web searches as they start, the sources cited, the end.
public enum AIEvent: Equatable, Sendable {
    case text(String)
    /// A web search began (the query when the provider says it).
    case searching(String?)
    case citation(AICitation)
    case finished
}

/// Why a request failed, in the user's terms (each has a message in the app).
public enum AIError: Error, Equatable, Sendable {
    /// No key for the model's provider (Settings → AI).
    case missingKey(AIProvider)
    /// The provider's base URL (Settings → AI) isn't usable: not a URL, or plain http to another machine.
    case badBaseURL(AIProvider)
    /// The key was refused.
    case unauthorized
    /// Too many requests, or the account's quota is used up.
    case rateLimited
    /// The provider is busy or down (5xx, overloaded).
    case unavailable
    /// No connection.
    case offline
    /// The request itself was refused (bad model id, content policy, too long), with the provider's words.
    case rejected(String)
    /// The reply couldn't be read.
    case invalidResponse
    case cancelled
}

/// Something that streams a model's answer. `HikkiAI.client(for:keys:)` picks the provider's.
public protocol AIClient: Sendable {
    func stream(_ request: AIRequest) -> AsyncThrowingStream<AIEvent, Error>
}
