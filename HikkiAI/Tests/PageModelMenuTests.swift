import Testing

@testable import HikkiAI

struct PageModelMenuTests {
    @Test func offersOnlyTheModelsWithAKeyInTheChatMenusSections() {
        let menu = PageModelMenu(
            choice: "auto", favorites: AIModelFavorites(ids: [AIModelCatalog.haiku.id]), available: [.anthropic])
        #expect(menu.auto == AIModelCatalog.sonnet)
        #expect(menu.groups.map(\.kind) == [.favorites, .recommended])
        #expect(menu.groups[0].models == [AIModelCatalog.haiku])
        #expect(menu.groups[1].models == [AIModelCatalog.opus, AIModelCatalog.sonnet])
    }

    @Test func aDefaultThatCantRunReadsAsAuto() {
        #expect(PageModelMenu(choice: "gpt-6.1-sol", favorites: .init(), available: [.anthropic]).choice == "auto")
        #expect(PageModelMenu(choice: "gone", favorites: .init(), available: [.anthropic]).choice == "auto")
        #expect(PageModelMenu(choice: "claude-opus-5-5", favorites: .init(), available: [.anthropic]).choice == "claude-opus-5-5")
    }

    @Test func withNoKeyThereIsNothingToChoose() {
        let menu = PageModelMenu(choice: nil, favorites: .init(), available: [])
        #expect(menu.auto == nil)
        #expect(menu.groups.isEmpty)
    }
}
