import Testing

@testable import HikkiCore

struct AIHandoffTests {
    @Test func theChatComesUpBesideThePageUnlessTheWindowIsCompact() {
        // Mac, a wide iPad — split or not: the panel of the side it came from, in AI mode.
        #expect(AIHandoff.placement(wide: true) == .inspector)
        // iPhone (a compact window): the Ask AI sheet.
        #expect(AIHandoff.placement(wide: false) == .sheet)
    }
}
