import Foundation

/// A provider's server-sent events, one `data:` line at a time, turned into `AIEvent`s. Both APIs put the event's type
/// inside the JSON, so `event:` lines aren't needed. Tolerant: an event it doesn't know, or a field that is missing, is
/// skipped — a reply never crashes the app; only an explicit error event throws.
protocol StreamDecoder: Sendable {
    mutating func consume(_ json: [String: Any]) throws -> [AIEvent]
}

/// The JSON object on a `data:` line, or nil (comments, `[DONE]`, keep-alives, malformed lines).
func sseJSON(_ line: some StringProtocol) -> [String: Any]? {
    guard line.hasPrefix("data:") else { return nil }
    let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
    guard payload.hasPrefix("{"), let data = payload.data(using: .utf8) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}

/// OpenAI's Responses API stream: `response.output_text.delta` (text), `response.reasoning_summary_*` (thinking), `response.web_search_call.*` and the finished
/// `web_search_call` item (the query, and its `image_result`s), `response.output_text.annotation.added` (`url_citation`), a finished
/// `function_call` item (a tool call), `response.completed`, and `response.failed` / `error`. Every finished output item is also
/// `carried`, to go back with a tool's result.
struct OpenAIStreamDecoder: StreamDecoder {
    private var cited = Set<String>()
    private var pictures = Set<String>()

    mutating func consume(_ json: [String: Any]) throws -> [AIEvent] {
        switch json["type"] as? String {
        case "response.output_text.delta":
            guard let delta = json["delta"] as? String, !delta.isEmpty else { return [] }
            return [.text(delta)]
        case "response.reasoning_summary_part.added":
            return [.reasoningStep]
        case "response.reasoning_summary_text.delta":
            guard let delta = json["delta"] as? String, !delta.isEmpty else { return [] }
            return [.reasoning(delta)]
        case "response.web_search_call.in_progress":
            return [.searching(nil)]
        case "response.output_item.done":
            guard let item = json["item"] as? [String: Any] else { return [] }
            var events = Self.carried(item).map { [AIEvent.carried(.openAI, $0)] } ?? []
            if item["type"] as? String == "function_call", let id = item["call_id"] as? String, let name = item["name"] as? String {
                events.append(.toolCall(AIToolCall(id: id, name: name, arguments: item["arguments"] as? String ?? "{}")))
            }
            guard item["type"] as? String == "web_search_call" else { return events }
            if let action = item["action"] as? [String: Any], let query = action["query"] as? String, !query.isEmpty {
                events.append(.searching(query))
            }
            // Pictures it found (`image_result`s, when the request asked for them), once each.
            for result in item["results"] as? [[String: Any]] ?? [] where result["type"] as? String == "image_result" {
                guard let url = result["image_url"] as? String, !url.isEmpty, pictures.insert(url).inserted else { continue }
                events.append(
                    .image(
                        AIImageResult(
                            url: url, thumbnail: result["thumbnail_url"] as? String,
                            source: result["source_website_url"] as? String, caption: result["caption"] as? String)))
            }
            return events
        case "response.output_text.annotation.added":
            guard let annotation = json["annotation"] as? [String: Any],
                annotation["type"] as? String == "url_citation", let url = annotation["url"] as? String,
                cited.insert(url).inserted
            else { return [] }
            return [.citation(AICitation(url: url, title: annotation["title"] as? String))]
        case "response.completed":
            return [.finished]
        case "response.incomplete":
            // Ran out of output tokens (or was cut short): what came is kept.
            return [.finished]
        case "response.failed":
            let response = json["response"] as? [String: Any]
            let error = response?["error"] as? [String: Any]
            throw AIError.rejected((error?["message"] as? String) ?? "")
        case "error":
            let message = (json["message"] as? String) ?? ((json["error"] as? [String: Any])?["message"] as? String) ?? ""
            throw Self.error(code: json["code"] as? String, message: message)
        default:
            return []
        }
    }

