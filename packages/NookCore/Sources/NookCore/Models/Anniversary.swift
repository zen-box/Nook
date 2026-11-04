import Foundation

public enum AnniversaryKind: String, Codable, CaseIterable, Sendable {
    case birthday
    case anniversary
    case personal
    case project
    case custom
}

public enum RepeatRule: String, Codable, CaseIterable, Sendable {
    case never = "none"
    case yearly
}

/// A date worth counting toward or from: birthdays, anniversaries, project starts.
public struct Anniversary: Identifiable, Hashable, Codable, Sendable {
    /// What a list row shows for an anniversary on a given day.
    public enum Status: Hashable, Sendable {
        /// The anniversary is today; `years` is how many years it marks (0 on the original date).
        case today(years: Int)
        /// The next occurrence is `days` away and marks `years` years.
        case upcoming(days: Int, years: Int)
        /// A one-off date `days` days in the past.
        case elapsed(days: Int)
    }

    public var id: UUID
    public var title: String
    public var date: LocalDate
    public var repeatRule: RepeatRule
    public var kind: AnniversaryKind
    public var notes: String
    public var showCountdown: Bool
    public var reminder: AnniversaryReminder?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUIDv7.make(),
        title: String,
        date: LocalDate,
        repeatRule: RepeatRule = .yearly,
        kind: AnniversaryKind = .anniversary,
        notes: String = "",
        showCountdown: Bool = true,
        reminder: AnniversaryReminder? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.repeatRule = repeatRule
        self.kind = kind
        self.notes = notes
        self.showCountdown = showCountdown
        self.reminder = reminder
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    /// The first day on or after `day` this anniversary falls on, or nil for a one-off date that
    /// has passed. Yearly dates on Feb 29 are observed on Feb 28 in common years.
    public func nextOccurrence(onOrAfter day: LocalDate) -> LocalDate? {
        if day <= date { return date }
        switch repeatRule {
        case .never:
            return nil
        case .yearly:
            let thisYear = date.sameDay(inYear: day.year)
            return thisYear >= day ? thisYear : date.sameDay(inYear: day.year + 1)
        }
    }

    public func status(on today: LocalDate) -> Status {
        guard let next = nextOccurrence(onOrAfter: today) else {
            return .elapsed(days: date.days(to: today))
        }
        let days = today.days(to: next)
        let years = next.year - date.year
        return days == 0 ? .today(years: years) : .upcoming(days: days, years: years)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case date
        case repeatRule = "repeat_rule"
        case kind = "category"
        case notes = "description"
        case showCountdown = "show_countdown"
        case reminder
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

public struct AnniversaryReminder: Hashable, Codable, Sendable {
    public var hour: Int
    public var minute: Int
    public var daysBefore: [Int]
    public init(hour: Int = 9, minute: Int = 0, daysBefore: [Int] = [0]) {
        self.hour = hour; self.minute = minute; self.daysBefore = daysBefore
    }
}
