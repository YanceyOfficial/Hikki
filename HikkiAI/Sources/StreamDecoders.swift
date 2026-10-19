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
/// `web_search_call` item (the query), `response.output_text.annotation.added` (`url_citation`), `response.completed`,
/// and `response.failed` / `error`.
struct OpenAIStreamDecoder: StreamDecoder {
    private var cited = Set<String>()

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
            guard let item = json["item"] as? [String: Any], item["type"] as? String == "web_search_call",
                let action = item["action"] as? [String: Any], let query = action["query"] as? String, !query.isEmpty
            else { return [] }
            return [.searching(query)]
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

    static func error(code: String?, message: String) -> AIError {
        switch code {
        case "rate_limit_exceeded", "insufficient_quota": .rateLimited
        case "server_error": .unavailable
        default: .rejected(message)
        }
    }
}

/// Anthropic's Messages API stream: `content_block_delta` with `text_delta` (text), `thinking_delta` (thinking) or
/// `citations_delta`
/// (`web_search_result_location`), a `server_tool_use` block whose input JSON streams in (the search query, read when
/// the block stops), `message_stop`, and `error` events.
struct AnthropicStreamDecoder: StreamDecoder {
    /// Content blocks by index: their type, and the tool input received so far.
    private var blocks: [Int: (type: String, input: String)] = [:]
    private var cited = Set<String>()

    mutating func consume(_ json: [String: Any]) throws -> [AIEvent] {
        switch json["type"] as? String {
        case "content_block_start":
            guard let index = json["index"] as? Int, let block = json["content_block"] as? [String: Any],
                let type = block["type"] as? String
            else { return [] }
            blocks[index] = (type, "")
            switch type {
            case "server_tool_use": return [.searching(nil)]
            case "thinking": return [.reasoningStep]
            default: return []
            }
        case "content_block_delta":
            guard let delta = json["delta"] as? [String: Any] else { return [] }
            switch delta["type"] as? String {
            case "text_delta":
                guard let text = delta["text"] as? String, !text.isEmpty else { return [] }
                return [.text(text)]
            case "thinking_delta":
                guard let thinking = delta["thinking"] as? String, !thinking.isEmpty else { return [] }
                return [.reasoning(thinking)]
            case "input_json_delta":
                if let index = json["index"] as? Int, let partial = delta["partial_json"] as? String {
                    blocks[index]?.input += partial
                }
                return []
            case "citations_delta":
                guard let citation = delta["citation"] as? [String: Any],
                    citation["type"] as? String == "web_search_result_location", let url = citation["url"] as? String,
                    cited.insert(url).inserted
                else { return [] }
                return [.citation(AICitation(url: url, title: citation["title"] as? String))]
            default:
                return []
            }
        case "content_block_stop":
            guard let index = json["index"] as? Int, let block = blocks.removeValue(forKey: index),
                block.type == "server_tool_use", let data = block.input.data(using: .utf8),
                let input = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                let query = input["query"] as? String, !query.isEmpty
            else { return [] }
            return [.searching(query)]
        case "message_stop":
            return [.finished]
        case "error":
            let error = json["error"] as? [String: Any]
            throw Self.error(type: error?["type"] as? String, message: (error?["message"] as? String) ?? "")
        default:
            return []
        }
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
