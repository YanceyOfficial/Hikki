import Foundation
import Testing

@testable import HikkiAI

struct AIEndpointTests {
    @Test func blankMeansTheProvidersOwnAPI() {
        #expect(AIEndpoint.base("", for: .openAI)?.absoluteString == "https://api.openai.com/v1")
        #expect(AIEndpoint.base("  ", for: .anthropic)?.absoluteString == "https://api.anthropic.com")
        #expect(RequestBuilders.openAIURL.absoluteString == "https://api.openai.com/v1/responses")
        #expect(RequestBuilders.anthropicURL.absoluteString == "https://api.anthropic.com/v1/messages")
    }

    @Test func aCustomBaseFollowsEachSDKsConvention() throws {
        let openAI = try #require(AIEndpoint.base("https://gateway.example.com/openai/v1/", for: .openAI))
        #expect(AIEndpoint.requestURL(.openAI, base: openAI).absoluteString == "https://gateway.example.com/openai/v1/responses")
        let anthropic = try #require(AIEndpoint.base("https://proxy.example.com", for: .anthropic))
        #expect(AIEndpoint.requestURL(.anthropic, base: anthropic).absoluteString == "https://proxy.example.com/v1/messages")
    }

    @Test func refusesWhatIsntAnHTTPURL() {
        #expect(AIEndpoint.base("api.openai.com", for: .openAI) == nil)
        #expect(AIEndpoint.base("ftp://x.example.com", for: .openAI) == nil)
        #expect(AIEndpoint.base("https://x.example.com/v1?key=1", for: .openAI) == nil)
    }

    @Test func aKeyGoesOnlyOverHTTPSOrToThisMachine() throws {
        #expect(AIEndpoint.mayCarryKey(try #require(URL(string: "https://proxy.example.com"))))
        #expect(AIEndpoint.mayCarryKey(try #require(URL(string: "http://localhost:4000"))))
        #expect(!AIEndpoint.mayCarryKey(try #require(URL(string: "http://proxy.example.com"))))
        #expect(throws: AIError.badBaseURL(.openAI)) {
            try AIClients.client(
                for: AIModelCatalog.gptSol, keys: [.openAI: "sk"],
                bases: [.openAI: try #require(URL(string: "http://proxy.example.com/v1"))])
        }
        #expect(AIEndpoint.origin(of: try #require(URL(string: "https://Proxy.example.com:8443/v1"))) == "https://proxy.example.com:8443")
    }

    @Test func eachAddressHasItsOwnKey() {
        #expect(AIEndpoint.keyAccount(.anthropic, base: AIEndpoint.base("", for: .anthropic)) == "ai.key.anthropic")
        // Another path on the provider's own host is still its own API.
        #expect(AIEndpoint.keyAccount(.openAI, base: AIEndpoint.base("https://api.openai.com/v2", for: .openAI)) == "ai.key.openAI")
        #expect(
            AIEndpoint.keyAccount(.openAI, base: AIEndpoint.base("https://proxy.example.com/v1", for: .openAI))
                == "ai.key.openAI|https://proxy.example.com")
        #expect(AIEndpoint.keyAccount(.openAI, base: nil) == nil)
    }

    @Test func theRequestGoesToTheCustomURL() throws {
        let request = AIRequest(model: AIModelCatalog.sonnet, instructions: "", messages: [.user("hi")])
        let url = try #require(URL(string: "https://proxy.example.com/v1/messages"))
        #expect(try RequestBuilders.anthropic(request, apiKey: "k", url: url).url == url)
    }
}
