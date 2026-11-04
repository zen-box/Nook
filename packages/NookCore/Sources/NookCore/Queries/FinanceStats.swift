import Foundation

/// One day's total, for bar charts.
public struct DailyTotal: Identifiable, Hashable, Sendable {
    public var day: LocalDate
    public var total: Money
    public var id: LocalDate { day }

    public init(day: LocalDate, total: Money) {
        self.day = day
        self.total = total
    }
}

/// A category's part of a period's total.
public struct CategoryShare: Identifiable, Hashable, Sendable {
    public var category: LedgerCategory
    public var amount: Money
    /// Whole percent of the period total. The shares of one breakdown always add up to 100.
    public var percent: Int
    public var id: LedgerCategory { category }

    public init(category: LedgerCategory, amount: Money, percent: Int) {
        self.category = category
        self.amount = amount
        self.percent = percent
    }
}

/// A period's total next to the total of the same stretch of the period before it.
public struct PeriodComparison: Hashable, Sendable {
    public var current: Money
    public var previous: Money

    public init(current: Money, previous: Money) {
        self.current = current
        self.previous = previous
    }

    /// -0.086 when spending fell by 8.6%; nil when there is nothing to compare against.
    public var change: Double? {
        FinanceStats.percentChange(from: previous, to: current)
    }
}

/// Totals for the finance screens. Entries in other currencies than the one asked for are left
/// out: there is no currency conversion yet.
public enum FinanceStats {
    /// The sum of `kind` entries that happened inside `interval` (its end excluded).
    public static func total(
        _ entries: [LedgerEntry],
        kind: LedgerKind = .expense,
        in interval: DateInterval,
        currencyCode: String
    ) -> Money {
        let code = currencyCode.uppercased()
        var sum: Int64 = 0
        for entry in entries where entry.kind == kind && entry.currencyCode == code && interval.containsExcludingEnd(entry.occurredAt) {
            sum += entry.amountMinor
        }
        return Money(minorUnits: sum, currencyCode: code)
    }

    /// The total of each of `days`, in the same order.
    public static func dailyTotals(
        _ entries: [LedgerEntry],
        kind: LedgerKind = .expense,
        days: [LocalDate],
        currencyCode: String,
        timeZone: TimeZone
    ) -> [DailyTotal] {
        let code = currencyCode.uppercased()
        var sums: [LocalDate: Int64] = [:]
        for entry in entries where entry.kind == kind && entry.currencyCode == code {
            sums[LocalDate(entry.occurredAt, timeZone: timeZone), default: 0] += entry.amountMinor
        }
        return days.map { DailyTotal(day: $0, total: Money(minorUnits: sums[$0] ?? 0, currencyCode: code)) }
    }

    /// The month's running total at `points` evenly spaced days from the 1st through `today`,
    /// so it never falls.
    public static func cumulativeSeries(
        _ entries: [LedgerEntry],
        kind: LedgerKind = .expense,
        through today: LocalDate,
        points: Int = 7,
        currencyCode: String,
        timeZone: TimeZone
    ) -> [DailyTotal] {
        precondition(points > 0, "A series needs at least one point")
        let monthStart = today.startOfMonth
        let span = monthStart.days(to: today)
        let start = monthStart.startDate(in: timeZone)
        return (0..<points).map { index in
            let offset = points == 1 ? span : Int((Double(index * span) / Double(points - 1)).rounded())
            let day = monthStart.adding(days: offset)
            let interval = DateInterval(start: start, end: day.adding(days: 1).startDate(in: timeZone))
            return DailyTotal(day: day, total: total(entries, kind: kind, in: interval, currencyCode: currencyCode))
        }
    }