    /// A finished item as it goes back: reasoning only with its encrypted content (nothing is stored on OpenAI's side,
    /// so an id alone would point nowhere), a search without its results (they are only for showing).
    static func carried(_ item: [String: Any]) -> String? {
        var kept = item
        switch item["type"] as? String {
        case "reasoning":
            guard item["encrypted_content"] is String else { return nil }
            kept = item.filter { ["type", "id", "summary", "encrypted_content"].contains($0.key) }
        case "web_search_call":
            kept["results"] = nil
        case "message", "function_call":
            break
        default:
            return nil
        }
        guard let data = try? JSONSerialization.data(withJSONObject: kept, options: [.sortedKeys]) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func error(code: String?, message: String) -> AIError {
        switch code {
        case "rate_limit_exceeded", "insufficient_quota": .rateLimited
        case "server_error": .unavailable
        default: .rejected(message)
        }
    }
}

/// Anthropic's Messages API stream: `content_block_delta` with `text_delta` (text), `thinking_delta` (thinking) or
/// `citations_delta` (`web_search_result_location`), a `server_tool_use` block whose input JSON streams in (the search
/// query, read when the block stops), a `tool_use` block (a tool call, once its input is complete), `message_stop`, and
/// `error` events. Every block is put back together as it came (`carried`), to go back with a tool's result.
/// Unchecked: the blocks are JSON values, and a decoder lives in the one task reading its stream.
struct AnthropicStreamDecoder: StreamDecoder, @unchecked Sendable {
    /// Content blocks by index, as they come in; tool input stays text until the block stops.
    private var blocks: [Int: (block: [String: Any], input: String)] = [:]
    private var cited = Set<String>()

    mutating func consume(_ json: [String: Any]) throws -> [AIEvent] {
        switch json["type"] as? String {
        case "content_block_start":
            guard let index = json["index"] as? Int, let block = json["content_block"] as? [String: Any],
                let type = block["type"] as? String
            else { return [] }
            blocks[index] = (block, "")
            switch type {
            case "server_tool_use": return [.searching(nil)]
            case "thinking": return [.reasoningStep]
            default: return []
            }
        case "content_block_delta":
            guard let delta = json["delta"] as? [String: Any], let index = json["index"] as? Int else { return [] }
            switch delta["type"] as? String {
            case "text_delta":
                guard let text = delta["text"] as? String, !text.isEmpty else { return [] }
                append(text, to: "text", in: index)
                return [.text(text)]
            case "thinking_delta":
                guard let thinking = delta["thinking"] as? String, !thinking.isEmpty else { return [] }
                append(thinking, to: "thinking", in: index)
                return [.reasoning(thinking)]
            case "signature_delta":
                if let signature = delta["signature"] as? String { append(signature, to: "signature", in: index) }
                return []
            case "input_json_delta":
                if let partial = delta["partial_json"] as? String { blocks[index]?.input += partial }
                return []
            case "citations_delta":
                guard let citation = delta["citation"] as? [String: Any] else { return [] }
                if var entry = blocks[index] {
                    entry.block["citations"] = (entry.block["citations"] as? [Any] ?? []) + [citation]
                    blocks[index] = entry
                }
                guard citation["type"] as? String == "web_search_result_location", let url = citation["url"] as? String,
                    cited.insert(url).inserted
                else { return [] }
                return [.citation(AICitation(url: url, title: citation["title"] as? String))]
            default:
                return []
            }
        case "content_block_stop":
            guard let index = json["index"] as? Int, let (kept, input) = blocks.removeValue(forKey: index) else { return [] }
            var block = kept
            let type = block["type"] as? String
            var events: [AIEvent] = []
            if type == "server_tool_use" || type == "tool_use" {
                let object = input.isEmpty ? [:] : (RequestBuilders.jsonObject(input) ?? [:])
                block["input"] = object
                if type == "server_tool_use", let query = object["query"] as? String, !query.isEmpty {
                    events.append(.searching(query))
                }
            }
            if let data = try? JSONSerialization.data(withJSONObject: block, options: [.sortedKeys]) {
                events.insert(.carried(.anthropic, String(decoding: data, as: UTF8.self)), at: 0)
            }
            if type == "tool_use", let id = block["id"] as? String, let name = block["name"] as? String {
                events.append(.toolCall(AIToolCall(id: id, name: name, arguments: input.isEmpty ? "{}" : input)))
            }
            return events
        case "message_stop":
            return [.finished]
        case "error":
            let error = json["error"] as? [String: Any]
            throw Self.error(type: error?["type"] as? String, message: (error?["message"] as? String) ?? "")
        default:
            return []
        }
    }

    private mutating func append(_ text: String, to key: String, in index: Int) {
        guard var entry = blocks[index] else { return }
        entry.block[key] = (entry.block[key] as? String ?? "") + text
        blocks[index] = entry
    }

    static func error(type: String?, message: String) -> AIError {
        switch type {
        case "authentication_error", "permission_error": .unauthorized
        case "rate_limit_error": .rateLimited
        case "overloaded_error", "api_error": .unavailable
        default: .rejected(message)
        }
    }
}
