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
        let selected = Array(Set(weekdays.isEmpty ? [firstWeekday] : weekdays)).sorted()
        let final = min(endsOn ?? LocalDate(range.end, timeZone: zone), LocalDate(range.end, timeZone: zone))
        guard final >= origin else { return [] }
        let lower = max(origin, LocalDate(range.start, timeZone: zone))
        let excluded = Set(excludedDates)
        let weekOrigin = origin.adding(days: 1 - firstWeekday)
        let firstWeekCount = selected.filter { $0 >= firstWeekday }.count
        let fractionalSecond = anchor.timeIntervalSince1970 - floor(anchor.timeIntervalSince1970)
        // Jump directly to the relevant period. A ten-year-old daily rule should not scan
        // thousands of intervening days every time a week strip or widget is refreshed.
        var period: Int
        switch frequency {
        case .daily: period = max(0, origin.days(to: lower) / interval - 1)
        case .weekly: period = max(0, weekOrigin.days(to: lower) / (7 * interval) - 1)
        case .monthly: period = max(0, ((lower.year - origin.year) * 12 + lower.month - origin.month) / interval - 1)
        case .yearly: period = max(0, (lower.year - origin.year) / interval - 1)
        }
        var result: [Date] = []
        // Calendar rules, never fixed 24-hour arithmetic: preserves local clock time across DST.
        while true {
            let days: [LocalDate]
            var ordinal: Int
            switch frequency {
            case .daily:
                days = [origin.adding(days: period * interval)]; ordinal = period
            case .weekly:
                let monday = weekOrigin.adding(days: period * interval * 7)
                days = selected.map { monday.adding(days: $0 - 1) }.filter { $0 >= origin }
                ordinal = period == 0 ? 0 : firstWeekCount + (period - 1) * selected.count
            case .monthly:
                let monthIndex = origin.year * 12 + origin.month - 1 + period * interval
                let year = monthIndex / 12, month = monthIndex % 12 + 1
                guard (1...9999).contains(year) else { return result }
                days = [LocalDate(year: year, month: month, day: min(origin.day, LocalDate.daysInMonth(year: year, month: month)))!]
                ordinal = period
            case .yearly:
                let year = origin.year + period * interval
                guard (1...9999).contains(year) else { return result }
                days = [origin.sameDay(inYear: year)]; ordinal = period
            }
            // The first weekly period can be empty when every selected weekday is before
            // the anchor. Subsequent periods still advance normally.
            if let first = days.first, first > final { return result }
            for day in days {
                ordinal += 1
                if day > final || occurrenceLimit.map({ ordinal > $0 }) == true { return result }
                let midnight = day.startDate(in: zone)
                if let base = calendar.date(bySettingHour: clock.hour ?? 0, minute: clock.minute ?? 0,
                                           second: clock.second ?? 0, of: midnight) {
                    let date = day == origin ? anchor : base.addingTimeInterval(fractionalSecond)
                    if date >= anchor, date >= range.start, date < range.end, !excluded.contains(day) {
                    result.append(date)
                    }
                }
            }
            period += 1
        }
    }
}

public extension ScheduleEvent {
    /// Derived instances are never stored as copies. Their series is the original record.
    func occurrences(in range: DateInterval) -> [ScheduleEvent] {
        guard let recurrence else { return overlaps(range) ? [self] : [] }
        let duration = effectiveEnd.timeIntervalSince(start)
        let search = DateInterval(start: range.start.addingTimeInterval(-duration - (isAllDay ? 86400 : 0)), end: range.end)
        return recurrence.starts(from: start, in: search).map { instance(starting: $0) }.filter { $0.overlaps(range) }
    }

    /// A stable UI identity distinguishes multiple projected occurrences of the same record.
    var displayID: String { "\(id)/\((occurrenceStart ?? start).timeIntervalSince1970)" }

    func instance(starting date: Date) -> ScheduleEvent {
        var copy = self
        copy.start = date
        if let end {
            if isAllDay, let zone = TimeZone(identifier: recurrence?.timeZoneID ?? TimeZone.current.identifier) {
                let daySpan = LocalDate(start, timeZone: zone).days(to: LocalDate(end, timeZone: zone))
                copy.end = LocalDate(date, timeZone: zone).adding(days: max(1, daySpan)).startDate(in: zone)
            } else { copy.end = date.addingTimeInterval(end.timeIntervalSince(start)) }
        }
        if let boarding = transport?.boardingAt { copy.transport?.boardingAt = date.addingTimeInterval(boarding.timeIntervalSince(start)) }
        copy.occurrenceStart = date
        return copy
    }
}
