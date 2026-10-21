import Foundation
import Testing

@testable import HikkiCore

struct DateMentionsTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func chip(_ id: String, _ date: String, time: String? = nil, remind: Int? = nil, done: Bool = false) -> JSONValue {
        var attrs: [String: JSONValue] = ["id": .string(id), "date": .string(date), "done": .bool(done)]
        attrs["time"] = time.map(JSONValue.string) ?? .null
        attrs["remind"] = remind.map { .number(Double($0)) } ?? .null
        return .object(["type": .string("dateMention"), "attrs": .object(attrs)])
    }

    private func text(_ text: String) -> JSONValue { .object(["type": .string("text"), "text": .string(text)]) }

    private func line(_ id: String, _ content: [JSONValue]) -> JSONValue {
        .object(["type": .string("paragraph"), "attrs": .object(["id": .string(id)]), "content": .array(content)])
    }

    private func doc(_ blocks: [JSONValue]) -> JSONValue { .object(["type": .string("doc"), "content": .array(blocks)]) }

    @Test func readsAChipAndRefusesMalformedOnes() {
        let attrs: JSONValue = .object([
            "id": .string("m1"), "date": .string("2026-10-22"), "time": .string("09:30"), "remind": .number(5),
            "done": .bool(false), "snoozed": .null,
        ])
        #expect(DateMention(attrs: attrs) == DateMention(id: "m1", date: "2026-10-22", time: "09:30", remind: 5))
        #expect(DateMention(attrs: .object(["date": .string("2026-02-30")])) == nil)
        #expect(DateMention(attrs: .object(["date": .string("tomorrow")])) == nil)
        // A malformed time is a whole day.
        #expect(DateMention(attrs: .object(["date": .string("2026-10-22"), "time": .string("25:00")]))?.time == nil)
        // Stored attributes read back the same.
        let mention = DateMention(id: "m2", date: "2026-10-23", remind: 0, done: true, snoozed: "2026-10-23T10:00")
        #expect(DateMention(attrs: mention.attrs) == mention)
    }

    @Test func aReminderRingsAtItsWallClockTime() {
        let timed = DateMention(id: nil, date: "2026-10-22", time: "09:30", remind: 60)
        #expect(timed.fireDate(in: calendar) == at(2026, 10, 22, 8, 30))
        // A whole day rings at 9:00, a day before is the day before at 9:00.
        #expect(DateMention(id: nil, date: "2026-10-22", remind: 0).fireDate(in: calendar) == at(2026, 10, 22, 9))
        #expect(DateMention(id: nil, date: "2026-10-22", remind: 1440).fireDate(in: calendar) == at(2026, 10, 21, 9))
        #expect(DateMention(id: nil, date: "2026-10-22").fireDate(in: calendar) == nil)
        var snoozed = timed
        snoozed.snooze(minutes: 60, now: at(2026, 10, 22, 8, 31), calendar: calendar)
        #expect(snoozed.snoozed == "2026-10-22T09:31")
        #expect(snoozed.fireDate(in: calendar) == at(2026, 10, 22, 9, 31))
    }

    @Test func overdueUntilMarkedDone() {
        var mention = DateMention(id: "m", date: "2026-10-22", time: "09:00", remind: 0)
        #expect(!mention.isOverdue(now: at(2026, 10, 22, 8, 59), calendar: calendar))
        #expect(mention.isOverdue(now: at(2026, 10, 22, 9), calendar: calendar))
        mention.markDone()
        #expect(!mention.isOverdue(now: at(2026, 10, 23), calendar: calendar))
        // A plain date is never overdue.
        #expect(!DateMention(id: nil, date: "2020-01-01").isOverdue(now: at(2026, 10, 22), calendar: calendar))
    }

    @Test func findsChipsWithTheirLineAndWords() {
        let content = doc([
            line("p1", [text("Book the "), chip("m1", "2026-10-22"), text("  ryokan")]),
            .object([
                "type": .string("bulletList"),
                "content": .array([
                    .object([
                        "type": .string("listItem"),
                        "content": .array([line("li", [chip("m2", "2026-10-23", time: "09:00", remind: 0)])]),
                    ])
                ]),
            ]),
            line("p2", [text("no dates")]),
        ])
        let found = DateMentions.find(in: content)
        #expect(found.map(\.blockId) == ["p1", "li"])
        #expect(found.map(\.text) == ["Book the ryokan", ""])
        #expect(found[1].mention.remind == 0)
    }

    @Test func aReminderFromSyncedContentStaysInRange() {
        func remind(_ value: JSONValue) -> Int? {
            DateMention(attrs: .object(["date": .string("2026-10-22"), "remind": value]))?.remind
        }
        #expect(remind(.number(60)) == 60)
        #expect(remind(.number(1e300)) == nil)
        #expect(remind(.number(-5)) == nil)
        #expect(remind(.number(1.5)) == nil)
        #expect(remind(.number(Double(DateMention.maxRemind + 1))) == nil)
    }

    @Test func theStoreListsOnlyLivePagesWithDates() throws {
        let store = try DocumentStore.inMemory()
        let dated = try store.create()
        let plain = try store.create()
        let trashed = try store.create()
        let withDate = doc([line("p1", [text("Call "), chip("a", "2026-10-22")])])
        for (record, content) in [(dated, withDate), (plain, doc([line("p2", [text("Nothing here")])])), (trashed, withDate)] {
            _ = try store.saveContent(Snapshot(docId: record.id, content: content, title: "T", text: "", wordCount: 0))
        }
        try store.moveToTrash(id: trashed.id)
        #expect(try store.pagesWithDates().map(\.id) == [dated.id])
    }

    @Test func marksOneChipDoneByItsId() throws {
        let content = doc([line("p1", [chip("a", "2026-10-22", remind: 0), chip("b", "2026-10-23", remind: 0)])])
        let next = try #require(DateMentions.updating(content, id: "b") { $0.markDone() })
        #expect(DateMentions.find(in: next).map(\.mention.done) == [false, true])
        #expect(DateMentions.updating(content, id: "nope") { $0.markDone() } == nil)
    }

    @Test func upcomingPutsOverdueRemindersFirstThenTheNextSevenDays() {
        let now = at(2026, 10, 21, 12)
        func entry(_ id: String, _ mention: DateMention) -> DateEntry {
            DateEntry(pageId: "page", pageTitle: "Page", found: .init(mention: mention, blockId: id, text: id))
        }
        let entries = [
            entry("later", DateMention(id: "later", date: "2026-11-30")),
            entry("friday", DateMention(id: "friday", date: "2026-10-23")),
            entry("missed", DateMention(id: "missed", date: "2026-10-20", time: "09:00", remind: 0)),
            entry("done", DateMention(id: "done", date: "2026-10-19", time: "09:00", remind: 0, done: true)),
            entry("today", DateMention(id: "today", date: "2026-10-21", time: "18:00", remind: 0)),
            entry("week", DateMention(id: "week", date: "2026-10-27")),
            entry("eight", DateMention(id: "eight", date: "2026-10-28")),
        ]
        let items = Upcoming.items(entries, now: now, calendar: calendar)
        #expect(items.map(\.found.blockId) == ["missed", "today", "friday", "week"])
        let pending = Upcoming.pending(entries, now: now, calendar: calendar)
        #expect(pending.map(\.entry.found.blockId) == ["today"])
        #expect(pending.first?.fire.hour == 18)
    }

    @Test func readsRelativeToToday() {
        let now = at(2026, 10, 21, 23, 30)
        func day(_ date: String) -> Upcoming.Day? {
            Upcoming.day(of: DateMention(id: nil, date: date), now: now, calendar: calendar)
        }
        #expect(day("2026-10-21") == .today)
        #expect(day("2026-10-22") == .tomorrow)
        #expect(day("2026-10-20") == .yesterday)
        #expect(day("2026-10-27") == .weekday(at(2026, 10, 27)))
        #expect(day("2026-10-28") == .date(at(2026, 10, 28), withYear: false))
        #expect(day("2027-01-02") == .date(at(2027, 1, 2), withYear: true))
    }
}
