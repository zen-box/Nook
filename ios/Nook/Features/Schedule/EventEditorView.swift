import SwiftUI
import NookCore

struct EventEditorView: View {
    enum Mode {
        case create(LocalDate)
        case edit(UUID)
        case occurrence(UUID, Date)
    }

    let mode: Mode
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var location = ""
    @State private var notes = ""
    @State private var category: EventCategory = .work
    @State private var isAllDay = false
    @State private var start = Date()
    @State private var end = Date()
    @State private var reminder: Int? = 10
    @State private var tripID: UUID?
    @State private var loaded = false
    @State private var confirmDelete = false
    @State private var recurrence: EventRecurrence?
    @State private var transport: TransportDetails?
    @State private var scopeDialog = false
    @State private var chosenScope: String?
    @State private var deletingSeries = false
    @State private var error: String?

    /// Minutes before the start.
    static let reminderOptions = [0, 5, 10, 15, 30, 60, 120, 1440]

    static func reminderLabel(_ minutes: Int) -> LocalizedStringKey {
        switch minutes {
        case 0: "At start time"
        case 60: "1 hour before"
        case 120: "2 hours before"
        case 1440: "1 day before"
        default: "\(minutes) minutes before"
        }
    }

    private var isEditing: Bool {
        switch mode {
        case .create: false
        case .edit, .occurrence: true
        }
    }

