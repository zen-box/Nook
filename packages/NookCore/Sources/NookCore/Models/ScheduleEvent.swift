import Foundation

public enum EventCategory: String, Codable, CaseIterable, Sendable {
    case work
    case travel
    case personal
    case health
    case other
}

/// A calendar entry. All-day events span whole days: `start` is midnight of the first day and
/// `end` is midnight after the last day, in the time zone they were created in.
public struct ScheduleEvent: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var start: Date
    public var end: Date?
    public var isAllDay: Bool
    public var location: String?
    public var notes: String
    public var category: EventCategory
    /// Minutes before `start` to remind, nil for no reminder.
    public var reminderMinutes: Int?
    public var planID: UUID?
    public var recurrence: EventRecurrence?
    public var transport: TransportDetails?
    /// Stored overrides refer back to the series. Derived projections set occurrenceStart.
    public var seriesID: UUID?
    public var occurrenceStart: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUIDv7.make(),
        title: String,
        start: Date,
        end: Date? = nil,
        isAllDay: Bool = false,
        location: String? = nil,
        notes: String = "",
        category: EventCategory = .other,
        reminderMinutes: Int? = nil,
        planID: UUID? = nil,
        recurrence: EventRecurrence? = nil,
        transport: TransportDetails? = nil,
        seriesID: UUID? = nil,
        occurrenceStart: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
        self.category = category
        self.reminderMinutes = reminderMinutes
        self.planID = planID
        self.recurrence = recurrence
        self.transport = transport
        self.seriesID = seriesID
        self.occurrenceStart = occurrenceStart
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    /// When the event is over. Events without an end take no time.
    public var effectiveEnd: Date {
        max(end ?? start, start)
    }

    /// Whether any part of the event falls inside `interval` (end excluded).
    public func overlaps(_ interval: DateInterval) -> Bool {
        let finish = effectiveEnd
        if finish == start {
            return interval.start <= start && start < interval.end
        }
        return start < interval.end && finish > interval.start
    }

    public func occurs(on day: LocalDate, timeZone: TimeZone) -> Bool {
        overlaps(day.interval(in: timeZone))
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case start
        case end
        case isAllDay = "all_day"
        case location
        case notes
        case category
        case reminderMinutes = "reminder_minutes"
        case planID = "plan_id"
        case recurrence, transport
        case seriesID = "series_id"
        case occurrenceStart = "occurrence_start"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
