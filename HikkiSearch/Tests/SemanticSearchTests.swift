import Foundation
import Testing

@testable import HikkiSearch

struct ChunkerTests {
    @Test func gathersLinesUpToTheLimitAndStartsEachPassageWithTheTitle() {
        let chunks = Chunker.chunks(title: "Trip", text: "aaaa\nbbbb\n\ncccc", limit: 9)
        #expect(chunks.map(\.text) == ["Trip\naaaa\nbbbb", "Trip\ncccc"])
        #expect(chunks.map(\.ordinal) == [0, 1])
    }

    @Test func cutsALongLineAtSentenceEnds() {
        let pieces = Chunker.pieces(of: "一二三。四五六。七八九十", limit: 5)
        #expect(pieces == ["一二三。", "四五六。", "七八九十"])
        #expect(Chunker.pieces(of: String(repeating: "x", count: 12), limit: 5) == ["xxxxx", "xxxxx", "xx"])
    }

    @Test func aPageWithOnlyATitleStillGetsAPassage() {
        #expect(Chunker.chunks(title: "Ideas", text: "").map(\.text) == ["Ideas"])
        #expect(Chunker.chunks(title: "", text: "").isEmpty)
    }

    @Test func sameTextSameHash() {
        let a = Chunker.chunks(title: "T", text: "hello")
        let b = Chunker.chunks(title: "T", text: "hello")
        let c = Chunker.chunks(title: "T", text: "hello!")
        #expect(a[0].hash == b[0].hash)
        #expect(a[0].hash != c[0].hash)
    }
}

