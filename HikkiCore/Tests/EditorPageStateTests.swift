import Foundation
import Testing

@testable import HikkiCore

struct EditorPageStateTests {
    private func page(_ id: String, title: String? = nil, icon: String? = nil, locked: Bool = false, words: Int = 0) -> PageSummary {
        PageSummary(
            id: id, parentId: nil, title: title ?? id, icon: icon, updatedAt: .now, favoritedAt: nil, deletedAt: nil, sortKey: 0,
            lockedAt: locked ? .now : nil, wordCount: words)
    }

    @Test func theIndexIsSentOnlyWhenATitleOrIconChanged() {
        var state = EditorPageState()
        #expect(state.index(for: [page("a"), page("b")])?.map(\.id) == ["a", "b"])
        // A body save: new word count and edited time, same titles and icons — nothing to send.
        #expect(state.index(for: [page("a", words: 12), page("b")]) == nil)
        #expect(state.index(for: [page("a", title: "Renamed"), page("b")])?.first?.title == "Renamed")
        #expect(state.index(for: [page("a", title: "Renamed"), page("b", icon: "🌱")]) != nil)
        #expect(state.index(for: [page("a", title: "Renamed")]) != nil)  // a page left
        state.reset()
        #expect(state.index(for: [page("a", title: "Renamed")]) != nil)  // a reloaded editor gets it again
    }

    @Test func aLockReachesThePageShownOnce() {
        var state = EditorPageState()
        state.loaded("a", locked: false)
        #expect(state.lockChange(showing: "a", in: PageTree([page("a")])) == nil)
        #expect(state.lockChange(showing: "a", in: PageTree([page("a", locked: true)])) == true)
        #expect(state.lockChange(showing: "a", in: PageTree([page("a", locked: true)])) == nil)  // already told
        #expect(state.lockChange(showing: "a", in: PageTree([page("a")])) == false)
    }

    /// During a switch the editor still shows the old page: the new page's state is not sent to it — its load
    /// carries it (the old ContentView hook sent the new page's lock to the old page).
    @Test func noLockIsSentForAPageStillLoading() {
        var state = EditorPageState()
        state.loaded("a", locked: false)
        #expect(state.lockChange(showing: "b", in: PageTree([page("a"), page("b", locked: true)])) == nil)
        state.loaded("b", locked: true)
        #expect(state.lockChange(showing: "b", in: PageTree([page("a"), page("b", locked: true)])) == nil)
        #expect(state.lockChange(showing: nil, in: PageTree([page("a")])) == nil)
    }
}
