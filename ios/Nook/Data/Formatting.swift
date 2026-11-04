import Foundation
import SwiftUI
import NookCore

extension LocalDate {
    /// Noon on this day in the current time zone, for formatting as a date.
    var noon: Date { date(hour: 12, in: .current) }
}

enum TimeText {
    /// "09:05". The reference design uses a 24-hour clock.
    static func time(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02ld:%02ld", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// "10:00 – 11:00", or just the start when there is no end.
    static func range(_ start: Date, _ end: Date?) -> String {
        guard let end, end > start else { return time(start) }
        return "\(time(start)) – \(time(end))"
    }
}

enum DateText {
    /// "Nov 4"
    static func monthDay(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// "Nov 2 – Nov 8"
    static func range(_ days: [LocalDate]) -> String {
        guard let first = days.first, let last = days.last else { return "" }
        return "\(monthDay(first.noon)) – \(monthDay(last.noon))"
    }
}

enum Greeting {
    case morning, afternoon, evening

    init(now: Date, calendar: Calendar = .current) {
        switch calendar.component(.hour, from: now) {
        case 5..<12: self = .morning
        case 12..<18: self = .afternoon
        default: self = .evening
        }
    }

    var text: LocalizedStringKey {
        switch self {
        case .morning: "Good Morning"
        case .afternoon: "Good Afternoon"
        case .evening: "Good Evening"
        }
    }
}
