import Foundation
import Testing

@testable import HikkiAI

/// Runs `data:` lines through a decoder (skipping what `sseJSON` skips), collecting events or the error thrown.
private func decode<D: StreamDecoder>(_ decoder: D, _ lines: [String]) -> (events: [AIEvent], error: Error?) {
    var decoder = decoder
    var events: [AIEvent] = []
    for line in lines {
        guard let json = sseJSON(line) else { continue }
        do { events += try decoder.consume(json) } catch { return (events, error) }
    }
    return (events, nil)
}

struct OpenAIStreamDecoderTests {
    @Test func textSearchesAndCitationsInOrder() {
        let lines = [
            #"event: response.created"#,
            #"data: {"type":"response.created","response":{"id":"r1"}}"#,
            #"data: {"type":"response.web_search_call.in_progress","item_id":"ws1"}"#,
            #"data: {"type":"response.output_item.done","item":{"type":"web_search_call","id":"ws1","action":{"type":"search","query":"kyoto autumn leaves 2026"}}}"#,
            #"data: {"type":"response.output_text.delta","delta":"Peak is "}"#,
            #"data: {"type":"response.output_text.delta","delta":"mid-November."}"#,
            #"data: {"type":"response.output_text.annotation.added","annotation":{"type":"url_citation","url":"https://kyoto.travel/autumn","title":"Autumn in Kyoto","start_index":0,"end_index":9}}"#,
            #"data: {"type":"response.output_text.annotation.added","annotation":{"type":"url_citation","url":"https://kyoto.travel/autumn","title":"Autumn in Kyoto"}}"#,
            #"data: {"type":"response.something.new","x":1}"#,
            ": keep-alive",
            #"data: {"type":"response.completed","response":{"status":"completed"}}"#,
        ]
        let (events, error) = decode(OpenAIStreamDecoder(), lines)
        #expect(error == nil)
        #expect(
            events == [
                .searching(nil), .searching("kyoto autumn leaves 2026"), .text("Peak is "), .text("mid-November."),
                .citation(AICitation(url: "https://kyoto.travel/autumn", title: "Autumn in Kyoto")), .finished,
            ])
    }

    @Test func failuresThrowInTheUsersTerms() {
        let failed = decode(
            OpenAIStreamDecoder(),
            [#"data: {"type":"response.failed","response":{"error":{"code":"server_error","message":"The model is unavailable."}}}"#])
        #expect(failed.error as? AIError == .rejected("The model is unavailable."))
        let limited = decode(
            OpenAIStreamDecoder(), [#"data: {"type":"error","code":"rate_limit_exceeded","message":"Slow down"}"#])
        #expect(limited.error as? AIError == .rateLimited)
    }

    @Test func malformedLinesAreSkippedNotFatal() {
        let (events, error) = decode(
            OpenAIStreamDecoder(),
            ["data: [DONE]", "data: {not json", #"data: {"type":"response.output_text.delta"}"#, "garbage"])
        #expect(error == nil)
        #expect(events.isEmpty)
    }
}

struct AnthropicStreamDecoderTests {
    @Test func textTheSearchQueryAndCitations() {
        let lines = [
            #"event: message_start"#,
            #"data: {"type":"message_start","message":{"id":"m1","role":"assistant"}}"#,
            #"data: {"type":"content_block_start","index":0,"content_block":{"type":"server_tool_use","id":"t1","name":"web_search","input":{}}}"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"query\": \"京都 紅"}}"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"葉\"}"}}"#,
            #"data: {"type":"content_block_stop","index":0}"#,
            #"data: {"type":"content_block_start","index":1,"content_block":{"type":"web_search_tool_result","tool_use_id":"t1","content":[{"type":"web_search_result","url":"https://example.jp/momiji","title":"紅葉情報"}]}}"#,
            #"data: {"type":"content_block_stop","index":1}"#,
            #"data: {"type":"content_block_start","index":2,"content_block":{"type":"text","text":""}}"#,
            #"data: {"type":"content_block_delta","index":2,"delta":{"type":"text_delta","text":"見頃は11月中旬です。"}}"#,
            #"data: {"type":"content_block_delta","index":2,"delta":{"type":"citations_delta","citation":{"type":"web_search_result_location","url":"https://example.jp/momiji","title":"紅葉情報","cited_text":"…"}}}"#,
            #"data: {"type":"content_block_stop","index":2}"#,
            #"data: {"type":"ping"}"#,
            #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#,
            #"data: {"type":"message_stop"}"#,
        ]
        let (events, error) = decode(AnthropicStreamDecoder(), lines)
        #expect(error == nil)
        #expect(
            events == [
                .searching(nil), .searching("京都 紅葉"), .text("見頃は11月中旬です。"),
                .citation(AICitation(url: "https://example.jp/momiji", title: "紅葉情報")), .finished,
            ])
    }

    @Test func errorEventsMapToTheirKind() {
        let overloaded = decode(
            AnthropicStreamDecoder(), [#"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#])
        #expect(overloaded.error as? AIError == .unavailable)
        let invalid = decode(
            AnthropicStreamDecoder(),
            [#"data: {"type":"error","error":{"type":"invalid_request_error","message":"max_tokens too large"}}"#])
        #expect(invalid.error as? AIError == .rejected("max_tokens too large"))
    }

    @Test func aBrokenToolInputIsIgnored() {
        let (events, error) = decode(
            AnthropicStreamDecoder(),
            [
                #"data: {"type":"content_block_start","index":0,"content_block":{"type":"server_tool_use","input":{}}}"#,
                #"data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"query\": "}}"#,
                #"data: {"type":"content_block_stop","index":0}"#,
            ])
        #expect(error == nil)
        #expect(events == [.searching(nil)])
    }
}

struct RequestBuilderTests {
    private let request = AIRequest(
        model: AIModelCatalog.sonnet, instructions: "Fix errors.",
        messages: [
            AIMessage(role: .user, parts: [.text("hello"), .image(Data([1, 2, 3]), mimeType: "image/png")]),
            .assistant("hi"),
        ],
        webSearch: true, maxOutputTokens: 1000)

    private func body(_ request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func anthropicMessages() throws {
        let http = try RequestBuilders.anthropic(request, apiKey: "sk-ant")
        #expect(http.url == RequestBuilders.anthropicURL)
        #expect(http.value(forHTTPHeaderField: "x-api-key") == "sk-ant")
        #expect(http.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        let json = try body(http)
        #expect(json["model"] as? String == "claude-sonnet-5-5")
        #expect(json["system"] as? String == "Fix errors.")
        #expect(json["max_tokens"] as? Int == 1000)
        #expect(json["stream"] as? Bool == true)
        let messages = try #require(json["messages"] as? [[String: Any]])
        let parts = try #require(messages[0]["content"] as? [[String: Any]])
        #expect(parts[1]["type"] as? String == "image")
        #expect((parts[1]["source"] as? [String: Any])?["data"] as? String == "AQID")
        #expect((json["tools"] as? [[String: Any]])?.first?["type"] as? String == "web_search_20250305")
    }

    @Test func openAIResponses() throws {
        var openAI = request
        openAI.model = AIModelCatalog.gptSol
        openAI.webSearch = false
        let http = try RequestBuilders.openAI(openAI, apiKey: "sk-oa")
        #expect(http.value(forHTTPHeaderField: "Authorization") == "Bearer sk-oa")
        let json = try body(http)
        #expect(json["model"] as? String == "gpt-6.1-sol")
        #expect(json["instructions"] as? String == "Fix errors.")
        #expect(json["store"] as? Bool == false)
        #expect(json["tools"] == nil)
        let input = try #require(json["input"] as? [[String: Any]])
        let user = try #require(input[0]["content"] as? [[String: Any]])
        #expect(user[0]["type"] as? String == "input_text")
        #expect(user[1]["image_url"] as? String == "data:image/png;base64,AQID")
        let assistant = try #require(input[1]["content"] as? [[String: Any]])
        #expect(assistant[0]["type"] as? String == "output_text")
    }
}

struct HTTPErrorTests {
    @Test func statusesAndBodies() {
        #expect(HTTPErrors.map(status: 401, body: Data()) == .unauthorized)
        #expect(HTTPErrors.map(status: 429, body: Data()) == .rateLimited)
        #expect(HTTPErrors.map(status: 529, body: Data()) == .unavailable)
        let body = Data(#"{"type":"error","error":{"type":"invalid_request_error","message":"model not found"}}"#.utf8)
        #expect(HTTPErrors.map(status: 404, body: body) == .rejected("model not found"))
        #expect(HTTPErrors.map(URLError(.notConnectedToInternet)) as? AIError == .offline)
        #expect(HTTPErrors.map(URLError(.cancelled)) as? AIError == .cancelled)
    }

    @Test func noKeyNoClient() {
        #expect(throws: AIError.missingKey(.anthropic)) {
            try AIClients.client(for: AIModelCatalog.sonnet, keys: [.openAI: "k"])
        }
    }
}

/// Serves a canned response (status + body) to every request.
final class CannedProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = ""

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized)
struct StreamingClientTests {
    private var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CannedProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func collect(_ model: AIModel) async -> (events: [AIEvent], error: Error?) {
        var events: [AIEvent] = []
        do {
            let client = try AIClients.client(for: model, keys: [.anthropic: "a", .openAI: "o"], session: session)
            for try await event in client.stream(AIRequest(model: model, instructions: "", messages: [.user("hi")])) {
                events.append(event)
            }
            return (events, nil)
        } catch {
            return (events, error)
        }
    }

    @Test func streamsAnAnswer() async {
        CannedProtocol.status = 200
        CannedProtocol.body = """
            event: content_block_delta
            data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

            event: message_stop
            data: {"type":"message_stop"}

            """
        let (events, error) = await collect(AIModelCatalog.sonnet)
        #expect(error == nil)
        #expect(events == [.text("Hello"), .finished])
    }

    @Test func endsEvenWithoutAFinishEvent() async {
        CannedProtocol.status = 200
        CannedProtocol.body = #"data: {"type":"response.output_text.delta","delta":"Hi"}"# + "\n"
        let (events, _) = await collect(AIModelCatalog.gptSol)
        #expect(events == [.text("Hi"), .finished])
    }

    @Test func anHTTPErrorIsReadAndMapped() async {
        CannedProtocol.status = 400
        CannedProtocol.body = #"{"error":{"message":"Unknown model"}}"#
        let (_, error) = await collect(AIModelCatalog.gptSol)
        #expect(error as? AIError == .rejected("Unknown model"))
    }
}

/// Answers every request to the configured host with a 307 to another host, and counts what reaches that one.
final class RedirectingProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var reachedOtherHost = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        if url.host() == "elsewhere.example" {
            Self.reachedOtherHost += 1
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("data: {\"type\":\"message_stop\"}\n\n".utf8))
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        var redirect = request
        redirect.url = URL(string: "https://elsewhere.example/v1/messages")
        let response = HTTPURLResponse(
            url: url, statusCode: 307, httpVersion: nil, headerFields: ["Location": redirect.url!.absoluteString])!
        client?.urlProtocol(self, wasRedirectedTo: redirect, redirectResponse: response)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized)
struct RedirectTests {
    @Test(.timeLimit(.minutes(1))) func aKeyNeverFollowsARedirectToAnotherHost() async {
        RedirectingProtocol.reachedOtherHost = 0
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RedirectingProtocol.self]
        var failed = false
        do {
            let client = try AIClients.client(
                for: AIModelCatalog.sonnet, keys: [.anthropic: "secret"], session: AIClients.session(configuration))
            for try await _ in client.stream(AIRequest(model: AIModelCatalog.sonnet, instructions: "", messages: [.user("hi")])) {}
        } catch {
            failed = true
        }
        #expect(RedirectingProtocol.reachedOtherHost == 0)
        #expect(failed)
    }
}
