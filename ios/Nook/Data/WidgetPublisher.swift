import Foundation
import WidgetKit
import NookCore

@MainActor
enum WidgetPublisher {
    static var isAvailable: Bool { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.group) != nil }
    static func publish(_ store: AppStore) {
        guard let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.group) else { return }
        let now = Date(), today = LocalDate.today(in: store.timeZone)
        let next = store.todaysAgenda(now: now).first
        let tasks = store.tasks.filter { !$0.isCompleted }.sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
        let anniversary = store.nextAnniversary(today: today)
        let details = store.defaults.bool(forKey: "widgets.details")
        let snapshot = WidgetSnapshot(updatedAt: now, eventTitle: details ? next?.title : nil, eventStart: next?.start,
            taskTitles: details ? Array(tasks.prefix(3).map(\.title)) : [], openTaskCount: tasks.count,
            anniversaryTitle: details ? anniversary?.anniversary.title : nil, anniversaryDate: anniversary?.date, showsDetails: details)
        do {
            try NookJSON.makeEncoder().encode(snapshot).write(to: folder.appending(path: WidgetSnapshot.filename), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            WidgetCenter.shared.reloadAllTimelines()
        } catch { store.defaults.set(String(localized: "Widget data could not be updated."), forKey: "widgets.error") }
    }
}
