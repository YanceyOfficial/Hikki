import Foundation

/// The HTTP request for each provider: endpoint, headers, JSON body. Pure, so the shape is tested without a network.
enum RequestBuilders {
    static let openAIURL = AIEndpoint.requestURL(.openAI, base: AIEndpoint.defaultBase(.openAI))
    static let anthropicURL = AIEndpoint.requestURL(.anthropic, base: AIEndpoint.defaultBase(.anthropic))
    static let anthropicVersion = "2023-06-01"

    /// OpenAI's Responses API: `instructions` + `input` messages (images as data URLs), the `web_search` tool, streamed.
    static func openAI(_ request: AIRequest, apiKey: String, url: URL = openAIURL) throws -> URLRequest {
        var body: [String: Any] = [
            "model": request.model.id,
            "instructions": request.instructions,
            "input": request.messages.map(openAIMessage),
            "max_output_tokens": request.maxOutputTokens,
            "stream": true,
            // Nothing kept on OpenAI's side (each request carries its own history).
            "store": false,
        ]
        if request.webSearch { body["tools"] = [["type": "web_search"]] }
        var http = URLRequest(url: url)
        http.httpMethod = "POST"
        http.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        http.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        http.httpBody = try JSONSerialization.data(withJSONObject: body)
        return http
    }

    private static func openAIMessage(_ message: AIMessage) -> [String: Any] {
        let content: [[String: Any]] = message.parts.map { part in
            switch part {
            case .text(let text):
                ["type": message.role == .assistant ? "output_text" : "input_text", "text": text]
            case .image(let data, let mimeType):
                ["type": "input_image", "image_url": "data:\(mimeType);base64,\(data.base64EncodedString())"]
            }
        }
        return ["role": message.role.rawValue, "content": content]
    }

    /// Anthropic's Messages API: `system` + `messages` (images as base64 sources), the `web_search` server tool, streamed.
    static func anthropic(_ request: AIRequest, apiKey: String, url: URL = anthropicURL) throws -> URLRequest {
        var body: [String: Any] = [
            "model": request.model.id,
            "system": request.instructions,
            "messages": request.messages.map(anthropicMessage),
            "max_tokens": request.maxOutputTokens,
            "stream": true,
        ]
        if request.webSearch { body["tools"] = [["type": "web_search_20250305", "name": "web_search", "max_uses": 5]] }
        var http = URLRequest(url: url)
        http.httpMethod = "POST"
        http.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        http.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        http.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        http.httpBody = try JSONSerialization.data(withJSONObject: body)
        return http
    }

    private static func anthropicMessage(_ message: AIMessage) -> [String: Any] {
        let content: [[String: Any]] = message.parts.map { part in
            switch part {
            case .text(let text):
                ["type": "text", "text": text]
            case .image(let data, let mimeType):
                [
                    "type": "image",
                    "source": ["type": "base64", "media_type": mimeType, "data": data.base64EncodedString()],
                ]
            }
        }
        return ["role": message.role.rawValue, "content": content]
    }
}
