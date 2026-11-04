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
    static func sync(events: [ScheduleEvent], tasks: [TaskItem] = [], anniversaries: [Anniversary] = [], now: Date = Date()) async {
        UserDefaults.standard.removeObject(forKey: "reminders.error")
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let reminders = ReminderPlan.make(events: events, tasks: tasks, anniversaries: anniversaries, now: now)
        let desired = Set(reminders.map { identifierPrefix + $0.id })
        let obsolete = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) && !desired.contains($0) }
        center.removePendingNotificationRequests(withIdentifiers: obsolete)
        guard !reminders.isEmpty else { return }
        var settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            settings = await center.notificationSettings()
        }
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        for reminder in reminders {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.detail
            content.sound = .default
            let components = reminder.repeating ?? Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.fireDate)
            let request = UNNotificationRequest(
                identifier: identifierPrefix + reminder.id,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: reminder.repeating != nil)
            )
            do { try await center.add(request) }
            catch { UserDefaults.standard.set(String(localized: "Some reminders could not be scheduled. Open Nook to retry."), forKey: "reminders.error") }
        }
    }
}
