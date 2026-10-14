import Testing

@testable import HikkiAI

struct AIModelCatalogTests {
    @Test func autoPicksABalancedModelFromTheProvidersWithAKey() {
        #expect(AIModelCatalog.auto(available: [.anthropic, .openAI]) == AIModelCatalog.sonnet)
        #expect(AIModelCatalog.auto(available: [.openAI]) == AIModelCatalog.gptSol)
        #expect(AIModelCatalog.auto(available: []) == nil)
    }

    @Test func aChosenModelIsUsedOnlyWhenItsProviderHasAKey() {
        #expect(AIModelCatalog.resolve("claude-opus-5-5", available: [.anthropic]) == AIModelCatalog.opus)
        // No Anthropic key: the choice can't run, Auto's pick does.
        #expect(AIModelCatalog.resolve("claude-opus-5-5", available: [.openAI]) == AIModelCatalog.gptSol)
        #expect(AIModelCatalog.resolve("auto", available: [.anthropic]) == AIModelCatalog.sonnet)
        #expect(AIModelCatalog.resolve("gone-model", available: [.anthropic]) == AIModelCatalog.sonnet)
        #expect(AIModelCatalog.resolve(nil, available: []) == nil)
    }

    @Test func everyModelIsListedOnceWithAName() {
        let ids = AIModelCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(AIModelCatalog.opus.displayName == "Opus 5.5")
        #expect(AIModelCatalog.gptSol.displayName == "GPT-6.1 Sol")
    }
}
