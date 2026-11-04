import SwiftUI
import NookCore

struct TripEditorView: View {
    let tripID: UUID?
    var transportEventID: UUID? = nil
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var destination = ""
    @State private var summary = ""
    @State private var start = Date()
    @State private var end = Date().addingTimeInterval(3 * 86_400)
    @State private var loaded = false
    @State private var confirmDelete = false
    @State private var transport: TransportDetails?
    @State private var departure = Date()
    @State private var arrival = Date().addingTimeInterval(3600)
    @State private var reminder: Int? = 30
    @State private var originalTrip: TripPlan?
    @State private var originalJourney: ScheduleEvent?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Trip name", text: $title).accessibilityIdentifier("trip.title")
                    TextField("Destination", text: $destination)
                }
                Section {
                    DatePicker("Starts", selection: $start, displayedComponents: .date)
                    DatePicker("Ends", selection: $end, in: start..., displayedComponents: .date)
                }
                Section {
                    TextField("What's the plan?", text: $summary, axis: .vertical)
                        .lineLimit(3...)
                } header: {
                    Text("Details")
                } footer: {
                    Text("Add transport below for departure reminders. You can also group other calendar events in this trip.")
                }
                Section {
                    Toggle("Transport Details", isOn: Binding(get: { transport != nil }, set: { transport = $0 ? TransportDetails() : nil }))
                        .accessibilityIdentifier("trip.transport")
                } footer: {
                    if originalJourney != nil { Text("Turning this off removes this timed transport segment when you save the trip.") }
                }
                if transport != nil {
                    Section("Departure and Arrival") {
                        DatePicker("Departure", selection: $departure)
                            .environment(\.timeZone, TimeZone(identifier: transport?.departureTimeZone ?? "") ?? store.timeZone)
                        DatePicker("Arrival", selection: $arrival, in: departure...)
                            .environment(\.timeZone, TimeZone(identifier: transport?.arrivalTimeZone ?? "") ?? store.timeZone)
                        Picker("Reminder", selection: $reminder) {
                            Text("None").tag(Int?.none)
                            ForEach(EventEditorView.reminderOptions, id: \.self) { value in
                                Text(EventEditorView.reminderLabel(value)).tag(Int?.some(value))
                            }
                        }
                    }
                    TransportFields(details: $transport, showsToggle: false)
                }
                if let error { Text(verbatim: error).foregroundStyle(Pastel.rose.strong) }
                if tripID != nil {
                    Section {
                        Button("Delete Trip", role: .destructive) {
                            confirmDelete = true
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(tripID == nil ? Text("New Trip") : Text("Edit Trip"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .accessibilityIdentifier("trip.save")
                        .fontWeight(.semibold)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmationDialog("Delete this trip?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Trip", role: .destructive) {
                    if let tripID {
                        guard store.deleteTrip(tripID) else { return }
                    }
                    dismiss()
                }
            } message: {
                Text("Its events and plan note are kept.")
            }
        }
        .onAppear { load() }
        .onChange(of: start) { _, newStart in
            if end < newStart {
                end = newStart
            }
        }
        .onChange(of: departure) { _, value in if arrival < value { arrival = value.addingTimeInterval(3600) } }
        .presentationDetents([.large])
        .presentationCornerRadius(28)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let tripID, let trip = store.trip(id: tripID) {
            originalTrip = trip
            title = trip.title; destination = trip.destination ?? ""; summary = trip.summary
            start = trip.startDate.noon; end = trip.endDate.noon
        }
        let linkedJourneys: [ScheduleEvent] = store.events.filter { tripID != nil && $0.planID == tripID && $0.transport != nil }
        let journey: ScheduleEvent? = transportEventID.flatMap { store.event(id: $0) } ?? linkedJourneys.min { $0.start < $1.start }
        if let journey {
            originalJourney = journey; transport = journey.transport
            departure = journey.start; arrival = journey.end ?? journey.start.addingTimeInterval(3600)
            reminder = journey.reminderMinutes
            if originalTrip == nil {
                title = journey.title; destination = journey.transport?.arrival ?? ""
                start = journey.start; end = journey.end ?? journey.start
            }
        }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let zone = store.timeZone
        let first = LocalDate(start, timeZone: zone)
        let last = max(LocalDate(end, timeZone: zone), first)
        var trip: TripPlan
        if let existing = originalTrip {
            trip = existing
        } else {
            trip = TripPlan(title: trimmed, startDate: first, endDate: last)
        }
        let place = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        trip.title = trimmed
        trip.destination = place.isEmpty ? nil : place
        trip.startDate = first
        trip.endDate = last
        trip.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            var journey: ScheduleEvent?
            if let transport {
                var segment = originalJourney ?? ScheduleEvent(title: trimmed, start: departure)
                segment.title = originalJourney?.title ?? trimmed
                segment.start = departure; segment.end = arrival; segment.transport = transport
                segment.reminderMinutes = reminder
                journey = segment
            }
            let plan = try TripJourneyPlan.make(trip: trip, previousTrip: originalTrip, journey: journey, previousJourney: originalJourney)
            try store.applyAssistantPlan(plan)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct AnniversaryEditorView: View {
    let anniversaryID: UUID?
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var date = Date()
    @State private var kind: AnniversaryKind = .birthday
    @State private var repeatsYearly = true
    @State private var reminderEnabled = false
    @State private var reminderTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var reminderDays: Set<Int> = [0]
    @State private var notes = ""
    @State private var loaded = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $title)
                    Picker("Type", selection: $kind) {
                        ForEach(AnniversaryKind.allCases, id: \.self) { option in
                            Label(option.label, systemImage: option.symbol).tag(option)
                        }
                    }
                }
                Section {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Toggle("Repeats every year", isOn: $repeatsYearly)
                } footer: {
                    Text("Use the original date, such as the date of birth, to see how many years it has been.")
                }
                Section("Reminder") {
                    Toggle("Remind Me", isOn: $reminderEnabled)
                    if reminderEnabled {
                        DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                        ForEach([0, 1, 3, 7, 14, 30], id: \.self) { days in
                            Toggle(isOn: Binding(get: { reminderDays.contains(days) }, set: { on in
                                if on { reminderDays.insert(days) } else { reminderDays.remove(days) }
                            })) {
                                if days == 0 { Text("On the day") } else { Text("\(days) days before") }
                            }
                        }
                    }
                }
                Section("Details") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...)
                }
                if anniversaryID != nil {
                    Section {
                        Button("Delete Anniversary", role: .destructive) {
                            confirmDelete = true
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(anniversaryID == nil ? Text("New Anniversary") : Text("Edit Anniversary"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmationDialog("Delete this anniversary?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Anniversary", role: .destructive) {
                    if let anniversaryID {
                        guard store.deleteAnniversary(anniversaryID) else { return }
                    }
                    dismiss()
                }
            }
        }
        .onAppear { load() }
        .presentationDetents([.large])
        .presentationCornerRadius(28)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let anniversaryID, let anniversary = store.anniversary(id: anniversaryID) else { return }
        title = anniversary.title
        date = anniversary.date.noon
        kind = anniversary.kind
        repeatsYearly = anniversary.repeatRule == .yearly
        notes = anniversary.notes
        if let reminder = anniversary.reminder {
            reminderEnabled = true; reminderDays = Set(reminder.daysBefore)
            reminderTime = Calendar.current.date(bySettingHour: reminder.hour, minute: reminder.minute, second: 0, of: Date()) ?? Date()
        }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let day = LocalDate(date, timeZone: store.timeZone)
        var anniversary: Anniversary
        if let anniversaryID, let existing = store.anniversary(id: anniversaryID) {
            anniversary = existing
        } else {
            anniversary = Anniversary(title: trimmed, date: day)
        }
        anniversary.title = trimmed
        anniversary.date = day
        anniversary.kind = kind
        anniversary.repeatRule = repeatsYearly ? .yearly : .never
        anniversary.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        anniversary.reminder = reminderEnabled ? AnniversaryReminder(hour: Calendar.current.component(.hour, from: reminderTime),
            minute: Calendar.current.component(.minute, from: reminderTime), daysBefore: reminderDays.isEmpty ? [0] : reminderDays.sorted()) : nil
        guard store.saveAnniversary(anniversary) else { return }
        dismiss()
    }
}
