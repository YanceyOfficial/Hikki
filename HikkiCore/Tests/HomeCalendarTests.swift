import Foundation
import Testing

@testable import HikkiCore

struct HomeCalendarTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        c.firstWeekday = 1  // Sunday: the view sets Monday itself
        return HomeCalendar.calendar(c)
    }

    private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    private struct Page: Equatable {
        let id: String
        let edited: Date
    }

    @Test func weeksStartOnMonday() {
        #expect(calendar.firstWeekday == 2)
        // October 2026: the 1st is a Thursday, the 31st a Saturday.
        let weeks = HomeCalendar.weeks(of: CalendarMonth(year: 2026, month: 10), calendar: calendar)
        #expect(weeks.count == 5)
        #expect(weeks.allSatisfy { $0.count == 7 })
        #expect(weeks[0][0] == calendar.startOfDay(for: day(2026, 9, 28)))  // Monday before the 1st
        #expect(weeks[0][3] == calendar.startOfDay(for: day(2026, 10, 1)))
        #expect(weeks[4][6] == calendar.startOfDay(for: day(2026, 11, 1)))  // the Sunday after the 31st
    }

    @Test func aMonthStartingOnMondayHasNoLeadingDays() {
        // June 2026 starts on a Monday and ends on a Tuesday: five rows.
        let weeks = HomeCalendar.weeks(of: CalendarMonth(year: 2026, month: 6), calendar: calendar)
        #expect(weeks.first?.first == calendar.startOfDay(for: day(2026, 6, 1)))
        #expect(weeks.count == 5)
        // February 2027: Monday the 1st to Sunday the 28th, exactly four rows.
        #expect(HomeCalendar.weeks(of: CalendarMonth(year: 2027, month: 2), calendar: calendar).count == 4)
    }

    @Test func monthsStepAcrossYears() {
        #expect(CalendarMonth(year: 2026, month: 12).adding(1) == CalendarMonth(year: 2027, month: 1))
        #expect(CalendarMonth(year: 2026, month: 1).adding(-1) == CalendarMonth(year: 2025, month: 12))
        #expect(CalendarMonth(year: 2026, month: 5).adding(-17) == CalendarMonth(year: 2024, month: 12))
        #expect(CalendarMonth(containing: day(2026, 10, 24), calendar: calendar) == CalendarMonth(year: 2026, month: 10))
    }

    @Test func weekdaySymbolsFollowTheFirstWeekday() {
        let symbols = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        #expect(HomeCalendar.weekdaySymbols(symbols, firstWeekday: 2) == ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
        #expect(HomeCalendar.weekdaySymbols(symbols, firstWeekday: 1) == symbols)
    }

    @Test func pagesGroupByTheirEditedDayNewestFirst() {
        let pages = [
            Page(id: "a", edited: day(2026, 10, 24, hour: 9)),
            Page(id: "b", edited: day(2026, 10, 24, hour: 22)),
            Page(id: "c", edited: day(2026, 10, 23, hour: 0)),
            Page(id: "d", edited: day(2026, 9, 30)),
        ]
        let days = HomeCalendar.byDay(pages, date: \.edited, calendar: calendar)
        #expect(days[calendar.startOfDay(for: day(2026, 10, 24))]?.map(\.id) == ["b", "a"])
        #expect(days[calendar.startOfDay(for: day(2026, 10, 23))]?.map(\.id) == ["c"])
        #expect(HomeCalendar.count(in: CalendarMonth(year: 2026, month: 10), of: days, calendar: calendar) == 3)
        #expect(HomeCalendar.count(in: CalendarMonth(year: 2026, month: 9), of: days, calendar: calendar) == 1)
        #expect(HomeCalendar.count(in: CalendarMonth(year: 2026, month: 8), of: days, calendar: calendar) == 0)
    }

    @Test func theDefaultDayIsTodayOrTheLastDayWithPages() {
        let october = CalendarMonth(year: 2026, month: 10)
        let today = day(2026, 10, 24, hour: 15)
        let busyToday = HomeCalendar.byDay([Page(id: "a", edited: day(2026, 10, 24, hour: 8))], date: \.edited, calendar: calendar)
        #expect(HomeCalendar.defaultDay(in: october, days: busyToday, today: today, calendar: calendar) == calendar.startOfDay(for: today))

        let earlier = HomeCalendar.byDay(
            [Page(id: "a", edited: day(2026, 10, 3)), Page(id: "b", edited: day(2026, 10, 19)), Page(id: "c", edited: day(2026, 9, 29))],
            date: \.edited, calendar: calendar)
        #expect(HomeCalendar.defaultDay(in: october, days: earlier, today: today, calendar: calendar) == calendar.startOfDay(for: day(2026, 10, 19)))
        // Another month: its last day with pages, else its first day.
        let september = CalendarMonth(year: 2026, month: 9)
        #expect(HomeCalendar.defaultDay(in: september, days: earlier, today: today, calendar: calendar) == calendar.startOfDay(for: day(2026, 9, 29)))
        let august = CalendarMonth(year: 2026, month: 8)
        #expect(HomeCalendar.defaultDay(in: august, days: earlier, today: today, calendar: calendar) == calendar.startOfDay(for: day(2026, 8, 1)))
        // Nothing this month: today.
        let none: [Date: [Page]] = [:]
        #expect(HomeCalendar.defaultDay(in: october, days: none, today: today, calendar: calendar) == calendar.startOfDay(for: today))
    }
}