struct SemanticIndexTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func unit(_ values: Float...) -> [Float] { OpenAICompatibleEmbeddings.normalized(values) }

    private func store(_ index: SearchIndex, _ id: String, _ title: String, _ vector: [Float], text: String = "body")
        throws
    {
        try index.index([SearchDocument(id: id, title: title, text: text, updatedAt: t0)])
        let chunk = Chunker.chunks(title: title, text: text)[0]
        try index.storeEmbeddings(pageId: id, updatedAt: t0, passages: [(chunk, vector)])
    }

    @Test func aNewModelDropsTheOldVectors() throws {
        let index = try SearchIndex.inMemory()
        #expect(try index.useEmbeddingModel("ollama|e5"))
        try store(index, "a", "Cats", unit(1, 0))
        #expect(!(try index.useEmbeddingModel("ollama|e5")))
        #expect(index.embeddedCount == 1)
        #expect(try index.useEmbeddingModel("openai|small"))
        #expect(index.embeddedCount == 0)
        #expect(try index.embeddingModel() == "openai|small")
    }

    @Test func findsTheClosestPassageOfEachPage() throws {
        let index = try SearchIndex.inMemory()
        try store(index, "cats", "Cats", unit(1, 0.1))
        try store(index, "dogs", "Dogs", unit(0.7, 0.7))
        try store(index, "tax", "Tax", unit(0, 1))
        let matches = try index.semanticMatches(unit(1, 0), limit: 2)
        #expect(matches.map(\.pageId) == ["cats", "dogs"])
        #expect(matches[0].similarity > 0.99)
        #expect(try index.passageVectors(of: "cats").count == 1)
    }

    @Test func wordMatchesComeFirstThenPagesRelatedOnlyByMeaning() throws {
        let index = try SearchIndex.inMemory()
        try store(index, "kitten", "Kitten care", unit(1, 0), text: "feeding a young cat")
        try store(index, "word", "Cat words", unit(0, 1), text: "the word cat in other languages")
        try store(index, "far", "Taxes", unit(0, 1), text: "receipts")
        try store(index, "far2", "Trains", unit(0, 1), text: "timetables")
        try store(index, "far3", "Bread", unit(0, 1), text: "flour")
        // Word matches keep their order (the title match first) however close in meaning the others are.
        let hits = try index.search("cat", queryVector: unit(1, 0.05))
        #expect(hits.map(\.id) == ["word", "kitten"])
        #expect(hits.allSatisfy { !$0.related })

        let byMeaning = try index.search("小猫", queryVector: unit(1, 0.05))
        #expect(byMeaning.map(\.id) == ["kitten"])
        #expect(byMeaning[0].related)
        #expect(byMeaning[0].snippet == "feeding a young cat")
        #expect(byMeaning[0].passage == "feeding a young cat")
        // Without a vector it is the word search alone.
        #expect(try index.search("小猫", queryVector: nil).isEmpty)
    }

    /// A unit vector whose similarity to (1, 0) is `cosine`.
    private func at(_ cosine: Float) -> [Float] { [cosine, (1 - cosine * cosine).squareRoot()] }

    @Test func onlyPagesThatStandOutAreRelated() throws {
        // Similarities in a narrow band, as e5 gives them: the clear winner is related, the pack isn't.
        let index = try SearchIndex.inMemory()
        for (id, cosine) in [("cat", 0.95), ("b", 0.80), ("c", 0.79), ("d", 0.78), ("e", 0.77)] as [(String, Float)] {
            try store(index, id, id.uppercased(), at(cosine), text: "x")
        }
        #expect(try index.search("宠物", queryVector: [1, 0]).map(\.id) == ["cat"])

        let flat = try SearchIndex.inMemory()
        for (id, cosine) in [("a", 0.80), ("b", 0.795), ("c", 0.79), ("d", 0.79), ("e", 0.785)] as [(String, Float)] {
            try store(flat, id, id.uppercased(), at(cosine), text: "x")
        }
        #expect(try flat.search("预算", queryVector: [1, 0]).isEmpty)
    }

    @Test func emptyPagesAreNeverRelated() throws {
        // A model that gives short texts one vector (qllama's e5 build did: "parents" = "Q2" = "2024") made every
        // empty page "related" to every one-word query.
        let index = try SearchIndex.inMemory()
        for id in ["q1", "q2", "2024"] { try store(index, id, id, at(1), text: "") }
        for (id, cosine) in [("a", 0.5), ("b", 0.49), ("c", 0.48), ("d", 0.47), ("e", 0.46)] as [(String, Float)] {
            try store(index, id, id.uppercased(), at(cosine), text: "notes")
        }
        #expect(try index.semanticMatches([1, 0], limit: .max).map(\.pageId).sorted() == ["a", "b", "c", "d", "e"])
        #expect(try index.search("parents", queryVector: [1, 0]).isEmpty)
    }

    @Test func tooFewPagesOrAFragmentOfAWordFindNothingByMeaning() throws {
        let index = try SearchIndex.inMemory()
        for (id, cosine) in [("a", 0.95), ("b", 0.2), ("c", 0.1)] as [(String, Float)] {
            try store(index, id, id.uppercased(), at(cosine), text: "x")
        }
        #expect(try index.search("宠物", queryVector: [1, 0]).isEmpty)
        #expect(!SearchIndex.meansSomething("be"))
        #expect(!SearchIndex.meansSomething("  "))
        #expect(SearchIndex.meansSomething("cat"))
        #expect(SearchIndex.meansSomething("親"))
    }

    @Test func aRelatedHitShowsItsClosestSentence() async {
        let passage = "練習B\n数字\nすみません、あちらに止めてください。\n￼\nイーさんのご家族は。両親と兄が一人います。"
        #expect(Chunker.sentences(of: passage) == ["練習B", "すみません、あちらに止めてください。", "イーさんのご家族は。", "両親と兄が一人います。"])
        let sentence = await SearchIndex.closestSentence(in: passage, to: [1, 0]) { sentences in
            sentences.map { $0.contains("両親") ? [1, 0] : [0, 1] }
        }
        #expect(sentence == "両親と兄が一人います。")
        // One sentence, or a failing model: the excerpt stays as it was.
        #expect(await SearchIndex.closestSentence(in: "一つだけ。", to: [1, 0]) { $0.map { _ in [1, 0] } } == nil)
        #expect(await SearchIndex.closestSentence(in: passage, to: [1, 0]) { _ in throw EmbeddingError.unreachable } == nil)
    }

    @Test func removingAPageForgetsItsPassages() throws {
        let index = try SearchIndex.inMemory()
        try store(index, "a", "A", unit(1, 0))
        try index.remove(["a"])
        #expect(index.embeddedCount == 0)
        #expect(try index.semanticMatches(unit(1, 0), limit: 5).isEmpty)
        #expect(try index.embeddingStamps().isEmpty)
    }
}