    private var components: DatePickerComponents {
        isAllDay ? [.date] : [.date, .hourAndMinute]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    TextField("Location", text: $location)
                }
                Section {
                    Picker("Category", selection: $category) {
                        ForEach(EventCategory.allCases, id: \.self) { option in
                            Label(option.label, systemImage: option.symbol).tag(option)
                        }
                    }
                }
                Section {
                    Toggle("All day", isOn: $isAllDay)
                    DatePicker("Starts", selection: $start, displayedComponents: components)
                        .environment(\.timeZone, transport.flatMap { TimeZone(identifier: $0.departureTimeZone) } ?? store.timeZone)
                    DatePicker("Ends", selection: $end, in: start..., displayedComponents: components)
                        .environment(\.timeZone, transport.flatMap { TimeZone(identifier: $0.arrivalTimeZone) } ?? store.timeZone)
                    Picker("Reminder", selection: $reminder) {
                            Text("None").tag(Int?.none)
                            ForEach(Self.reminderOptions, id: \.self) { minutes in
                                Text(Self.reminderLabel(minutes)).tag(Int?.some(minutes))
                            }
                    }
                }
                RecurrenceFields(rule: $recurrence, start: start)
                TransportFields(details: $transport)
                Text("Local notifications follow your saved times. Allow notifications in iOS Settings. Past reminder times are skipped.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
                if !store.trips.isEmpty {
                    Section {
                        Picker("Trip", selection: $tripID) {
                            Text("None").tag(UUID?.none)
                            ForEach(store.tripsByDate) { trip in
                                Text(trip.title).tag(UUID?.some(trip.id))
                            }
                        }
                    }
                }
                Section("Details") {
                    TextField("Add notes", text: $notes, axis: .vertical)
                        .lineLimit(3...)
                }
                if let error { Text(verbatim: error).foregroundStyle(Pastel.rose.strong) }
                if isEditing {
                    Section {
                        Button("Delete Event", role: .destructive) {
                            confirmDelete = true
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(isEditing ? Text("Edit Event") : Text("New Event"))
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
            .confirmationDialog("Delete this event?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Event", role: .destructive) {
                    deleteAndClose()
                }
            }
            .confirmationDialog("Apply to which events?", isPresented: $scopeDialog, titleVisibility: .visible) {
                Button("Only This Event") { chosenScope = "this"; finishScopedAction() }
                Button("This and Future Events") { chosenScope = "future"; finishScopedAction() }
                Button("All Events in Series") { chosenScope = "series"; finishScopedAction() }
            }
        }
        .onAppear { load() }
        .onChange(of: start) { _, newStart in
            if end < newStart {
                end = newStart.addingTimeInterval(3600)
            }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(28)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        switch mode {
        case .create(let day):
            let isToday = day == LocalDate.today(in: store.timeZone)
            let hour = isToday ? min(Calendar.current.component(.hour, from: Date()) + 1, 23) : 9
            start = day.date(hour: hour, in: store.timeZone)
            end = start.addingTimeInterval(3600)
            // A new event during a trip belongs to it.
            tripID = store.trips.first { $0.startDate <= day && day <= $0.endDate }?.id
        case .edit(let id), .occurrence(let id, _):
            guard let event = store.event(id: id) else { return }
            title = event.title
            location = event.location ?? ""
            notes = event.notes
            category = event.category
            isAllDay = event.isAllDay
            let selectedStart: Date
            if case .occurrence(_, let date) = mode { selectedStart = date } else { selectedStart = event.start }
            start = selectedStart
            reminder = event.reminderMinutes
            recurrence = event.recurrence
            transport = event.transport
            tripID = event.planID
            if event.isAllDay {
                // Stored ends are exclusive (next midnight); show the last day instead.
                end = selectedStart.addingTimeInterval(max(0, event.effectiveEnd.timeIntervalSince(event.start) - 1))
            } else {
                end = selectedStart.addingTimeInterval(event.end.map { $0.timeIntervalSince(event.start) } ?? 3600)
            }
        }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let zone = store.timeZone
        let eventStart: Date
        let eventEnd: Date
        if isAllDay {
            let firstDay = LocalDate(start, timeZone: zone)
            let lastDay = max(LocalDate(end, timeZone: zone), firstDay)
            eventStart = firstDay.startDate(in: zone)
            eventEnd = lastDay.adding(days: 1).startDate(in: zone)
        } else {
            eventStart = start
            eventEnd = max(end, start)
        }
        var event: ScheduleEvent
        switch mode {
        case .create:
            event = ScheduleEvent(title: trimmed, start: eventStart)
        case .edit(let id), .occurrence(let id, _):
            guard let existing = store.event(id: id) else {
                dismiss()
                return
            }
            event = existing
        }
        let place = location.trimmingCharacters(in: .whitespacesAndNewlines)
        event.title = trimmed
        event.start = eventStart
        event.end = eventEnd
        event.isAllDay = isAllDay
        event.location = place.isEmpty ? nil : place
        event.notes = notes
        event.category = category
        event.reminderMinutes = reminder
        event.planID = tripID
        event.recurrence = recurrence
        event.transport = transport
        do {
            try AgentPlanner.validate(try .from(event), kind: .event)
            if let existing = originalEvent, existing.recurrence != nil {
                guard let chosenScope else { deletingSeries = false; scopeDialog = true; return }
                var fields = try JSONValue.from(event).object!
                for key in ["id", "created_at", "updated_at", "series_id", "occurrence_start"] { fields.removeValue(forKey: key) }
                if recurrence == existing.recurrence { fields.removeValue(forKey: "recurrence") }
                let action = AgentAction(kind: .event, operation: .update, id: existing.id, fields: fields,
                                         scope: chosenScope, occurrenceStart: selectedOccurrence)
                let plan = try AgentPlanner.prepare([action], records: store.assistantRecords(), summary: trimmed, currency: store.currencyCode)
                try store.applyAssistantPlan(plan)
            } else {
                guard store.saveEvent(event) else { error = String(localized: "Couldn't save the change"); return }
            }
        } catch { self.error = error.localizedDescription; return }
        router.selectedDay = LocalDate(eventStart, timeZone: zone)
        dismiss()
    }

    private func deleteAndClose() {
        if let existing = originalEvent {
            if existing.recurrence != nil {
                guard let chosenScope else { deletingSeries = true; scopeDialog = true; return }
                do {
                    let action = AgentAction(kind: .event, operation: .delete, id: existing.id, scope: chosenScope, occurrenceStart: selectedOccurrence)
                    let plan = try AgentPlanner.prepare([action], records: store.assistantRecords(), summary: existing.title, currency: store.currencyCode)
                    try store.applyAssistantPlan(plan)
                } catch { self.error = error.localizedDescription; return }
            } else { guard store.deleteEvent(existing.id) else { return } }
        }
        dismiss()
    }
    private var originalEvent: ScheduleEvent? {
        switch mode { case .create: nil; case .edit(let id), .occurrence(let id, _): store.event(id: id) }
    }
    private var selectedOccurrence: Date? {
        if case .occurrence(_, let date) = mode { return date }
        return originalEvent?.start
    }
    private func finishScopedAction() { if deletingSeries { deleteAndClose() } else { save() } }
}
