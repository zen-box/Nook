import Foundation

public struct WidgetSnapshot: Codable, Sendable {
    public static let group = "group.com.nook.personal"
    public static let filename = "nook-widget.json"
    public var updatedAt: Date
    public var eventTitle: String?
    public var eventStart: Date?
    public var taskTitles: [String]
    public var openTaskCount: Int
    public var anniversaryTitle: String?
    public var anniversaryDate: LocalDate?
    public var showsDetails: Bool
    public var agenda: [WidgetAgendaItem]?
    public var trip: WidgetTripItem?
    public var noteTitle: String?
    public var noteCount: Int?
    public var timeZoneID: String?
    public init(updatedAt: Date = Date(), eventTitle: String? = nil, eventStart: Date? = nil,
                taskTitles: [String] = [], openTaskCount: Int = 0, anniversaryTitle: String? = nil,
                anniversaryDate: LocalDate? = nil, showsDetails: Bool = false,
                agenda: [WidgetAgendaItem]? = nil, trip: WidgetTripItem? = nil,
                noteTitle: String? = nil, noteCount: Int? = nil, timeZoneID: String? = nil) {
        self.updatedAt = updatedAt; self.eventTitle = eventTitle; self.eventStart = eventStart
        self.taskTitles = taskTitles; self.openTaskCount = openTaskCount
        self.anniversaryTitle = anniversaryTitle; self.anniversaryDate = anniversaryDate; self.showsDetails = showsDetails
        self.agenda = agenda; self.trip = trip; self.noteTitle = noteTitle; self.noteCount = noteCount; self.timeZoneID = timeZoneID
    }

    public static func make(notes: [Note], events: [ScheduleEvent], trips: [TripPlan], tasks: [TaskItem],
                            anniversaries: [Anniversary], details: Bool, now: Date = Date(), timeZone: TimeZone = .current) -> Self {
        let today = LocalDate(now, timeZone: timeZone)
        let interval = DateInterval(start: today.startDate(in: timeZone), end: today.adding(days: 8).startDate(in: timeZone))
        let upcoming = ScheduleQuery.upcoming(events.flatMap { $0.occurrences(in: interval) }, after: now, limit: 8)
        let openTasks = tasks.filter { !$0.isCompleted }.sorted { ($0.dueAt ?? .distantFuture, $0.title) < ($1.dueAt ?? .distantFuture, $1.title) }
        let nextAnniversary = anniversaries.compactMap { a -> (Anniversary, LocalDate)? in
            guard let day = a.nextOccurrence(onOrAfter: today) else { return nil }
            return (a, day)
        }.sorted { ($0.1, $0.0.title) < ($1.1, $1.0.title) }.first
        let nextTrip = trips.filter { $0.endDate >= today }.sorted { ($0.startDate, $0.title) < ($1.startDate, $1.title) }.first
        let tripItem = nextTrip.map { trip in
            let segment = upcoming.first { $0.planID == trip.id && $0.transport != nil }
            return WidgetTripItem(title: details ? trip.title : nil, destination: details ? trip.destination : nil,
                startDate: trip.startDate, endDate: trip.endDate, departure: segment?.start,
                route: details ? segment?.transport.map(ReminderPlan.transportText) : nil)
        }
        let visibleNotes = notes.filter { !$0.isBlank }.sorted { $0.updatedAt > $1.updatedAt }
        let noteTitle = visibleNotes.first?.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return Self(updatedAt: now, eventTitle: details ? upcoming.first?.title : nil, eventStart: upcoming.first?.start,
            taskTitles: details ? Array(openTasks.prefix(3).map(\.title)) : [], openTaskCount: openTasks.count,
            anniversaryTitle: details ? nextAnniversary?.0.title : nil, anniversaryDate: nextAnniversary?.1, showsDetails: details,
            agenda: upcoming.map { WidgetAgendaItem(title: details ? $0.title : nil, start: $0.start, end: $0.effectiveEnd, allDay: $0.isAllDay) },
            trip: tripItem, noteTitle: details && noteTitle?.isEmpty == false ? noteTitle : nil, noteCount: visibleNotes.count, timeZoneID: timeZone.identifier)
    }
}

public struct WidgetAgendaItem: Codable, Sendable {
    public var title: String?
    public var start: Date
    public var end: Date
    public var allDay: Bool
}
public struct WidgetTripItem: Codable, Sendable {
    public var title: String?
    public var destination: String?
    public var startDate: LocalDate
    public var endDate: LocalDate
    public var departure: Date?
    public var route: String?
}
public enum WidgetSharedData: Sendable {
    case ready(WidgetSnapshot), groupUnavailable, awaitingData, unreadableData
    public static func read(directory: URL?) -> Self {
        guard let directory else { return .groupUnavailable }
        let file = directory.appending(path: WidgetSnapshot.filename)
        guard FileManager.default.fileExists(atPath: file.path) else { return .awaitingData }
        do { return .ready(try NookJSON.makeDecoder().decode(WidgetSnapshot.self, from: Data(contentsOf: file))) }
        catch { return .unreadableData }
    }
    public var snapshot: WidgetSnapshot? { if case .ready(let value) = self { return value }; return nil }
}
