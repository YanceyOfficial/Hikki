import Foundation
import Testing

@testable import HikkiCore

struct ActivityTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        c.firstWeekday = 1  // Sunday
        return c
    }

    private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    @Test func savesCountAsEditsAndAddedWords() throws {
        let s = try DocumentStore.inMemory()
        try s.create(id: "a", now: day(2026, 10, 1))
        let body = try JSONValue(jsonData: Data(#"{"type":"doc"}"#.utf8))
        _ = try s.saveContent(Snapshot(docId: "a", content: body, title: "One", text: "", wordCount: 10), now: day(2026, 10, 2))
        _ = try s.saveContent(Snapshot(docId: "a", content: body, title: "Two", text: "", wordCount: 4), now: day(2026, 10, 2))
        // Unchanged content: no edit.
        _ = try s.saveContent(Snapshot(docId: "a", content: body, title: "Two", text: "", wordCount: 4), now: day(2026, 10, 2))
        let days = try s.activity(since: day(2026, 10, 1))
        let oct2 = try #require(days.first { ActivityDay.key($0.day) == "2026-10-02" })
        #expect(oct2.edits == 2)
        #expect(oct2.wordsAdded == 10)  // +10, then −6 counts as 0 added
        #expect(try s.stats() == WorkspaceStats(pages: 1, words: 4))
    }
}
