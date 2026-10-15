import Foundation

/// What a text is for: a search query or a stored passage. Some models are trained with a prefix for each
/// (`EmbeddingPrefixes`).
public enum EmbeddingKind: Sendable {
    case query, passage
}

/// Something that turns text into vectors. Hikki only reads and writes them: the model runs elsewhere (Ollama by
/// default), and any provider can stand in as long as this stays the same.
public protocol EmbeddingProvider: Sendable {
    /// Which model makes the vectors — vectors from different models can't be compared, so the index keeps this and
    /// starts over when it changes.
    var identity: String { get }
    /// One vector per text, in order, each scaled to unit length.
    func embed(_ texts: [String], kind: EmbeddingKind) async throws -> [[Float]]
}

/// Prefixes some embedding models were trained with; without them their results get worse. Chosen by model name.
public struct EmbeddingPrefixes: Sendable, Equatable {
    public var query: String
    public var passage: String

    public static let none = EmbeddingPrefixes(query: "", passage: "")

    public static func forModel(_ model: String) -> EmbeddingPrefixes {
        let name = model.lowercased()
        if name.contains("e5") { return EmbeddingPrefixes(query: "query: ", passage: "passage: ") }
        if name.contains("qwen3-embedding") {
            // Qwen3-Embedding reads an instruction before a query; passages go as they are.
            return EmbeddingPrefixes(
                query: "Instruct: Given a search query, retrieve passages of the user's notes that answer it\nQuery: ",
                passage: "")
        }
        if name.contains("nomic-embed") {
            return EmbeddingPrefixes(query: "search_query: ", passage: "search_document: ")
        }
        return .none
    }
}

public enum EmbeddingError: Error, Equatable, Sendable {
    /// Nothing answered at the endpoint (not running, wrong address, offline).
    case unreachable
    /// It answered with an HTTP error (an unknown model is a 404 on Ollama).
    case http(Int)
    /// It answered with something that isn't an embeddings response.
    case badResponse
}

/// The OpenAI-compatible embeddings API (`POST <base>/embeddings`, `GET <base>/models`): Ollama, LM Studio,
/// llama.cpp's server, text-embeddings-inference and OpenAI itself all speak it.
public struct OpenAICompatibleEmbeddings: EmbeddingProvider {
    public let baseURL: URL
    public let model: String
    public let apiKey: String?
    public let prefixes: EmbeddingPrefixes
    private let session: URLSession

    public init(baseURL: URL, model: String, apiKey: String? = nil, session: URLSession? = nil) {
        self.baseURL = baseURL
        self.model = model
        // A key never crosses the network in the clear: over http only to this machine.
        self.apiKey = apiKey.flatMap { $0.isEmpty || !Self.mayCarryKey(baseURL) ? nil : $0 }
        prefixes = EmbeddingPrefixes.forModel(model)
        self.session = session ?? Self.makeSession(for: baseURL)
    }

    public var identity: String { "\(baseURL.absoluteString)|\(model)" }

    /// Whether a key may be sent to this address: https anywhere, http only to loopback.
    public static func mayCarryKey(_ url: URL) -> Bool {
        url.scheme == "https" || (url.scheme == "http" && isLoopback(url))
    }

    /// The scheme, host and port a key belongs to: it is only ever sent back there (`SemanticPreferences`).
    public static func origin(of url: URL) -> String? {
        guard let scheme = url.scheme, let host = url.host() else { return nil }
        return "\(scheme)://\(host.lowercased())" + (url.port.map { ":\($0)" } ?? "")
    }

    static func isLoopback(_ url: URL) -> Bool {
        guard let host = url.host() else { return false }
        return ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host.lowercased())
    }

    /// A model on this machine is reached directly: a system or shell proxy would otherwise get the loopback request.
    static func makeSession(for url: URL) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        if isLoopback(url) {
            configuration.connectionProxyDictionary = [:]
        }
        return URLSession(configuration: configuration)
    }

    public func embed(_ texts: [String], kind: EmbeddingKind) async throws -> [[Float]] {
        guard !texts.isEmpty else { return [] }
        let prefix = kind == .query ? prefixes.query : prefixes.passage
        var request = URLRequest(url: baseURL.appending(path: "embeddings"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONEncoder().encode(Request(model: model, input: texts.map { prefix + $0 }))
        let response: Response = try await send(request)
        // In the order asked, by `index` where the server gives one.
        let vectors = response.data.enumerated()
            .sorted { ($0.element.index ?? $0.offset) < ($1.element.index ?? $1.offset) }
            .map { Self.normalized($0.element.embedding) }
        guard vectors.count == texts.count, let width = vectors.first?.count, width > 0,
            vectors.allSatisfy({ $0.count == width })
        else { throw EmbeddingError.badResponse }
        return vectors
    }

    /// The models the endpoint offers (Settings lists them to pick from).
    public func models() async throws -> [String] {
        var request = URLRequest(url: baseURL.appending(path: "models"))
        if let apiKey { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        let list: ModelList = try await send(request)
        return list.data.map(\.id).sorted()
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw EmbeddingError.unreachable
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw EmbeddingError.http(http.statusCode)
        }
        guard let decoded = try? JSONDecoder().decode(T.self, from: data) else { throw EmbeddingError.badResponse }
        return decoded
    }

    static func normalized(_ vector: [Float]) -> [Float] {
        let length = vector.reduce(0) { $0 + $1 * $1 }.squareRoot()
        return length > 0 ? vector.map { $0 / length } : vector
    }

    private struct Request: Encodable {
        var model: String
        var input: [String]
    }

    private struct Response: Decodable {
        struct Item: Decodable {
            var index: Int?
            var embedding: [Float]
        }
        var data: [Item]
    }

    private struct ModelList: Decodable {
        struct Model: Decodable { var id: String }
        var data: [Model]
    }
}
