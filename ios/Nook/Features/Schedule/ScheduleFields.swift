import SwiftUI
import NookCore

@MainActor
struct RecurrenceFields: View {
    @Binding var rule: EventRecurrence?
    let start: Date
    var body: some View {
        Section {
            Toggle("Repeats", isOn: Binding(get: { rule != nil }, set: { enabled in
                rule = enabled ? EventRecurrence(frequency: .weekly, weekdays: [LocalDate(start, timeZone: .current).isoWeekday]) : nil
            }))
            if rule != nil {
                Picker("Repeat", selection: binding(\.frequency, fallback: .weekly)) {
                    Text("Daily").tag(EventRecurrence.Frequency.daily)
                    Text("Weekly").tag(EventRecurrence.Frequency.weekly)
                    Text("Monthly").tag(EventRecurrence.Frequency.monthly)
                    Text("Yearly").tag(EventRecurrence.Frequency.yearly)
                }
                Stepper("Every \(rule?.interval ?? 1)", value: binding(\.interval, fallback: 1), in: 1...99)
                if rule?.frequency == .weekly {
                    HStack(spacing: 3) {
                        ForEach(1...7, id: \.self) { day in
                            Button {
                                var weekdays = rule?.weekdays ?? []
                                if weekdays.contains(day) { if weekdays.count > 1 { weekdays.removeAll { $0 == day } } }
                                else { weekdays.append(day) }
                                rule?.weekdays = weekdays.sorted()
                            } label: {
                                Text(verbatim: Calendar.current.veryShortStandaloneWeekdaySymbols[day % 7])
                                    .frame(maxWidth: .infinity).frame(height: 34)
                                    .background(rule?.weekdays.contains(day) == true ? Theme.accent : Theme.primarySoft, in: Circle())
                                    .foregroundStyle(rule?.weekdays.contains(day) == true ? .white : Theme.textPrimary)
                            }.buttonStyle(.plain)
                        }
                    }
                    Button("Weekdays") { rule?.weekdays = [1, 2, 3, 4, 5] }
                }
                Picker("Ends", selection: Binding(get: { rule?.endsOn != nil ? 1 : rule?.occurrenceLimit != nil ? 2 : 0 }, set: { value in
                    rule?.endsOn = value == 1 ? LocalDate(start, timeZone: .current).adding(days: 90) : nil
                    rule?.occurrenceLimit = value == 2 ? 10 : nil
                })) {
                    Text("Never").tag(0); Text("On Date").tag(1); Text("After Occurrences").tag(2)
                }
                if let day = rule?.endsOn {
                    DatePicker("Last Date", selection: Binding(get: { day.date(hour: 12, in: .current) }, set: { rule?.endsOn = LocalDate($0, timeZone: .current) }), displayedComponents: .date)
                }
                if rule?.occurrenceLimit != nil {
                    Stepper("\(rule?.occurrenceLimit ?? 10) occurrences", value: Binding(get: { rule?.occurrenceLimit ?? 10 }, set: { rule?.occurrenceLimit = $0 }), in: 1...999)
                }
            }
        } header: { Text("Repeat") } footer: {
            if rule != nil { Text("Repeats at the same local time. Monthly dates beyond the month's end use its last day.") }
        }
    }
    private func binding<T>(_ keyPath: WritableKeyPath<EventRecurrence, T>, fallback: T) -> Binding<T> {
        Binding(get: { rule?[keyPath: keyPath] ?? fallback }, set: { rule?[keyPath: keyPath] = $0 })
    }
}

@MainActor
struct TransportFields: View {
    @Binding var details: TransportDetails?
    var body: some View {
        Section {
            Toggle("Transport Details", isOn: Binding(get: { details != nil }, set: { details = $0 ? TransportDetails() : nil }))
            if details != nil {
                Picker("Transport", selection: binding(\.kind, .train)) {
                    Text("Train / High-speed Rail").tag(TransportDetails.Kind.train)
                    Text("Flight").tag(TransportDetails.Kind.flight)
                    Text("Other").tag(TransportDetails.Kind.other)
                }
                TextField(details?.kind == .flight ? "Flight Number" : "Train Number", text: binding(\.number, ""))
                TextField(details?.kind == .flight ? "Departure Airport" : "Departure Station", text: binding(\.departure, ""))
                TextField(details?.kind == .flight ? "Arrival Airport" : "Arrival Station", text: binding(\.arrival, ""))
                if details?.kind == .flight {
                    TextField("Terminal", text: binding(\.terminal, ""))
                    Toggle("Boarding Time", isOn: Binding(get: { details?.boardingAt != nil }, set: { details?.boardingAt = $0 ? Date() : nil }))
                    if details?.boardingAt != nil {
                        DatePicker("Boarding", selection: Binding(get: { details?.boardingAt ?? Date() }, set: { details?.boardingAt = $0 }))
                    }
                } else {
                    TextField("Carriage", text: binding(\.carriage, ""))
                    TextField("Platform", text: binding(\.platform, ""))
                }
                TextField(details?.kind == .flight ? "Boarding Gate" : "Check-in Gate", text: binding(\.gate, ""))
                TextField("Seat", text: binding(\.seat, ""))
                Picker("Departure Time Zone", selection: binding(\.departureTimeZone, TimeZone.current.identifier)) {
                    ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text(verbatim: $0).tag($0) }
                }
                Picker("Arrival Time Zone", selection: binding(\.arrivalTimeZone, TimeZone.current.identifier)) {
                    ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text(verbatim: $0).tag($0) }
                }
            }
        } header: { Text("Travel Information") } footer: { Text("Optional fields can be filled later. Times and reminders use your saved information; live delays and gate changes are not fetched.") }
    }
    private func binding<T>(_ keyPath: WritableKeyPath<TransportDetails, T>, _ fallback: T) -> Binding<T> {
        Binding(get: { details?[keyPath: keyPath] ?? fallback }, set: { details?[keyPath: keyPath] = $0 })
    }
}
