import Foundation
import Testing
@testable import StillpointModel

struct DayTests {
    @Test func componentsRoundTrip() {
        let day = Day(year: 2026, month: 3, day: 9)
        #expect(day.rawValue == 20_260_309)
        #expect(day.year == 2026)
        #expect(day.month == 3)
        #expect(day.day == 9)
        #expect(day.description == "2026-03-09")
    }

    @Test func fromDateUsesCalendarTimeZone() {
        // 2026-10-15 23:30 UTC is already Oct 16 in Kolkata (UTC+5:30).
        let date = Date(timeIntervalSince1970: 1_792_107_000)
        #expect(Day(date, calendar: .fixture(timeZone: "UTC")) == Day(year: 2026, month: 10, day: 15))
        #expect(Day(date, calendar: .fixture(timeZone: "Asia/Kolkata")) == Day(year: 2026, month: 10, day: 16))
    }

    @Test func addingDaysCrossesMonthYearAndDST() {
        let berlin = Calendar.fixture(timeZone: "Europe/Berlin")
        #expect(Day(year: 2026, month: 12, day: 31).adding(days: 1, calendar: berlin) == Day(year: 2027, month: 1, day: 1))
        #expect(Day(year: 2028, month: 3, day: 1).adding(days: -1, calendar: berlin) == Day(year: 2028, month: 2, day: 29))
        // DST ends in Berlin on 2026-10-25.
        #expect(Day(year: 2026, month: 10, day: 24).adding(days: 2, calendar: berlin) == Day(year: 2026, month: 10, day: 26))
    }

    @Test func ordering() {
        #expect(Day(year: 2026, month: 1, day: 31) < Day(year: 2026, month: 2, day: 1))
    }
}
