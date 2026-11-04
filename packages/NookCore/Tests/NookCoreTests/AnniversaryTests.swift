import Foundation
import Testing
@testable import NookCore

struct AnniversaryTests {
    private func yearly(_ date: LocalDate) -> Anniversary {
        Anniversary(title: "Test", date: date, repeatRule: .yearly, createdAt: Date(timeIntervalSince1970: 0))
    }

    @Test func leapDayFallsBackToFebruary28() {
        let leapDay = yearly(Fixtures.day(2024, 2, 29))
        #expect(leapDay.nextOccurrence(onOrAfter: Fixtures.day(2023, 6, 1)) == Fixtures.day(2024, 2, 29))
        #expect(leapDay.nextOccurrence(onOrAfter: Fixtures.day(2025, 2, 28)) == Fixtures.day(2025, 2, 28))
        #expect(leapDay.nextOccurrence(onOrAfter: Fixtures.day(2025, 3, 1)) == Fixtures.day(2026, 2, 28))
        #expect(leapDay.nextOccurrence(onOrAfter: Fixtures.day(2027, 3, 1)) == Fixtures.day(2028, 2, 29))
    }

    @Test func yearlyStatus() {
        let birthday = yearly(Fixtures.day(2020, 6, 1))
        #expect(birthday.status(on: Fixtures.day(2020, 5, 1)) == .upcoming(days: 31, years: 0))
        #expect(birthday.status(on: Fixtures.day(2020, 6, 1)) == .today(years: 0))
        #expect(birthday.status(on: Fixtures.day(2026, 5, 31)) == .upcoming(days: 1, years: 6))
        #expect(birthday.status(on: Fixtures.day(2026, 6, 1)) == .today(years: 6))
        #expect(birthday.status(on: Fixtures.day(2026, 6, 2)) == .upcoming(days: 364, years: 7))
    }

    @Test func oneOffDates() {
        let launch = Anniversary(title: "Launch", date: Fixtures.day(2026, 1, 1), repeatRule: .never, kind: .project)
        #expect(launch.status(on: Fixtures.day(2025, 12, 25)) == .upcoming(days: 7, years: 0))
        #expect(launch.status(on: Fixtures.day(2026, 1, 1)) == .today(years: 0))
        #expect(launch.status(on: Fixtures.day(2026, 11, 4)) == .elapsed(days: 307))
        #expect(launch.nextOccurrence(onOrAfter: Fixtures.day(2026, 1, 2)) == nil)
    }
}