    /// Totals per category inside `interval`, largest first. Percentages are rounded so that
    /// they add up to exactly 100 (largest remainder method).
    public static func categoryBreakdown(
        _ entries: [LedgerEntry],
        kind: LedgerKind = .expense,
        in interval: DateInterval,
        currencyCode: String
    ) -> [CategoryShare] {
        let code = currencyCode.uppercased()
        var sums: [LedgerCategory: Int64] = [:]
        for entry in entries where entry.kind == kind && entry.currencyCode == code && interval.containsExcludingEnd(entry.occurredAt) {
            sums[entry.category, default: 0] += entry.amountMinor
        }
        // Largest first; equal amounts keep the order of `allCases`, so the result never depends
        // on the order of `entries`.
        let categories = LedgerCategory.allCases.enumerated()
            .filter { (sums[$0.element] ?? 0) > 0 }
            .sorted { lhs, rhs in
                let left = sums[lhs.element] ?? 0
                let right = sums[rhs.element] ?? 0
                return left != right ? left > right : lhs.offset < rhs.offset
            }
            .map(\.element)
        let total = categories.reduce(Int64(0)) { $0 + (sums[$1] ?? 0) }
        guard total > 0 else { return [] }

        var percents = categories.map { Int((sums[$0] ?? 0) * 100 / total) }
        let remainders = categories.map { (sums[$0] ?? 0) * 100 % total }
        let leftover = 100 - percents.reduce(0, +)
        // Categories are already sorted by amount, so ties in the remainder go to the larger one.
        let byRemainder = categories.indices.sorted { remainders[$0] > remainders[$1] || (remainders[$0] == remainders[$1] && $0 < $1) }
        for index in byRemainder.prefix(leftover) {
            percents[index] += 1
        }
        return categories.indices.map { index in
            CategoryShare(
                category: categories[index],
                amount: Money(minorUnits: sums[categories[index]] ?? 0, currencyCode: code),
                percent: percents[index]
            )
        }
    }

    /// Monday through `today` against the same weekdays of the week before.
    public static func weekToDate(
        _ entries: [LedgerEntry],
        kind: LedgerKind = .expense,
        today: LocalDate,
        currencyCode: String,
        timeZone: TimeZone
    ) -> PeriodComparison {
        let monday = today.startOfISOWeek
        return compare(
            entries, kind: kind,
            current: (monday, today),
            previous: (monday.adding(days: -7), today.adding(days: -7)),
            currencyCode: currencyCode, timeZone: timeZone
        )
    }

    /// The 1st through `today` against the same days of the month before. On the last day of a
    /// month the whole previous month counts.
    public static func monthToDate(
        _ entries: [LedgerEntry],
        kind: LedgerKind = .expense,
        today: LocalDate,
        currencyCode: String,
        timeZone: TimeZone
    ) -> PeriodComparison {
        let previousStart = today.startOfMonth.adding(months: -1)
        let previousLast = today.startOfMonth.adding(days: -1)
        let isLastDay = today.day == LocalDate.daysInMonth(year: today.year, month: today.month)
        return compare(
            entries, kind: kind,
            current: (today.startOfMonth, today),
            previous: (previousStart, isLastDay ? previousLast : min(today.adding(months: -1), previousLast)),
            currencyCode: currencyCode, timeZone: timeZone
        )
    }

    /// Relative change from `previous` to `current`, or nil when `previous` is zero or in
    /// another currency.
    public static func percentChange(from previous: Money, to current: Money) -> Double? {
        guard previous.minorUnits != 0, previous.currencyCode == current.currencyCode else { return nil }
        return Double(current.minorUnits - previous.minorUnits) / Double(previous.minorUnits.magnitude)
    }

    private static func compare(
        _ entries: [LedgerEntry],
        kind: LedgerKind,
        current: (first: LocalDate, last: LocalDate),
        previous: (first: LocalDate, last: LocalDate),
        currencyCode: String,
        timeZone: TimeZone
    ) -> PeriodComparison {
        func interval(_ days: (first: LocalDate, last: LocalDate)) -> DateInterval {
            DateInterval(start: days.first.startDate(in: timeZone), end: days.last.adding(days: 1).startDate(in: timeZone))
        }
        return PeriodComparison(
            current: total(entries, kind: kind, in: interval(current), currencyCode: currencyCode),
            previous: total(entries, kind: kind, in: interval(previous), currencyCode: currencyCode)
        )
    }
}

extension DateInterval {
    /// Like `contains(_:)` but without the end, so back-to-back intervals never share an instant.
    func containsExcludingEnd(_ date: Date) -> Bool {
        start <= date && date < end
    }
}
