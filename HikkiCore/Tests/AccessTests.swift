import Foundation
import Testing

@testable import HikkiCore

struct AccessTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }

    private func date(_ day: Int, hour: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    @Test func theTrialCountsDownFourteenDays() {
        let downloaded = date(1)
        #expect(Access.on(date(1), downloaded: downloaded, unlocked: false, calendar: calendar) == .trial(daysLeft: 14))
        #expect(Access.on(date(8), downloaded: downloaded, unlocked: false, calendar: calendar) == .trial(daysLeft: 7))
        // The last morning still has a day; from the hour it was downloaded, the trial is over.
        #expect(Access.on(date(15, hour: 9), downloaded: downloaded, unlocked: false, calendar: calendar) == .trial(daysLeft: 1))
        #expect(Access.on(date(15, hour: 10), downloaded: downloaded, unlocked: false, calendar: calendar) == .expired)
        #expect(Access.on(date(30), downloaded: downloaded, unlocked: false, calendar: calendar) == .expired)
    }

    @Test func theUnlockOpensEverythingForGood() {
        #expect(Access.on(date(30), downloaded: date(1), unlocked: true, calendar: calendar) == .unlocked)
        #expect(Access.unlocked.canWrite)
        #expect(Access.trial(daysLeft: 3).canWrite)
        #expect(!Access.expired.canWrite)
    }

    @Test func aClockSetBeforeTheDownloadIsStillATrial() {
        #expect(Access.on(date(1), downloaded: date(5), unlocked: false, calendar: calendar) == .trial(daysLeft: 14))
    }
}
