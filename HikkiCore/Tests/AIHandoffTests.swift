import Testing

@testable import HikkiCore

struct AIHandoffTests {
    @Test func theChatComesUpBesideThePageUnlessTheWindowIsSplitOrCompact() {
        // Mac, a wide iPad: the inspector, in AI mode.
        #expect(AIHandoff.placement(wide: true, isSplit: false) == .inspector)
        // Split: the inspector belongs to the left page and is off — the Ask AI sheet, from either side.
        #expect(AIHandoff.placement(wide: true, isSplit: true) == .sheet)
        // iPhone (a compact window): the Ask AI sheet.
        #expect(AIHandoff.placement(wide: false, isSplit: false) == .sheet)
    }
}
