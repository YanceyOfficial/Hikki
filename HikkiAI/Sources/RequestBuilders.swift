import Foundation

/// The HTTP request for each provider: endpoint, headers, JSON body. Pure, so the shape is tested without a network.
enum RequestBuilders {
    static let openAIURL = AIEndpoint.requestURL(.openAI, base: AIEndpoint.defaultBase(.openAI))
    static let anthropicURL = AIEndpoint.requestURL(.anthropic, base: AIEndpoint.defaultBase(.anthropic))
    static let anthropicVersion = "2023-06-01"
    /// Tokens Anthropic's models may think with before answering (extended thinking's minimum is 1024).
    static let anthropicThinkingBudget = 4096

    /// OpenAI's Responses API: `instructions` + `input` messages (images as data URLs), the `web_search` tool (with its
    /// image results when asked), streamed.
    static func openAI(_ request: AIRequest, apiKey: String, url: URL = openAIURL) throws -> URLRequest {
        var body: [String: Any] = [
            "model": request.model.id,
            "instructions": request.instructions,
            "input": request.messages.flatMap(openAIItems),
            "max_output_tokens": request.maxOutputTokens,
            "stream": true,
            // Nothing kept on OpenAI's side (each request carries its own history).
            "store": false,
        ]
        var tools: [[String: Any]] = []
        var include: [String] = []
        if request.webSearch {
            var tool: [String: Any] = ["type": "web_search"]
            if request.imageResults > 0 {
                // Pictures come back in the search call's results, which are left out unless included.
                tool["search_content_types"] = ["text", "image"]
                tool["image_settings"] = ["max_results": request.imageResults, "caption": true]
                include.append("web_search_call.results")
            }
            tools.append(tool)
        }
        tools += request.tools.map {
            ["type": "function", "name": $0.name, "description": $0.description, "parameters": $0.schema, "strict": false]
        }
        if !tools.isEmpty { body["tools"] = tools }
        if !request.tools.isEmpty, !request.toolsAllowed { body["tool_choice"] = "none" }
        // Reasoning models think anyway; this asks for the summary of it to be streamed.
        if request.reasoning {
            body["reasoning"] = ["summary": "auto"]
            // Nothing is stored on OpenAI's side, so a tool's result goes back with the reasoning that led to the call,
            // encrypted (`carried`).
            if !request.tools.isEmpty { include.append("reasoning.encrypted_content") }
        }
        if !include.isEmpty { body["include"] = include }
        var http = URLRequest(url: url)
        http.httpMethod = "POST"
        http.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        http.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        http.httpBody = try JSONSerialization.data(withJSONObject: body)
        return http
    }

    /// A turn as Responses input items, in its order: messages, calls and tools' results, or — for an answer
    /// that called tools — the items it came as (`carried`), which also hold its calls.
    private static func openAIItems(_ message: AIMessage) -> [[String: Any]] {
        let carried = message.parts.compactMap { part -> [String: Any]? in
            guard case .carried(.openAI, let json) = part else { return nil }
            return jsonObject(json)
        }
        if !carried.isEmpty { return carried }
        var items: [[String: Any]] = []
        var content: [[String: Any]] = []
        // Items keep the turn's order: words before a call go first, as a message of their own.
        func flush() {
            if !content.isEmpty { items.append(["role": message.role.rawValue, "content": content]) }
            content = []
        }
        for part in message.parts {
            switch part {
            case .text(let text):
                content.append(["type": message.role == .assistant ? "output_text" : "input_text", "text": text])
            case .image(let data, let mimeType):
                content.append(["type": "input_image", "image_url": "data:\(mimeType);base64,\(data.base64EncodedString())"])
            case .document(let data, let mimeType, let name):
                content.append(
                    ["type": "input_file", "filename": name, "file_data": "data:\(mimeType);base64,\(data.base64EncodedString())"])
            case .toolCall(let call):
                flush()
                items.append(["type": "function_call", "call_id": call.id, "name": call.name, "arguments": call.arguments])
            case .toolResult(let id, let output, _):
                flush()
                items.append(["type": "function_call_output", "call_id": id, "output": output])
            case .carried:
                break
            }
        }
        flush()
        return items
    }

    static func jsonObject(_ json: String) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any]
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
        var tools: [[String: Any]] = []
        if request.webSearch { tools.append(["type": "web_search_20250305", "name": "web_search", "max_uses": 5]) }
        tools += request.tools.map { ["name": $0.name, "description": $0.description, "input_schema": $0.schema] }
        if !tools.isEmpty { body["tools"] = tools }
        if !request.tools.isEmpty, !request.toolsAllowed { body["tool_choice"] = ["type": "none"] }
        // Extended thinking: its budget comes on top of the answer's (max_tokens must exceed it).
        if request.reasoning {
            body["thinking"] = ["type": "enabled", "budget_tokens": anthropicThinkingBudget]
            body["max_tokens"] = request.maxOutputTokens + anthropicThinkingBudget
        }
        var http = URLRequest(url: url)
        http.httpMethod = "POST"
        http.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        http.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        http.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        http.httpBody = try JSONSerialization.data(withJSONObject: body)
        return http
    }

    /// A turn's content blocks: tools' results first (as the API asks), then the rest; an answer that called tools is
    /// sent as the blocks it came as (`carried`: thinking with its signature, searches, words, `tool_use`).
    private static func anthropicMessage(_ message: AIMessage) -> [String: Any] {
        let carried = message.parts.compactMap { part -> [String: Any]? in
            guard case .carried(.anthropic, let json) = part else { return nil }
            return jsonObject(json)
        }
        if !carried.isEmpty { return ["role": message.role.rawValue, "content": carried] }
        var results: [[String: Any]] = []
        var content: [[String: Any]] = []
        for part in message.parts {
            switch part {
            case .text(let text):
                content.append(["type": "text", "text": text])
            case .image(let data, let mimeType):
                content.append([
                    "type": "image",
                    "source": ["type": "base64", "media_type": mimeType, "data": data.base64EncodedString()],
                ])
            case .document(let data, let mimeType, _):
                content.append([
                    "type": "document",
                    "source": ["type": "base64", "media_type": mimeType, "data": data.base64EncodedString()],
                ])
            case .toolCall(let call):
                content.append([
                    "type": "tool_use", "id": call.id, "name": call.name,
                    "input": jsonObject(call.arguments) ?? [String: Any](),
                ])
            case .toolResult(let id, let output, let isError):
                results.append(["type": "tool_result", "tool_use_id": id, "content": output, "is_error": isError])
            case .carried:
                break
            }
        }
        return ["role": message.role.rawValue, "content": results + content]
    }
}
