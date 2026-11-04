import SwiftUI
import NookCore

struct EventEditorView: View {
    enum Mode {
        case create(LocalDate)
        case edit(UUID)
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
        case .edit: true
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
                    DatePicker("Ends", selection: $end, in: start..., displayedComponents: components)
                    if !isAllDay {
                        Picker("Reminder", selection: $reminder) {
                            Text("None").tag(Int?.none)
                            ForEach(Self.reminderOptions, id: \.self) { minutes in
                                Text(Self.reminderLabel(minutes)).tag(Int?.some(minutes))
                            }
                        }
                    }
                }
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
        case .edit(let id):
            guard let event = store.event(id: id) else { return }
            title = event.title
            location = event.location ?? ""
            notes = event.notes
            category = event.category
            isAllDay = event.isAllDay
            start = event.start
            reminder = event.reminderMinutes
            tripID = event.planID
            if event.isAllDay {
                // Stored ends are exclusive (next midnight); show the last day instead.
                end = max(event.effectiveEnd.addingTimeInterval(-1), event.start)
            } else {
                end = event.end ?? event.start.addingTimeInterval(3600)
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
        case .edit(let id):
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
        event.reminderMinutes = isAllDay ? nil : reminder
        event.planID = tripID
        guard store.saveEvent(event) else { return }
        router.selectedDay = LocalDate(eventStart, timeZone: zone)
        dismiss()
    }

    private func deleteAndClose() {
        if case .edit(let id) = mode {
            guard store.deleteEvent(id) else { return }
        }
        dismiss()
    }
}
