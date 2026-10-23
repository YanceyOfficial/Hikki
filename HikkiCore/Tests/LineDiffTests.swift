import Foundation
import Testing

@testable import HikkiCore

struct LineDiffTests {
    @Test func changedLinesWithTheirContext() {
        let old = (1...10).map { "line \($0)" }.joined(separator: "\n")
        let new = old.replacingOccurrences(of: "line 5", with: "line five")
        guard case .lines(let items, let added, let removed) = LineDiff.diff(old: old, new: new, context: 1) else {
            return #expect(Bool(false))
        }
        #expect(added == 1 && removed == 1)
        #expect(
            items == [
                .gap(3), .row(.init(kind: .context, text: "line 4")), .row(.init(kind: .removed, text: "line 5")),
                .row(.init(kind: .added, text: "line five")), .row(.init(kind: .context, text: "line 6")), .gap(4),
            ])
    }

    @Test func aNewTextIsAllAdded() {
        #expect(LineDiff.diff(old: "", new: "a\nb\n").added == 2)
        #expect(
            LineDiff.diff(old: "a\r\nb", new: "a\nb")
                == .lines(items: [.row(.init(kind: .context, text: "a")), .row(.init(kind: .context, text: "b"))], added: 0, removed: 0))
    }

    @Test func tooLargeToCompareIsSaid() {
        let old = (1...600).map { "a\($0)" }.joined(separator: "\n")
        let new = (1...600).map { "b\($0)" }.joined(separator: "\n")
        #expect(LineDiff.diff(old: old, new: new) == .tooLarge(oldLines: 600, newLines: 600))
    }

    @Test func aChatsToolCallsAreKeptAndComeBackStopped() throws {
        var call = ChatToolCall(id: "c1", name: "edit_file", path: "notes/plan.md", status: .waiting)
        call.before = ChatToolCall.capped(String(repeating: "x", count: ChatToolCall.maxText + 10))
        call.after = "y"
        let turn = ChatTurn(id: "t", role: .assistant, text: "Done.", sentAt: .now, tools: [call])
        let back = try JSONDecoder().decode(ChatTurn.self, from: JSONEncoder().encode(turn))
        #expect(back.tools == [call])
        #expect(back.tools?.first?.before?.count == ChatToolCall.maxText)
        #expect(call.restored.status == .stopped)
        var done = call
        done.status = .done
        #expect(done.restored.status == .done)
        // Older files have no tools.
        let older = #"{"id":"t","role":"assistant","text":"Hi","sentAt":0,"attachments":[],"citations":[]}"#
        #expect(try JSONDecoder().decode(ChatTurn.self, from: Data(older.utf8)).tools == nil)
    }
}
