import Foundation

/// Streams a provider's answer over URLSession: the request from `RequestBuilders`, the `data:` lines through the
/// provider's `StreamDecoder`. A non-2xx answer is read (up to 64 KB) and mapped to an `AIError`; so are network errors.
/// Cancelling the consuming task cancels the request.
struct StreamingClient<Decoder: StreamDecoder>: AIClient {
    let makeRequest: @Sendable (AIRequest) throws -> URLRequest
    let makeDecoder: @Sendable () -> Decoder
    let session: URLSession

    func stream(_ request: AIRequest) -> AsyncThrowingStream<AIEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let http = try makeRequest(request)
                    let (bytes, response) = try await session.bytes(for: http)
                    if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
                        var body = Data()
                        for try await byte in bytes {
                            body.append(byte)
                            if body.count > 65_536 { break }
                        }
                        throw HTTPErrors.map(status: status, body: body)
                    }
                    var decoder = makeDecoder()
                    var finished = false
                    for try await line in bytes.lines {
                        guard let json = sseJSON(line) else { continue }
                        for event in try decoder.consume(json) {
                            continuation.yield(event)
                            if event == .finished { finished = true }
                        }
                    }
                    if !finished { continuation.yield(.finished) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: HTTPErrors.map(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Errors in the user's terms.
enum HTTPErrors {
    static func map(status: Int, body: Data) -> AIError {
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let error = json?["error"] as? [String: Any]
        let message = (error?["message"] as? String) ?? (json?["message"] as? String) ?? ""
        switch status {
        case 401, 403: return .unauthorized
        case 429: return .rateLimited
        case 500...599: return .unavailable
        default: return .rejected(message)
        }
    }

    static func map(_ error: Error) -> Error {
        if let error = error as? AIError { return error }
        if error is CancellationError { return AIError.cancelled }
        if let url = error as? URLError {
            switch url.code {
            case .cancelled: return AIError.cancelled
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .timedOut,
                .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed:
                return AIError.offline
            default: return AIError.unavailable
            }
        }
        return AIError.invalidResponse
    }
}

/// The client for a model, given the providers' keys.
public enum AIClients {
    /// `bases`: a provider's base URL when it isn't the default (`AIEndpoint`); one that may not carry a key (plain
    /// http to another machine) is refused before anything is sent.
    public static func client(
        for model: AIModel, keys: [AIProvider: String], bases: [AIProvider: URL] = [:], session: URLSession = .shared
    ) throws -> any AIClient {
        guard let key = keys[model.provider], !key.isEmpty else { throw AIError.missingKey(model.provider) }
        let base = bases[model.provider] ?? AIEndpoint.defaultBase(model.provider)
        guard AIEndpoint.mayCarryKey(base) else { throw AIError.badBaseURL(model.provider) }
        let url = AIEndpoint.requestURL(model.provider, base: base)
        switch model.provider {
        case .openAI:
            return StreamingClient(
                makeRequest: { try RequestBuilders.openAI($0, apiKey: key, url: url) },
                makeDecoder: { OpenAIStreamDecoder() }, session: session)
        case .anthropic:
            return StreamingClient(
                makeRequest: { try RequestBuilders.anthropic($0, apiKey: key, url: url) },
                makeDecoder: { AnthropicStreamDecoder() }, session: session)
        }
    }
}
