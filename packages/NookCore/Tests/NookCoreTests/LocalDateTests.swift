import Foundation
import Testing
@testable import NookCore

struct LocalDateTests {
    @Test func validatesDays() {
        #expect(LocalDate(year: 2024, month: 2, day: 29) != nil)
        #expect(LocalDate(year: 2000, month: 2, day: 29) != nil)
        #expect(LocalDate(year: 2025, month: 2, day: 29) == nil)
        #expect(LocalDate(year: 1900, month: 2, day: 29) == nil)
        #expect(LocalDate(year: 2026, month: 4, day: 31) == nil)
        #expect(LocalDate(year: 2026, month: 13, day: 1) == nil)
        #expect(LocalDate(year: 2026, month: 1, day: 0) == nil)
    }

    @Test func julianDayAndWeekday() {
        #expect(Fixtures.day(2000, 1, 1).julianDay == 2_451_545)
        #expect(Fixtures.day(1970, 1, 1).julianDay == 2_440_588)
        #expect(Fixtures.day(2026, 11, 4).julianDay == 2_461_349)
        #expect(Fixtures.day(2000, 1, 1).isoWeekday == 6)  // Saturday
        #expect(Fixtures.day(2026, 11, 1).isoWeekday == 7)  // Sunday
        #expect(Fixtures.day(2026, 11, 2).isoWeekday == 1)  // Monday
        #expect(Fixtures.day(2026, 11, 4).isoWeekday == 3)  // Wednesday
    }

    @Test(arguments: ["0001-01-01", "1970-01-01", "2000-01-01", "2024-02-29", "2026-12-31", "9999-12-31"])
    func julianDayRoundTrips(iso: String) throws {
        let date = try #require(LocalDate(isoString: iso))
        #expect(LocalDate(julianDay: date.julianDay) == date)
        #expect(date.isoString == iso)
    }

    @Test func startOfDayInATimeZone() {
        let start = Fixtures.day(2026, 11, 4).startDate(in: Fixtures.plus8)
        #expect(start == Date(timeIntervalSince1970: 1_793_721_600))
        #expect(LocalDate(start, timeZone: Fixtures.plus8) == Fixtures.day(2026, 11, 4))
        #expect(LocalDate(start, timeZone: Fixtures.utc) == Fixtures.day(2026, 11, 3))
    }

    @Test func intervalCoversOneDay() {
        let interval = Fixtures.day(2026, 11, 4).interval(in: Fixtures.plus8)
        #expect(interval.duration == 86_400)
        #expect(interval.end == Fixtures.day(2026, 11, 5).startDate(in: Fixtures.plus8))
    }

    @Test func parsesOnlyFullISODates() {
        #expect(LocalDate(isoString: "2026-11-04") == Fixtures.day(2026, 11, 4))
        #expect(LocalDate(isoString: "2026-1-04") == nil)
        #expect(LocalDate(isoString: "2026-02-30") == nil)
        #expect(LocalDate(isoString: "20261104") == nil)
        #expect(LocalDate(isoString: "+026-11-04") == nil)
        #expect(LocalDate(isoString: "2026-11-04T00:00") == nil)
        #expect(Fixtures.day(33, 3, 7).isoString == "0033-03-07")
    }

    @Test func addsMonthsClampingTheDay() {
        #expect(Fixtures.day(2024, 1, 31).adding(months: 1) == Fixtures.day(2024, 2, 29))
        #expect(Fixtures.day(2025, 1, 31).adding(months: 1) == Fixtures.day(2025, 2, 28))
        #expect(Fixtures.day(2026, 3, 31).adding(months: -1) == Fixtures.day(2026, 2, 28))
        #expect(Fixtures.day(2026, 1, 15).adding(months: -1) == Fixtures.day(2025, 12, 15))
        #expect(Fixtures.day(2026, 11, 4).adding(months: 14) == Fixtures.day(2028, 1, 4))
    }

    @Test func countsDays() {
        #expect(Fixtures.day(2026, 1, 1).days(to: Fixtures.day(2026, 11, 4)) == 307)
        #expect(Fixtures.day(2026, 11, 4).days(to: Fixtures.day(2026, 1, 1)) == -307)
        #expect(Fixtures.day(2024, 2, 28).adding(days: 1) == Fixtures.day(2024, 2, 29))
        #expect(Fixtures.day(2026, 12, 31).adding(days: 1) == Fixtures.day(2027, 1, 1))
    }

    @Test func isoWeekRunsMondayToSunday() {
        let week = Fixtures.day(2026, 11, 4).isoWeek
        #expect(week.count == 7)
        #expect(week.first == Fixtures.day(2026, 11, 2))
        #expect(week.last == Fixtures.day(2026, 11, 8))
        #expect(Fixtures.day(2026, 11, 8).startOfISOWeek == Fixtures.day(2026, 11, 2))
        #expect(Fixtures.day(2026, 11, 2).startOfISOWeek == Fixtures.day(2026, 11, 2))
        #expect(Fixtures.day(2026, 11, 4).startOfMonth == Fixtures.day(2026, 11, 1))
    }

    @Test func comparesChronologically() {
        #expect(Fixtures.day(2025, 12, 31) < Fixtures.day(2026, 1, 1))
        #expect(Fixtures.day(2026, 2, 1) > Fixtures.day(2026, 1, 31))
    }

    @Test func codesAsAString() throws {
        let data = try JSONEncoder().encode([Fixtures.day(2026, 11, 4)])
        #expect(String(decoding: data, as: UTF8.self) == #"["2026-11-04"]"#)
        #expect(try JSONDecoder().decode([LocalDate].self, from: data) == [Fixtures.day(2026, 11, 4)])
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([LocalDate].self, from: Data(#"["2026-02-30"]"#.utf8))
        }
    }
}
