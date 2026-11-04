import Foundation
import WidgetKit
import NookCore

@MainActor
enum WidgetPublisher {
    enum Status: Equatable { case notPublished, unavailable, updated(Date), failed }
    static var isAvailable: Bool { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.group) != nil }
    static func publish(_ store: AppStore) {
        guard let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.group) else {
            store.widgetSharingStatus = .unavailable
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        let now = Date()
        let details = store.defaults.bool(forKey: "widgets.details")
        let snapshot = WidgetSnapshot.make(notes: store.notes, events: store.events, trips: store.trips, tasks: store.tasks,
            anniversaries: store.anniversaries, details: details, now: now, timeZone: store.timeZone)
        do {
            try NookJSON.makeEncoder().encode(snapshot).write(to: folder.appending(path: WidgetSnapshot.filename), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            store.widgetSharingStatus = .updated(now)
            store.defaults.removeObject(forKey: "widgets.error")
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            store.widgetSharingStatus = .failed
            store.defaults.set(String(localized: "Widget data could not be updated."), forKey: "widgets.error")
        }
    }
}