/// Answers the provider's requests from a table (path → status, body) and records them.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responses: [String: (Int, String)] = [:]
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var recorded = request
        if let stream = request.httpBodyStream {
            stream.open()
            var body = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                body.append(buffer, count: read)
            }
            stream.close()
            recorded.httpBody = body
        }
        Self.requests.append(recorded)
        guard let (status, body) = Self.responses[request.url?.path() ?? ""] else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct EmbeddingProviderTests {
    private func provider(model: String = "qllama/multilingual-e5-small", key: String? = nil)
        -> OpenAICompatibleEmbeddings
    {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return OpenAICompatibleEmbeddings(
            baseURL: URL(string: "http://localhost:11434/v1")!, model: model, apiKey: key,
            session: URLSession(configuration: configuration))
    }

    @Test func sendsPrefixedTextsAndReturnsUnitVectorsInOrder() async throws {
        StubProtocol.requests = []
        StubProtocol.responses = [
            "/v1/embeddings": (200, #"{"data":[{"index":1,"embedding":[0,2]},{"index":0,"embedding":[3,4]}]}"#)
        ]
        let vectors = try await provider().embed(["猫", "犬"], kind: .passage)
        #expect(vectors == [[0.6, 0.8], [0, 1]])
        let body = try #require(StubProtocol.requests.first?.httpBody)
        let sent = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        #expect(sent["model"] as? String == "qllama/multilingual-e5-small")
        #expect(sent["input"] as? [String] == ["passage: 猫", "passage: 犬"])
        #expect(StubProtocol.requests.first?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func aQueryGetsTheQueryPrefixAndAKeyGoesAsBearer() async throws {
        StubProtocol.requests = []
        StubProtocol.responses = ["/v1/embeddings": (200, #"{"data":[{"embedding":[1,0]}]}"#)]
        _ = try await provider(key: "sk-test").embed(["cats"], kind: .query)
        let request = try #require(StubProtocol.requests.first)
        let sent = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        #expect(sent["input"] as? [String] == ["query: cats"])
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
    }

    @Test func qwen3ReadsAnInstructionBeforeAQuery() {
        let prefixes = EmbeddingPrefixes.forModel("qwen3-embedding:0.6b")
        #expect(prefixes.query.hasPrefix("Instruct: ") && prefixes.query.hasSuffix("\nQuery: "))
        #expect(prefixes.passage.isEmpty)
        #expect(EmbeddingPrefixes.forModel("bge-m3") == .none)
    }

    @Test func modelsWithoutPrefixesGetTheTextAsIs() {
        #expect(EmbeddingPrefixes.forModel("text-embedding-3-small") == .none)
        #expect(EmbeddingPrefixes.forModel("nomic-embed-text").query == "search_query: ")
    }

    @Test func reportsWhatWentWrong() async {
        StubProtocol.responses = ["/v1/embeddings": (404, #"{"error":"model not found"}"#)]
        await #expect(throws: EmbeddingError.http(404)) { try await provider().embed(["x"], kind: .query) }
        StubProtocol.responses = ["/v1/embeddings": (200, #"{"nope":true}"#)]
        await #expect(throws: EmbeddingError.badResponse) { try await provider().embed(["x"], kind: .query) }
        StubProtocol.responses = [:]
        await #expect(throws: EmbeddingError.unreachable) { try await provider().embed(["x"], kind: .query) }
    }

    @Test func listsTheEndpointsModels() async throws {
        StubProtocol.responses = [
            "/v1/models": (200, #"{"object":"list","data":[{"id":"qllama/multilingual-e5-small:latest"},{"id":"bge-m3"}]}"#)
        ]
        #expect(try await provider().models() == ["bge-m3", "qllama/multilingual-e5-small:latest"])
    }

    @Test func aKeyIsNeverSentInTheClearToAnotherMachine() async throws {
        let remote = OpenAICompatibleEmbeddings(
            baseURL: URL(string: "http://192.168.1.20:11434/v1")!, model: "m", apiKey: "sk-secret")
        #expect(remote.apiKey == nil)
        #expect(
            OpenAICompatibleEmbeddings(baseURL: URL(string: "https://api.openai.com/v1")!, model: "m", apiKey: "sk")
                .apiKey == "sk")
        #expect(
            OpenAICompatibleEmbeddings(baseURL: URL(string: "http://localhost:11434/v1")!, model: "m", apiKey: "k")
                .apiKey == "k")
    }

    @Test func aKeyBelongsToItsOrigin() {
        let origin = { OpenAICompatibleEmbeddings.origin(of: URL(string: $0)!) }
        #expect(origin("https://API.openai.com/v1") == "https://api.openai.com")
        #expect(origin("https://api.openai.com/other") == "https://api.openai.com")
        #expect(origin("http://localhost:11434/v1") == "http://localhost:11434")
        // A half-typed host is another origin, so it never gets the key.
        #expect(origin("https://api.op") != origin("https://api.openai.com/v1"))
        #expect(origin("http://localhost:1234/v1") != origin("http://localhost:11434/v1"))
    }

    @Test func loopbackSkipsTheProxy() {
        let local = OpenAICompatibleEmbeddings.makeSession(for: URL(string: "http://localhost:11434/v1")!)
        #expect(local.configuration.connectionProxyDictionary?.isEmpty == true)
        let remote = OpenAICompatibleEmbeddings.makeSession(for: URL(string: "https://api.openai.com/v1")!)
        #expect(remote.configuration.connectionProxyDictionary == nil)
    }
}
