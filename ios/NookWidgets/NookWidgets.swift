import SwiftUI
import WidgetKit
import NookCore

private struct NookEntry: TimelineEntry {
    var date: Date
    var data: WidgetSharedData
}
private struct NookProvider: TimelineProvider {
    func placeholder(in context: Context) -> NookEntry {
        NookEntry(date: .now, data: .ready(WidgetSnapshot(openTaskCount: 3)))
    }
    func getSnapshot(in context: Context, completion: @escaping (NookEntry) -> Void) { completion(read()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<NookEntry>) -> Void) {
        let entry = read()
        var dates = [entry.date]
        if let snapshot = entry.data.snapshot {
            dates += (snapshot.agenda ?? []).flatMap { [$0.start, $0.end] }.filter { $0 > entry.date }
            let zone = snapshot.timeZoneID.flatMap(TimeZone.init(identifier:)) ?? .current
            dates.append(LocalDate(entry.date, timeZone: zone).adding(days: 1).startDate(in: zone))
        }
        let entries = Set(dates).sorted().prefix(18).map { NookEntry(date: $0, data: entry.data) }
        completion(Timeline(entries: Array(entries), policy: .after(entry.date.addingTimeInterval(900))))
    }
    private func read() -> NookEntry {
        NookEntry(date: .now, data: .read(directory: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.group)))
    }
}
private struct ContentWidgetView: View {
    let kind: NookWidgetContentKind
    let entry: NookEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        NookWidgetContent(kind: kind, data: entry.data, date: entry.date,
                          medium: family == .systemMedium, compact: family == .accessoryRectangular)
            .containerBackground(.fill.tertiary, for: .widget)
            .widgetURL(kind.url)
    }
}
struct NookTodayWidget: Widget {
    let kind = "NookToday"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NookProvider()) { ContentWidgetView(kind: .schedule, entry: $0) }
            .configurationDisplayName("Today in Nook")
            .description("Upcoming calendar events, with a task count. Details are hidden until you enable them in Nook.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}
struct NookTripWidget: Widget {
    let kind = "NookTrips"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NookProvider()) { ContentWidgetView(kind: .trips, entry: $0) }
            .configurationDisplayName("Next Trip").description("Your next trip, departure time and travel details.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
struct NookNoteWidget: Widget {
    let kind = "NookNotes"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NookProvider()) { ContentWidgetView(kind: .notes, entry: $0) }
            .configurationDisplayName("Recent Note").description("Keep your latest note title nearby. Note bodies stay in Nook.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
struct NookAnniversaryWidget: Widget {
    let kind = "NookAnniversary"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NookProvider()) { ContentWidgetView(kind: .anniversary, entry: $0) }
            .configurationDisplayName("Anniversary Countdown").description("Keep an important date close.")
            .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}
struct NookQuickWidget: Widget {
    let kind = "NookQuick"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NookProvider()) { _ in
            HStack {
                Link(destination: URL(string: "nook://assistant")!) { Label("Ask Nook", systemImage: "sparkles").frame(maxWidth: .infinity) }
                Link(destination: URL(string: "nook://expense")!) { Label("Expense", systemImage: "plus.circle").frame(maxWidth: .infinity) }
                Link(destination: URL(string: "nook://note")!) { Label("Note", systemImage: "square.and.pencil").frame(maxWidth: .infinity) }
            }.font(.caption).containerBackground(.fill.tertiary, for: .widget)
        }.configurationDisplayName("Nook Shortcuts").description("Open the assistant, add an expense or write a note.").supportedFamilies([.systemMedium])
    }
}
@main struct NookWidgets: WidgetBundle {
    var body: some Widget { NookTodayWidget(); NookTripWidget(); NookNoteWidget(); NookAnniversaryWidget(); NookQuickWidget() }
}