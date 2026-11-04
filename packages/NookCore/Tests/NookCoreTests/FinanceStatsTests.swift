import Foundation
import Testing
@testable import NookCore

struct FinanceStatsTests {
    private static let zone = Fixtures.plus8
    /// A Wednesday.
    private static let today = Fixtures.day(2026, 11, 4)

    private static var thisWeek: DateInterval {
        let monday = today.startOfISOWeek
        return DateInterval(start: monday.startDate(in: zone), end: monday.adding(days: 7).startDate(in: zone))
    }

    @Test func totalsOnlyMatchingKindAndCurrency() {
        let noon = Fixtures.time(2026, 11, 4, 12)
        let entries = [
            Fixtures.expense(1_000, .food, at: noon),
            Fixtures.expense(2_000, .food, at: noon, currency: "EUR"),
            Fixtures.expense(5_000, .salary, at: noon, kind: .income),
            Fixtures.expense(300, .travel, at: Fixtures.time(2026, 11, 9, 0)),  // next Monday
        ]
        #expect(FinanceStats.total(entries, in: Self.thisWeek, currencyCode: "usd") == Fixtures.usd(1_000))
        #expect(FinanceStats.total(entries, kind: .income, in: Self.thisWeek, currencyCode: "USD") == Fixtures.usd(5_000))
        #expect(FinanceStats.total(entries, in: Self.thisWeek, currencyCode: "EUR").minorUnits == 2_000)
    }

    @Test func dailyTotalsFollowTheGivenDays() {
        let entries = [
            Fixtures.expense(1_000, .food, at: Fixtures.time(2026, 11, 2, 8)),
            Fixtures.expense(500, .food, at: Fixtures.time(2026, 11, 2, 23, 59)),
            Fixtures.expense(700, .travel, at: Fixtures.time(2026, 11, 4, 0)),
        ]
        let totals = FinanceStats.dailyTotals(entries, days: Self.today.isoWeek, currencyCode: "USD", timeZone: Self.zone)
        #expect(totals.map(\.day) == Self.today.isoWeek)
        #expect(totals.map(\.total.minorUnits) == [1_500, 0, 700, 0, 0, 0, 0])
    }

    @Test func breakdownPercentagesAddUpTo100() {
        let noon = Fixtures.time(2026, 11, 3, 12)
        let entries = [
            Fixtures.expense(23_640, .food, at: noon),
            Fixtures.expense(8_980, .shopping, at: noon),
            Fixtures.expense(18_000, .travel, at: noon),
            Fixtures.expense(7_400, .others, at: noon),
        ]
        let shares = FinanceStats.categoryBreakdown(entries, in: Self.thisWeek, currencyCode: "USD")
        #expect(shares.map(\.category) == [.food, .travel, .shopping, .others])
        #expect(shares.map(\.percent) == [41, 31, 15, 13])
        #expect(shares.reduce(Money.zero("USD")) { $0 + $1.amount } == Fixtures.usd(58_020))
    }

    @Test func equalAmountsKeepAFixedOrder() {
        let noon = Fixtures.time(2026, 11, 3, 12)
        let entries = [
            Fixtures.expense(100, .shopping, at: noon),
            Fixtures.expense(100, .food, at: noon),
            Fixtures.expense(100, .travel, at: noon),
        ]
        let shares = FinanceStats.categoryBreakdown(entries, in: Self.thisWeek, currencyCode: "USD")
        #expect(shares == FinanceStats.categoryBreakdown(Array(entries.reversed()), in: Self.thisWeek, currencyCode: "USD"))
        #expect(shares.map(\.category) == [.food, .travel, .shopping])
        #expect(shares.map(\.percent) == [34, 33, 33])
        #expect(FinanceStats.categoryBreakdown([], in: Self.thisWeek, currencyCode: "USD").isEmpty)
    }

