import Foundation

/// A Gregorian calendar date without a time of day or time zone, such as an anniversary
/// or a trip day. Encoded as "YYYY-MM-DD".
public struct LocalDate: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init?(year: Int, month: Int, day: Int) {
        guard (1...9999).contains(year), (1...12).contains(month),
              (1...LocalDate.daysInMonth(year: year, month: month)).contains(day) else { return nil }
        self.init(unchecked: year, month, day)
    }

    init(unchecked year: Int, _ month: Int, _ day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The date that `instant` falls on in `timeZone`.
    public init(_ instant: Date, timeZone: TimeZone) {
        let parts = Calendar.gregorian(timeZone).dateComponents([.year, .month, .day], from: instant)
        self.init(unchecked: parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }

    public static func today(in timeZone: TimeZone = .current, now: Date = Date()) -> LocalDate {
        LocalDate(now, timeZone: timeZone)
    }

    public init?(isoString: String) {
        let parts = isoString.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.utf8.allSatisfy { $0 >= 48 && $0 <= 57 } }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return nil }
        self.init(year: year, month: month, day: day)
    }

    public var isoString: String {
        func pad(_ value: Int, _ width: Int) -> String {
            let text = String(value)
            return String(repeating: "0", count: max(0, width - text.count)) + text
        }
        return "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))"
    }

    public var description: String { isoString }

    /// Midnight at the start of this date in `timeZone`.
    public func startDate(in timeZone: TimeZone) -> Date {
        let calendar = Calendar.gregorian(timeZone)
        // Build from noon: some time zones skip midnight on DST change days.
        guard let noon = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) else {
            preconditionFailure("Invalid LocalDate \(isoString)")
        }
        return calendar.startOfDay(for: noon)
    }

    /// The instant at `hour`:`minute` on this date in `timeZone`.
    public func date(hour: Int, minute: Int = 0, in timeZone: TimeZone) -> Date {
        let calendar = Calendar.gregorian(timeZone)
        guard let value = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) else {
            preconditionFailure("Invalid time \(hour):\(minute) on \(isoString)")
        }
        return value
    }

    /// From the start of this date to the start of the next one, in `timeZone`.
    public func interval(in timeZone: TimeZone) -> DateInterval {
        DateInterval(start: startDate(in: timeZone), end: adding(days: 1).startDate(in: timeZone))
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

// MARK: - Day arithmetic

extension LocalDate {
    /// Julian Day Number (Fliegel & Van Flandern), e.g. 2000-01-01 is 2451545.
    public var julianDay: Int {
        let a = (14 - month) / 12
        let y = year + 4800 - a
        let m = month + 12 * a - 3
        return day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
    }

    public init(julianDay: Int) {
        let a = julianDay + 32044
        let b = (4 * a + 3) / 146097
        let c = a - 146097 * b / 4
        let d = (4 * c + 3) / 1461
        let e = c - 1461 * d / 4
        let m = (5 * e + 2) / 153
        self.init(unchecked: 100 * b + d - 4800 + m / 10, m + 3 - 12 * (m / 10), e - (153 * m + 2) / 5 + 1)
    }

    /// ISO 8601 weekday: 1 is Monday, 7 is Sunday.
    public var isoWeekday: Int { julianDay % 7 + 1 }

    public func adding(days: Int) -> LocalDate {
        LocalDate(julianDay: julianDay + days)
    }

    /// Whole days from this date to `other` (negative when `other` is earlier).
    public func days(to other: LocalDate) -> Int {
        other.julianDay - julianDay
    }

    /// The Monday of this date's week.
    public var startOfISOWeek: LocalDate { adding(days: 1 - isoWeekday) }

    /// Monday through Sunday of this date's week.
    public var isoWeek: [LocalDate] {
        let monday = startOfISOWeek
        return (0..<7).map { monday.adding(days: $0) }
    }

    public var startOfMonth: LocalDate { LocalDate(unchecked: year, month, 1) }

    /// Moves by whole months, clamping the day to the target month's length (Jan 31 + 1 month = Feb 28/29).
    public func adding(months: Int) -> LocalDate {
        let index = year * 12 + (month - 1) + months
        let newYear = Int((Double(index) / 12).rounded(.down))
        let newMonth = index - newYear * 12 + 1
        return LocalDate(unchecked: newYear, newMonth, min(day, LocalDate.daysInMonth(year: newYear, month: newMonth)))
    }

    /// This month and day in another year. Feb 29 becomes Feb 28 in common years.
    public func sameDay(inYear targetYear: Int) -> LocalDate {
        LocalDate(unchecked: targetYear, month, min(day, LocalDate.daysInMonth(year: targetYear, month: month)))
    }

    public static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    public static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2: return isLeapYear(year) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }
}

// MARK: - Codable

extension LocalDate: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let value = LocalDate(isoString: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected YYYY-MM-DD, got \(text)")
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(isoString)
    }
}

extension Calendar {
    /// A Gregorian calendar in `timeZone`, independent of the user's calendar setting.
    static func gregorian(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}
