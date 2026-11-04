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
    public init(updatedAt: Date = Date(), eventTitle: String? = nil, eventStart: Date? = nil,
                taskTitles: [String] = [], openTaskCount: Int = 0, anniversaryTitle: String? = nil,
                anniversaryDate: LocalDate? = nil, showsDetails: Bool = false) {
        self.updatedAt = updatedAt; self.eventTitle = eventTitle; self.eventStart = eventStart
        self.taskTitles = taskTitles; self.openTaskCount = openTaskCount
        self.anniversaryTitle = anniversaryTitle; self.anniversaryDate = anniversaryDate; self.showsDetails = showsDetails
    }
}
