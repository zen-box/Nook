import SwiftUI
import WidgetKit
import NookCore

private struct NookEntry: TimelineEntry { var date: Date; var snapshot: WidgetSnapshot? }
private struct NookProvider: TimelineProvider {
    func placeholder(in context: Context) -> NookEntry { NookEntry(date: .now, snapshot: WidgetSnapshot(openTaskCount: 3)) }
    func getSnapshot(in context: Context, completion: @escaping (NookEntry) -> Void) { completion(read()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<NookEntry>) -> Void) {
        completion(Timeline(entries: [read()], policy: .after(Date().addingTimeInterval(1800))))
    }
    private func read() -> NookEntry {
        let snapshot = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.group)
            .flatMap { try? Data(contentsOf: $0.appending(path: WidgetSnapshot.filename)) }
            .flatMap { try? NookJSON.makeDecoder().decode(WidgetSnapshot.self, from: $0) }
        return NookEntry(date: .now, snapshot: snapshot)
    }
}
private struct TodayWidgetView: View {
    let entry: NookEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Nook", systemImage: "leaf").font(.caption.bold()).foregroundStyle(.blue)
            if let snapshot = entry.snapshot {
                if let date = snapshot.eventStart, date > entry.date {
                    Text(snapshot.eventTitle ?? String(localized: "Next Event")).font(.headline).lineLimit(1).privacySensitive(snapshot.showsDetails)
                    Text(date, style: .time).font(.title3.monospacedDigit())
                } else { Text("Today").font(.headline) }
                Text("\(snapshot.openTaskCount) tasks remaining").font(.caption)
                if family == .systemMedium {
                    ForEach(Array(snapshot.taskTitles.enumerated()), id: \.offset) { _, title in
                        Label { Text(verbatim: title).lineLimit(1) } icon: { Image(systemName: "circle") }.font(.caption).privacySensitive()
                    }
                }
            } else { Text("Open Nook to set up widget sharing.").font(.caption) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "nook://tasks"))
    }
}
private struct AnniversaryWidgetView: View {
    let entry: NookEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Anniversary", systemImage: "heart").font(.caption.bold()).foregroundStyle(.pink)
            if let snapshot = entry.snapshot, let day = snapshot.anniversaryDate {
                Text(snapshot.anniversaryTitle ?? String(localized: "Next Anniversary")).font(.headline).lineLimit(2).privacySensitive(snapshot.showsDetails)
                let count = LocalDate.today(now: entry.date).days(to: day)
                Text("\(max(0, count)) days").font(.title2.bold())
            } else { Text("Open Nook to add an anniversary.").font(.caption) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(.fill.tertiary, for: .widget).widgetURL(URL(string: "nook://anniversaries"))
    }
}
struct NookTodayWidget: Widget {
    let kind = "NookToday"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NookProvider()) { TodayWidgetView(entry: $0) }
            .configurationDisplayName("Today in Nook").description("Your next event and tasks. Details are hidden until you enable them in Nook.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}
struct NookAnniversaryWidget: Widget {
    let kind = "NookAnniversary"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NookProvider()) { AnniversaryWidgetView(entry: $0) }
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
    var body: some Widget { NookTodayWidget(); NookAnniversaryWidget(); NookQuickWidget() }
}
