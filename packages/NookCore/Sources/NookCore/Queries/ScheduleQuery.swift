import Foundation

public enum ScheduleQuery {
    /// Events taking place on `day`, all-day ones first, then by start time.
    public static func events(_ events: [ScheduleEvent], on day: LocalDate, timeZone: TimeZone) -> [ScheduleEvent] {
        let interval = day.interval(in: timeZone)
        return events.flatMap { $0.occurrences(in: interval) }.sorted(by: agendaOrder)
    }

    /// Events that are still going on or haven't started at `now`, soonest first.
    public static func upcoming(_ events: [ScheduleEvent], after now: Date, limit: Int = .max) -> [ScheduleEvent] {
        Array(
            events
                .filter { $0.effectiveEnd > now || $0.start >= now }
                .sorted { ($0.start, $0.title) < ($1.start, $1.title) }
                .prefix(limit)
        )
    }

    /// The days among `days` that have at least one event, for the dots under a week strip.
    public static func daysWithEvents(_ events: [ScheduleEvent], in days: [LocalDate], timeZone: TimeZone) -> Set<LocalDate> {
        Set(days.filter { day in
            let interval = day.interval(in: timeZone)
            return events.contains { !$0.occurrences(in: interval).isEmpty }
        })
    }

    /// All-day events first, then by start time, then by title.
    public static func agendaOrder(_ lhs: ScheduleEvent, _ rhs: ScheduleEvent) -> Bool {
        if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
        if lhs.start != rhs.start { return lhs.start < rhs.start }
        if lhs.title != rhs.title { return lhs.title < rhs.title }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
