import Foundation

/// A trip spanning whole days. Events link to it through `ScheduleEvent.planID`.
public struct TripPlan: Identifiable, Hashable, Codable, Sendable {
    public enum Phase: Hashable, Sendable {
        case upcoming
        case ongoing
        case finished
    }

    public var id: UUID
    public var title: String
    public var destination: String?
    public var startDate: LocalDate
    public var endDate: LocalDate
    public var summary: String
    public var noteID: UUID?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUIDv7.make(),
        title: String,
        destination: String? = nil,
        startDate: LocalDate,
        endDate: LocalDate,
        summary: String = "",
        noteID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.destination = destination
        self.startDate = startDate
        self.endDate = max(startDate, endDate)
        self.summary = summary
        self.noteID = noteID
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    public var dayCount: Int {
        startDate.days(to: endDate) + 1
    }

    public func phase(on today: LocalDate) -> Phase {
        if today < startDate { return .upcoming }
        if today > endDate { return .finished }
        return .ongoing
    }

    /// The 1-based day of the trip that `date` is, or nil outside the trip.
    public func dayNumber(of date: LocalDate) -> Int? {
        guard date >= startDate, date <= endDate else { return nil }
        return startDate.days(to: date) + 1
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case destination
        case startDate = "start_date"
        case endDate = "end_date"
        case summary
        case noteID = "note_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
