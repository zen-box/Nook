import Foundation

public struct EventRecurrence: Hashable, Codable, Sendable {
    public enum Frequency: String, CaseIterable, Codable, Sendable { case daily, weekly, monthly, yearly }
    public var frequency: Frequency
    public var interval: Int
    /// ISO weekdays: Monday = 1, Sunday = 7. Empty means the original weekday.
    public var weekdays: [Int]
    public var timeZoneID: String
    public var endsOn: LocalDate?
    public var occurrenceLimit: Int?
    public var excludedDates: [LocalDate]

    public init(frequency: Frequency, interval: Int = 1, weekdays: [Int] = [],
                timeZoneID: String = TimeZone.current.identifier, endsOn: LocalDate? = nil,
                occurrenceLimit: Int? = nil, excludedDates: [LocalDate] = []) {
        self.frequency = frequency; self.interval = interval; self.weekdays = weekdays
        self.timeZoneID = timeZoneID; self.endsOn = endsOn; self.occurrenceLimit = occurrenceLimit
        self.excludedDates = excludedDates
    }

    public var isValid: Bool {
        (1...999).contains(interval) && weekdays.allSatisfy { (1...7).contains($0) }
            && TimeZone(identifier: timeZoneID) != nil && (occurrenceLimit.map { (1...100_000).contains($0) } ?? true)
    }

    public func starts(from anchor: Date, in range: DateInterval) -> [Date] {
        guard isValid, range.end > anchor, let zone = TimeZone(identifier: timeZoneID) else { return [] }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let origin = LocalDate(anchor, timeZone: zone)
        let clock = calendar.dateComponents([.hour, .minute, .second], from: anchor)
        let firstWeekday = origin.isoWeekday
        let selected = weekdays.isEmpty ? [firstWeekday] : weekdays
        let final = min(endsOn ?? LocalDate(range.end, timeZone: zone), LocalDate(range.end, timeZone: zone))
        var day = origin
        var ordinal = 0
        var result: [Date] = []
        // Calendar rules, never fixed 24-hour arithmetic: preserves local clock time across DST.
        while day <= final {
            let offset = origin.days(to: day)
            let week = (offset + firstWeekday - 1) / 7
            let weekday = ((firstWeekday - 1 + offset) % 7) + 1
            let months = (day.year - origin.year) * 12 + day.month - origin.month
            let matches: Bool
            switch frequency {
            case .daily: matches = offset % interval == 0
            case .weekly: matches = week % interval == 0 && selected.contains(weekday)
            case .monthly:
                matches = months % interval == 0 && day.day == min(origin.day, LocalDate.daysInMonth(year: day.year, month: day.month))
            case .yearly:
                matches = (day.year - origin.year) % interval == 0 && day == origin.sameDay(inYear: day.year)
            }
            if matches {
                ordinal += 1
                if let limit = occurrenceLimit, ordinal > limit { break }
                let midnight = day.startDate(in: zone)
                if let date = calendar.date(bySettingHour: clock.hour ?? 0, minute: clock.minute ?? 0,
                                            second: clock.second ?? 0, of: midnight),
                   date >= anchor, date >= range.start, date < range.end, !excludedDates.contains(day) {
                    result.append(date)
                }
            }
            day = day.adding(days: 1)
        }
        return result
    }
}

public extension ScheduleEvent {
    /// Derived instances are never stored as copies. Their series is the original record.
    func occurrences(in range: DateInterval) -> [ScheduleEvent] {
        guard let recurrence else { return overlaps(range) ? [self] : [] }
        let duration = effectiveEnd.timeIntervalSince(start)
        let search = DateInterval(start: range.start.addingTimeInterval(-duration), end: range.end)
        return recurrence.starts(from: start, in: search).map { date in
            var copy = self
            copy.start = date
            copy.end = end.map { _ in date.addingTimeInterval(duration) }
            copy.occurrenceStart = date
            return copy
        }
    }
}
