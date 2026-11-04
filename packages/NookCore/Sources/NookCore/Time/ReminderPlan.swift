import Foundation

public struct PlannedReminder: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public var fireDate: Date
    public var repeating: DateComponents?
    public init(id: String, title: String, detail: String = "", fireDate: Date, repeating: DateComponents? = nil) {
        self.id = id; self.title = title; self.detail = detail; self.fireDate = fireDate; self.repeating = repeating
    }
}
public enum ReminderPlan {
    public static func make(events: [ScheduleEvent], tasks: [TaskItem], anniversaries: [Anniversary],
                            now: Date, timeZone: TimeZone = .current, limit: Int = 60) -> [PlannedReminder] {
        var result: [PlannedReminder] = []
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let until = calendar.date(byAdding: .year, value: 2, to: now) ?? now.addingTimeInterval(730 * 86400)
        for event in events {
            guard let minutes = event.reminderMinutes, minutes >= 0 else { continue }
            // Unbounded daily/weekly rules use native repeating requests, not a finite series.
            if let rule = event.recurrence, rule.interval == 1, rule.endsOn == nil,
               rule.occurrenceLimit == nil, rule.excludedDates.isEmpty,
               rule.frequency == .daily || rule.frequency == .weekly,
               event.start <= now, let zone = TimeZone(identifier: rule.timeZoneID) {
                var local = calendar; local.timeZone = zone
                let weekdays = rule.weekdays.isEmpty ? [LocalDate(event.start, timeZone: zone).isoWeekday] : rule.weekdays
                let days = rule.frequency == .daily ? [0] : weekdays
                for weekday in days {
                    var start = event.start
                    if weekday != 0 {
                        let origin = LocalDate(event.start, timeZone: zone)
                        start = origin.adding(days: (weekday - origin.isoWeekday + 7) % 7).date(
                            hour: local.component(.hour, from: event.start), minute: local.component(.minute, from: event.start), in: zone)
                    }
                    let fire = start.addingTimeInterval(-Double(minutes) * 60)
                    var components = local.dateComponents([.hour, .minute], from: fire)
                    if weekday != 0 { components.weekday = local.component(.weekday, from: fire) }
                    components.timeZone = zone
                    let next = local.nextDate(after: now, matching: components, matchingPolicy: .nextTime) ?? fire
                    result.append(.init(id: "event-\(event.id)-repeat-\(weekday)", title: event.title,
                                        detail: event.transport.map(transportText) ?? event.location ?? "", fireDate: next, repeating: components))
                }
                continue
            }
            let range = DateInterval(start: now, end: until.addingTimeInterval(Double(minutes) * 60))
            for instance in event.occurrences(in: range) {
                let fire = instance.start.addingTimeInterval(-Double(minutes) * 60)
                guard fire > now else { continue }
                result.append(.init(id: "event-\(event.id)-\(Int64(instance.start.timeIntervalSince1970))", title: event.title,
                                    detail: instance.transport.map(transportText) ?? instance.location ?? "", fireDate: fire))
            }
        }
        for task in tasks where !task.isCompleted {
            guard let due = task.dueAt, let minutes = task.reminderMinutes, minutes >= 0 else { continue }
            let fire = due.addingTimeInterval(-Double(minutes) * 60)
            if fire > now { result.append(.init(id: "task-\(task.id)", title: task.title, detail: task.notes, fireDate: fire)) }
        }
        let today = LocalDate(now, timeZone: timeZone)
        for anniversary in anniversaries {
            guard let reminder = anniversary.reminder, (0...23).contains(reminder.hour), (0...59).contains(reminder.minute) else { continue }
            // Include next year's occurrence even if today's notification time already passed.
            var nextDay = today
            for _ in 0..<3 {
                guard let date = anniversary.nextOccurrence(onOrAfter: nextDay) else { break }
                for before in Set(reminder.daysBefore) where (0...365).contains(before) {
                    let fire = date.adding(days: -before).date(hour: reminder.hour, minute: reminder.minute, in: timeZone)
                    if fire > now {
                        result.append(.init(id: "anniversary-\(anniversary.id)-\(date)-\(before)", title: anniversary.title,
                                            detail: date.isoString, fireDate: fire))
                    }
                }
                if anniversary.repeatRule == .never { break }
                nextDay = date.adding(days: 1)
            }
        }
        return Array(result.sorted { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }.prefix(max(0, limit)))
    }
    public static func transportText(_ t: TransportDetails) -> String {
        [t.number, t.departure, t.arrival, t.terminal, t.gate, t.platform, t.carriage, t.seat].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
