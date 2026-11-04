import Foundation
import UserNotifications
import NookCore

/// Local notifications for event reminders. iOS keeps at most 64 pending requests per app, so
/// the next 60 reminders are scheduled and the list is rebuilt whenever events change.
enum ReminderScheduler {
    static let identifierPrefix = "event-reminder-"
    static let limit = 60

    /// The reminder times still ahead, soonest first.
    static func upcoming(_ events: [ScheduleEvent], now: Date) -> [(event: ScheduleEvent, fireDate: Date)] {
        let planned = events.compactMap { event -> (event: ScheduleEvent, fireDate: Date)? in
            guard let minutes = event.reminderMinutes, !event.isAllDay else { return nil }
            guard minutes >= 0 else { return nil }
            let fireDate = event.start.addingTimeInterval(-TimeInterval(minutes) * 60)
            return fireDate > now ? (event: event, fireDate: fireDate) : nil
        }
        return Array(planned.sorted { $0.fireDate < $1.fireDate }.prefix(limit))
    }

    /// Asks for permission the first time a reminder is needed, then replaces every pending
    /// reminder with the current list.
    static func sync(events: [ScheduleEvent], now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        let reminders = upcoming(events, now: now)
        guard !reminders.isEmpty else { return }
        var settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            settings = await center.notificationSettings()
        }
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        for reminder in reminders {
            let content = UNMutableNotificationContent()
            content.title = reminder.event.title
            var lines = [String(localized: "Starts at \(TimeText.time(reminder.event.start))")]
            if let location = reminder.event.location, !location.isEmpty {
                lines.append(location)
            }
            content.body = lines.joined(separator: " · ")
            content.sound = .default
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.fireDate)
            let request = UNNotificationRequest(
                identifier: identifierPrefix + reminder.event.id.uuidString,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }
}
