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

    @Test func withoutFavoritesTheMenuIsRecommendedThenOthers() {
        let sections = AIModelCatalog.sections(favorites: AIModelFavorites())
        #expect(sections.map(\.kind) == [.recommended, .other])
        #expect(sections[0].models == AIModelCatalog.recommended)
        #expect(sections[1].models == AIModelCatalog.others)
    }

    @Test func starredModelsComeFirstInTheOrderStarredAndOnlyOnce() {
        var favorites = AIModelFavorites()
        favorites.toggle(AIModelCatalog.haiku.id)
        favorites.toggle(AIModelCatalog.opus.id)
        let sections = AIModelCatalog.sections(favorites: favorites)
        #expect(sections.map(\.kind) == [.favorites, .recommended, .other])
        #expect(sections[0].models == [AIModelCatalog.haiku, AIModelCatalog.opus])
        #expect(sections[1].models == [AIModelCatalog.sonnet, AIModelCatalog.gptSol])
        #expect(sections[2].models == [AIModelCatalog.gptAstra])
        // Every model exactly once across the groups.
        #expect(sections.flatMap(\.models).count == AIModelCatalog.all.count)
        // Unstarring puts it back in its own group.
        favorites.toggle(AIModelCatalog.haiku.id)
        #expect(AIModelCatalog.sections(favorites: favorites)[0].models == [AIModelCatalog.opus])
    }

    @Test func aGroupThatEndsUpEmptyIsLeftOut() {
        let favorites = AIModelFavorites(ids: AIModelCatalog.others.map(\.id))
        #expect(AIModelCatalog.sections(favorites: favorites).map(\.kind) == [.favorites, .recommended])
    }

    @Test func favoritesRoundTripTheirStoredStringAndDropUnknownOrRepeatedIds() {
        let favorites = AIModelFavorites(stored: "claude-opus-5-5, gone-model,gpt-6-astra,claude-opus-5-5")
        #expect(favorites.ids == ["claude-opus-5-5", "gpt-6-astra"])
        #expect(favorites.stored == "claude-opus-5-5,gpt-6-astra")
        #expect(AIModelFavorites(stored: favorites.stored) == favorites)
        #expect(AIModelFavorites(stored: "").ids.isEmpty)
        // Only catalog models can be starred.
        #expect(favorites.toggling("gone-model") == favorites)
        #expect(!favorites.toggling("claude-opus-5-5").contains("claude-opus-5-5"))
    }

    @Test func everyModelIsListedOnceWithAName() {
        let ids = AIModelCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(AIModelCatalog.opus.displayName == "Opus 5.5")
        #expect(AIModelCatalog.gptSol.displayName == "GPT-6.1 Sol")
    }
}
