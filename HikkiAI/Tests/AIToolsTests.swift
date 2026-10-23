import Foundation
import Testing

@testable import HikkiAI

private let readTool = AITool(
    name: "read_file", description: "Read a file.",
    parameters: #"{"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}"#)

private func body(_ request: URLRequest) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
}

struct AIToolRequestTests {
    @Test func everyToolsParametersAreAnObjectSchema() throws {
        for tool in WorkspaceFiles.tools + [AIPictures.tool] {
            let object = try #require(
                (try? JSONSerialization.jsonObject(with: Data(tool.parameters.utf8))) as? [String: Any], "\(tool.name)")
            #expect(object["type"] as? String == "object", "\(tool.name)")
            #expect(object["properties"] is [String: Any], "\(tool.name)")
        }
        #expect(Set(WorkspaceFiles.tools.map(\.name)) == Set(WorkspaceFiles.Tool.allCases.map(\.rawValue)))
    }

    @Test func openAIGetsFunctionToolsAndTheCallsResults() throws {
        let call = AIToolCall(id: "call_1", name: "read_file", arguments: #"{"path":"a.md"}"#)
        var request = AIRequest(
            model: AIModelCatalog.gptSol, instructions: "i",
            messages: [
                .user("Read a.md"),
                AIMessage(role: .assistant, parts: [.text("Reading."), .toolCall(call)]),
                AIMessage(role: .user, parts: [.toolResult(callID: "call_1", output: #"{"content":"hi"}"#, isError: false)]),
            ], webSearch: true, reasoning: true)
        request.tools = [readTool]
        var json = try body(RequestBuilders.openAI(request, apiKey: "k"))
        let tools = try #require(json["tools"] as? [[String: Any]])
        #expect(tools.map { $0["type"] as? String } == ["web_search", "function"])
        #expect(tools[1]["name"] as? String == "read_file")
        #expect((tools[1]["parameters"] as? [String: Any])?["required"] as? [String] == ["path"])
        // Nothing is stored at OpenAI: the reasoning before a call comes back encrypted, to be sent with its result.
        #expect(json["include"] as? [String] == ["reasoning.encrypted_content"])
        #expect(json["tool_choice"] == nil)
        let input = try #require(json["input"] as? [[String: Any]])
        #expect(input.count == 4)
        #expect(input[1]["role"] as? String == "assistant")
        #expect(input[2]["type"] as? String == "function_call")
        #expect(input[2]["call_id"] as? String == "call_1")
        #expect(input[2]["arguments"] as? String == #"{"path":"a.md"}"#)
        #expect(input[3]["type"] as? String == "function_call_output")
        #expect(input[3]["output"] as? String == #"{"content":"hi"}"#)

        request.toolsAllowed = false
        json = try body(RequestBuilders.openAI(request, apiKey: "k"))
        #expect(json["tool_choice"] as? String == "none")
    }

    @Test func anAnswerThatCalledToolsGoesBackAsItCame() throws {
        let reasoning = #"{"encrypted_content":"enc","id":"rs_1","summary":[],"type":"reasoning"}"#
        let call = #"{"arguments":"{}","call_id":"call_1","id":"fc_1","name":"read_file","type":"function_call"}"#
        let answer = AIMessage(
            role: .assistant,
            parts: [
                .carried(.openAI, reasoning), .carried(.openAI, call),
                .toolCall(AIToolCall(id: "call_1", name: "read_file", arguments: "{}")),
            ])
        var request = AIRequest(model: AIModelCatalog.gptSol, instructions: "i", messages: [.user("q"), answer])
        request.tools = [readTool]
        let input = try #require(try body(RequestBuilders.openAI(request, apiKey: "k"))["input"] as? [[String: Any]])
        #expect(input.count == 3)
        #expect(input[1]["id"] as? String == "rs_1")
        #expect(input[1]["encrypted_content"] as? String == "enc")
        #expect(input[2]["id"] as? String == "fc_1")
    }

    @Test func anthropicGetsToolsAndResultsFirst() throws {
        let thinking = #"{"signature":"sig","thinking":"Let me look.","type":"thinking"}"#
        let use = #"{"id":"toolu_1","input":{"path":"a.md"},"name":"read_file","type":"tool_use"}"#
        var request = AIRequest(
            model: AIModelCatalog.sonnet, instructions: "i",
            messages: [
                .user("Read a.md"),
                AIMessage(
                    role: .assistant,
                    parts: [
                        .carried(.anthropic, thinking), .carried(.anthropic, use),
                        .toolCall(AIToolCall(id: "toolu_1", name: "read_file", arguments: #"{"path":"a.md"}"#)),
                    ]),
                AIMessage(
                    role: .user,
                    parts: [.text("(note)"), .toolResult(callID: "toolu_1", output: "gone", isError: true)]),
            ], reasoning: true)
        request.tools = [readTool]
        var json = try body(RequestBuilders.anthropic(request, apiKey: "k"))
        let tools = try #require(json["tools"] as? [[String: Any]])
        #expect(tools.count == 1)
        #expect((tools[0]["input_schema"] as? [String: Any])?["type"] as? String == "object")
        let messages = try #require(json["messages"] as? [[String: Any]])
        let said = try #require(messages[1]["content"] as? [[String: Any]])
        #expect(said.map { $0["type"] as? String } == ["thinking", "tool_use"])
        #expect(said[0]["signature"] as? String == "sig")
        #expect((said[1]["input"] as? [String: Any])?["path"] as? String == "a.md")
        let results = try #require(messages[2]["content"] as? [[String: Any]])
        #expect(results.map { $0["type"] as? String } == ["tool_result", "text"])
        #expect(results[0]["tool_use_id"] as? String == "toolu_1")
        #expect(results[0]["is_error"] as? Bool == true)

        request.toolsAllowed = false
        json = try body(RequestBuilders.anthropic(request, apiKey: "k"))
        #expect((json["tool_choice"] as? [String: Any])?["type"] as? String == "none")
    }

    @Test func noToolsNoToolFields() throws {
        let request = AIRequest(model: AIModelCatalog.sonnet, instructions: "i", messages: [.user("q")])
        #expect(try body(RequestBuilders.anthropic(request, apiKey: "k"))["tools"] == nil)
        let openAI = AIRequest(model: AIModelCatalog.gptSol, instructions: "i", messages: [.user("q")], reasoning: true)
        let json = try body(RequestBuilders.openAI(openAI, apiKey: "k"))
        #expect(json["tools"] == nil)
        #expect(json["include"] == nil)
    }
}

struct AIToolStreamTests {
    @Test func openAIsCallsAndWhatGoesBack() throws {
        let lines = [
            #"data: {"type":"response.output_item.done","item":{"type":"reasoning","id":"rs_1","summary":[],"encrypted_content":"enc","status":"completed"}}"#,
            #"data: {"type":"response.output_item.done","item":{"type":"reasoning","id":"rs_2","summary":[]}}"#,
            #"data: {"type":"response.output_item.done","item":{"type":"function_call","id":"fc_1","call_id":"call_1","name":"read_file","arguments":"{\"path\":\"a.md\"}","status":"completed"}}"#,
            #"data: {"type":"response.completed","response":{}}"#,
        ]
        let (events, error) = decode(OpenAIStreamDecoder(), lines, carried: true)
        #expect(error == nil)
        #expect(events.count == 4)
        guard case .carried(.openAI, let reasoning) = events[0] else { return #expect(Bool(false)) }
        let kept = try #require(RequestBuilders.jsonObject(reasoning))
        #expect(kept["encrypted_content"] as? String == "enc")
        #expect(kept["status"] == nil)
        // Reasoning with nothing to send back isn't carried (an id alone points at nothing stored).
        guard case .carried(.openAI, let call) = events[1] else { return #expect(Bool(false)) }
        #expect(RequestBuilders.jsonObject(call)?["call_id"] as? String == "call_1")
        #expect(events[2] == .toolCall(AIToolCall(id: "call_1", name: "read_file", arguments: #"{"path":"a.md"}"#)))
        #expect(events[3] == .finished)
    }

    @Test func anthropicsCallsAndWhatGoesBack() throws {
        let lines = [
            #"data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"","signature":""}}"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Look at a.md."}}"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"sig"}}"#,
            #"data: {"type":"content_block_stop","index":0}"#,
            #"data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}"#,
            #"data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Reading."}}"#,
            #"data: {"type":"content_block_stop","index":1}"#,
            #"data: {"type":"content_block_start","index":2,"content_block":{"type":"tool_use","id":"toolu_1","name":"read_file","input":{}}}"#,
            #"data: {"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"{\"path\":"}}"#,
            #"data: {"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"\"a.md\"}"}}"#,
            #"data: {"type":"content_block_stop","index":2}"#,
            #"data: {"type":"message_stop"}"#,
        ]
        let (events, error) = decode(AnthropicStreamDecoder(), lines, carried: true)
        #expect(error == nil)
        var carried: [[String: Any]] = []
        var calls: [AIToolCall] = []
        for event in events {
            if case .carried(.anthropic, let json) = event, let object = RequestBuilders.jsonObject(json) { carried.append(object) }
            if case .toolCall(let call) = event { calls.append(call) }
        }
        #expect(carried.map { $0["type"] as? String } == ["thinking", "text", "tool_use"])
        #expect(carried[0]["thinking"] as? String == "Look at a.md.")
        #expect(carried[0]["signature"] as? String == "sig")
        #expect(carried[1]["text"] as? String == "Reading.")
        #expect((carried[2]["input"] as? [String: Any])?["path"] as? String == "a.md")
        #expect(calls == [AIToolCall(id: "toolu_1", name: "read_file", arguments: #"{"path":"a.md"}"#)])
        #expect(events.last == .finished)
    }
}

/// Answers each request with the next script of events, keeping the requests it was sent.
private final class ScriptedClient: AIClient, @unchecked Sendable {
    private let lock = NSLock()
    private var scripts: [[AIEvent]]
    private(set) var requests: [AIRequest] = []

    init(_ scripts: [[AIEvent]]) { self.scripts = scripts }

    func stream(_ request: AIRequest) -> AsyncThrowingStream<AIEvent, Error> {
        let events: [AIEvent] = lock.withLock {
            requests.append(request)
            return scripts.isEmpty ? [.text("…"), .finished] : scripts.removeFirst()
        }
        return AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }
}

struct AIToolLoopTests {
    private let call = AIToolCall(id: "c1", name: "read_file", arguments: #"{"path":"a.md"}"#)

    private func collect(_ stream: AsyncThrowingStream<AIEvent, Error>) async throws -> [AIEvent] {
        var events: [AIEvent] = []
        for try await event in stream { events.append(event) }
        return events
    }

    @Test func aCallRunsAndTheModelGoesOnWithItsResult() async throws {
        let client = ScriptedClient([
            [.text("Let me look."), .carried(.anthropic, #"{"type":"text"}"#), .toolCall(call), .finished],
            [.text("It says hi."), .finished],
        ])
        var request = AIRequest(model: AIModelCatalog.sonnet, instructions: "i", messages: [.user("What's in a.md?")])
        request.tools = [readTool]
        let events = try await collect(AIToolLoop.run(request, client: client) { _ in AIToolOutput("hi") })
        #expect(
            events == [
                .text("Let me look."), .toolCall(call), .toolResult(call, AIToolOutput("hi")), .text("\n\n"),
                .text("It says hi."), .finished,
            ])
        #expect(client.requests.count == 2)
        let second = client.requests[1].messages
        #expect(second.count == 3)
        #expect(second[1].role == .assistant)
        #expect(second[1].parts == [.text("Let me look."), .carried(.anthropic, #"{"type":"text"}"#), .toolCall(call)])
        #expect(second[2].parts == [.toolResult(callID: "c1", output: "hi", isError: false)])
    }

    @Test func noCallsIsOneRound() async throws {
        let client = ScriptedClient([[.text("Hello."), .finished]])
        let events = try await collect(
            AIToolLoop.run(AIRequest(model: AIModelCatalog.sonnet, instructions: "i", messages: [.user("hi")]), client: client) {
                _ in AIToolOutput("never")
            })
        #expect(events == [.text("Hello."), .finished])
        #expect(client.requests.count == 1)
    }

    @Test func theLastRoundMustAnswerInWords() async throws {
        let client = ScriptedClient(Array(repeating: [.toolCall(call), .finished], count: AIToolLoop.maxRounds + 2))
        var request = AIRequest(model: AIModelCatalog.sonnet, instructions: "i", messages: [.user("loop")])
        request.tools = [readTool]
        let events = try await collect(AIToolLoop.run(request, client: client) { _ in AIToolOutput("again") })
        #expect(client.requests.count == AIToolLoop.maxRounds)
        #expect(client.requests.last?.toolsAllowed == false)
        #expect(client.requests.dropLast().allSatisfy { $0.toolsAllowed })
        #expect(events.last == .finished)
    }
}
