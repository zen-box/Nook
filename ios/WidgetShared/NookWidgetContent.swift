import SwiftUI
import NookCore

enum NookWidgetContentKind: String, CaseIterable, Identifiable {
    case schedule, trips, notes, anniversary
    var id: Self { self }
    var title: LocalizedStringKey {
        switch self { case .schedule: "Schedule"; case .trips: "Trips"; case .notes: "Recent Note"; case .anniversary: "Anniversary" }
    }
    var symbol: String {
        switch self { case .schedule: "calendar"; case .trips: "tram.fill"; case .notes: "note.text"; case .anniversary: "heart.fill" }
    }
    var url: URL {
        URL(string: "nook://\(self == .anniversary ? "anniversaries" : rawValue)")!
    }
}

/// Compiled into the app's preview and the extension, so the preview uses the actual layout.
struct NookWidgetContent: View {
    let kind: NookWidgetContentKind
    let data: WidgetSharedData
    var date = Date()
    var medium = false
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 8) {
            Label(kind.title, systemImage: kind.symbol)
                .font(.caption.weight(.semibold)).foregroundStyle(kind == .anniversary ? Color.pink : Color.blue)
            if let snapshot = data.snapshot {
                content(snapshot)
            } else {
                unavailable
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private func content(_ snapshot: WidgetSnapshot) -> some View {
        switch kind {
        case .schedule:
            let agenda = (snapshot.agenda ?? []).filter { $0.end > date || $0.start >= date }
            if let first = agenda.first {
                event(first, details: snapshot.showsDetails)
                if medium && !compact {
                    ForEach(Array(agenda.dropFirst().prefix(2).enumerated()), id: \.offset) { _, item in
                        HStack {
                            Text(item.title ?? String(localized: "Event")).lineLimit(1).privacySensitive(snapshot.showsDetails)
                            Spacer(minLength: 4)
                            if item.allDay { Text("All day") } else { Text(item.start, style: .time) }
                        }.font(.caption)
                    }
                }
            } else { Text("No upcoming events").font(.headline).lineLimit(2) }
            if !compact { Spacer(minLength: 0); Text("\(snapshot.openTaskCount) tasks remaining").font(.caption2).foregroundStyle(.secondary) }
        case .trips:
            if let trip = snapshot.trip {
                Text(trip.title ?? String(localized: "Next Trip")).font(.headline).lineLimit(compact ? 1 : 2).privacySensitive(snapshot.showsDetails)
                if let departure = trip.departure, departure >= date {
                    Text(departure, style: .time).font(compact ? .caption : .title3).monospacedDigit()
                } else {
                    let zone = snapshot.timeZoneID.flatMap(TimeZone.init(identifier:)) ?? .current
                    let count = LocalDate(date, timeZone: zone).days(to: trip.startDate)
                    if count > 0 { Text("In \(count) days").font(.subheadline) } else { Text("In progress").font(.subheadline) }
                }
                if !compact {
                    if medium, let route = trip.route, !route.isEmpty { Text(verbatim: route).font(.caption).lineLimit(2).privacySensitive() }
                    else if let destination = trip.destination, !destination.isEmpty { Text(verbatim: destination).font(.caption).lineLimit(1).privacySensitive() }
                    Spacer(minLength: 0)
                    Text(trip.startDate.date(hour: 12, in: .current), format: .dateTime.month(.abbreviated).day()).font(.caption2).foregroundStyle(.secondary)
                }
            } else { Text("No upcoming trips").font(.headline).lineLimit(2) }
        case .notes:
            if let count = snapshot.noteCount, count > 0 {
                Text(snapshot.noteTitle ?? String(localized: "Recent Note")).font(.headline).lineLimit(medium ? 3 : 2).privacySensitive(snapshot.showsDetails)
                if !compact { Spacer(minLength: 0); Text("\(count) notes").font(.caption).foregroundStyle(.secondary) }
            } else { Text("No notes yet").font(.headline).lineLimit(2) }
        case .anniversary:
            if let day = snapshot.anniversaryDate {
                Text(snapshot.anniversaryTitle ?? String(localized: "Next Anniversary")).font(.headline).lineLimit(compact ? 1 : 2).privacySensitive(snapshot.showsDetails)
                let zone = snapshot.timeZoneID.flatMap(TimeZone.init(identifier:)) ?? .current
                let count = LocalDate(date, timeZone: zone).days(to: day)
                if count >= 0 { Text("\(count) days").font(compact ? .caption : .title2).bold() }
                else { Text("Open Nook to refresh dates.").font(.caption) }
            } else { Text("No anniversaries yet").font(.headline).lineLimit(2) }
        }
    }

    private func event(_ item: WidgetAgendaItem, details: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title ?? String(localized: "Next Event")).font(.headline).lineLimit(compact ? 1 : 2).privacySensitive(details)
            if item.allDay { Text("All day").font(.caption) }
            else {
                HStack(spacing: 5) {
                    Text(item.start, style: .time).monospacedDigit()
                    if item.start < date && item.end > date { Text("Now").font(.caption2).foregroundStyle(.secondary) }
                }.font(compact ? .caption : .title3)
            }
        }
    }

    @ViewBuilder private var unavailable: some View {
        switch data {
        case .groupUnavailable:
            Text("Widget sharing permission is missing.").font(.caption.weight(.semibold))
            if !compact { Text("The app and widget must be signed with the same App Group.").font(.caption2).foregroundStyle(.secondary) }
        case .awaitingData:
            Text("No shared data yet. Refresh Widget Data in Nook Settings.").font(.caption)
        case .unreadableData:
            Text("Shared data could not be read. Unlock your iPhone and refresh Widget Data in Nook.").font(.caption)
        case .ready: EmptyView()
        }
    }
}