    @Test func percentChange() {
        #expect(FinanceStats.percentChange(from: Fixtures.usd(1_000), to: Fixtures.usd(914)) == -0.086)
        #expect(FinanceStats.percentChange(from: Fixtures.usd(1_000), to: Fixtures.usd(1_500)) == 0.5)
        #expect(FinanceStats.percentChange(from: Fixtures.usd(0), to: Fixtures.usd(500)) == nil)
        #expect(FinanceStats.percentChange(from: Money(minorUnits: 100, currencyCode: "EUR"), to: Fixtures.usd(500)) == nil)
    }

    @Test func weekToDateComparesTheSameWeekdays() {
        let entries = [
            Fixtures.expense(1_000, .food, at: Fixtures.time(2026, 11, 2, 9)),  // this Monday
            Fixtures.expense(2_000, .food, at: Fixtures.time(2026, 11, 4, 20)),  // today
            Fixtures.expense(9_999, .food, at: Fixtures.time(2026, 11, 5, 9)),  // tomorrow
            Fixtures.expense(4_000, .food, at: Fixtures.time(2026, 10, 26, 9)),  // last Monday
            Fixtures.expense(8_000, .food, at: Fixtures.time(2026, 10, 29, 9)),  // last Thursday
        ]
        let comparison = FinanceStats.weekToDate(entries, today: Self.today, currencyCode: "USD", timeZone: Self.zone)
        #expect(comparison.current == Fixtures.usd(3_000))
        #expect(comparison.previous == Fixtures.usd(4_000))
        #expect(comparison.change == -0.25)
    }

    @Test func monthToDateComparesTheSameDays() {
        let entries = [
            Fixtures.expense(10_000, .housing, at: Fixtures.time(2026, 11, 1, 9)),
            Fixtures.expense(2_000, .food, at: Fixtures.time(2026, 11, 4, 9)),
            Fixtures.expense(5_000, .food, at: Fixtures.time(2026, 10, 3, 9)),
            Fixtures.expense(7_000, .food, at: Fixtures.time(2026, 10, 20, 9)),
        ]
        let comparison = FinanceStats.monthToDate(entries, today: Self.today, currencyCode: "USD", timeZone: Self.zone)
        #expect(comparison.current == Fixtures.usd(12_000))
        #expect(comparison.previous == Fixtures.usd(5_000))
    }

    @Test func monthEndComparesWholeMonths() {
        let entries = [
            Fixtures.expense(1_000, .food, at: Fixtures.time(2026, 2, 28, 20)),
            Fixtures.expense(3_000, .food, at: Fixtures.time(2026, 3, 1, 9)),
        ]
        for day in [Fixtures.day(2026, 3, 30), Fixtures.day(2026, 3, 31)] {
            let comparison = FinanceStats.monthToDate(entries, today: day, currencyCode: "USD", timeZone: Self.zone)
            #expect(comparison.previous == Fixtures.usd(1_000), "on \(day)")
        }
        let april = FinanceStats.monthToDate(entries, today: Fixtures.day(2026, 4, 30), currencyCode: "USD", timeZone: Self.zone)
        #expect(april.previous == Fixtures.usd(3_000))
    }

    @Test func cumulativeSeriesClimbsToTheMonthTotal() {
        let entries = [
            Fixtures.expense(10_000, .housing, at: Fixtures.time(2026, 11, 1, 9)),
            Fixtures.expense(2_550, .food, at: Fixtures.time(2026, 11, 2, 12)),
            Fixtures.expense(500, .transport, at: Fixtures.time(2026, 11, 4, 8)),
            Fixtures.expense(4_000, .food, at: Fixtures.time(2026, 10, 31, 12)),  // last month
        ]
        let series = FinanceStats.cumulativeSeries(entries, through: Self.today, currencyCode: "USD", timeZone: Self.zone)
        let values = series.map(\.total.minorUnits)
        #expect(series.count == 7)
        #expect(series.first?.day == Fixtures.day(2026, 11, 1))
        #expect(series.last?.day == Self.today)
        #expect(values == values.sorted())
        #expect(values.first == 10_000)
        let monthTotal = FinanceStats.monthToDate(entries, today: Self.today, currencyCode: "USD", timeZone: Self.zone).current
        #expect(values.last == monthTotal.minorUnits)
        #expect(monthTotal == Fixtures.usd(13_050))
    }
}
